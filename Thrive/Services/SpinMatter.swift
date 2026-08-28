import CoreImage
import OSLog
import UIKit
import Vision

/// 把每帧里的植物抠出来，背景留成透明。
///
/// 绕着走拍出来的背景是跟着转的 —— 从沙发转到窗户，转起来非常晃眼。
/// 这是「绕着走」相对物理转盘的固有缺陷，只能靠抠图补。
///
/// 留透明而不是合到纯色底上：详情页在浅色和深色模式下底色不同，
/// 透明能跟着主题走，写死一个底色总有一边难看。
enum SpinMatter {
    private static let logger = Logger(subsystem: "com.ryanzou.thrive", category: "SpinMatter")

    /// 主体在画面里的位置和大小，全部按画面尺寸归一化 —— 流水线拿它把各帧对齐。
    struct Subject {
        /// 底边：0 是顶边，1 是底边。举手机的高度直接写在这个数上。
        var baseline: Double
        /// 主体高度，占画面高的比例。
        ///
        /// 绕垂直轴转不改变物体的真实高度，所以这个数的变化基本只反映远近 ——
        /// 拿它当缩放基准在几何上站得住。宽度不行，宽度本来就随角度变。
        var height: Double
        /// 盆底中心的水平位置：0 是左边，1 是右边。
        var baseCenterX: Double
        /// 主体贴着画面上边或下边 —— 多半是被切掉了一截。
        ///
        /// 这种帧量到的高度是截断的，比真实的矮，拿它当缩放依据会把「离得最近、
        /// 本来就最大」的那几帧越放越大，正好放反。所以它不参与高度中位数，自己也不缩放。
        var isClipped: Bool
    }

    /// 抠好的一帧，外加量出来的主体信息。
    struct Matted {
        var image: UIImage
        var subject: Subject
    }

    /// 抠一帧。抠不出主体返回 nil，由流水线决定整组怎么办
    /// （只要有一帧没抠成，整组都退回原图 —— 23 帧干净背景里混进一帧带房间的，
    /// 转到那儿会闪一下，比整组都留着背景更像出了 bug）。
    ///
    /// context 由调用方传进来，一组帧共用一个。每帧新建一个的话，
    /// 光是建上下文就比抠图本身还慢。
    static func matte(_ image: UIImage, context: CIContext) -> Matted? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }

            // croppedToInstancesExtent 必须是 false：按主体外框裁的话，
            // 每帧裁出来的框都不一样，转起来植物会在画面里跳。
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )

            let ciImage = CIImage(cvPixelBuffer: masked)
            guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            // 量不出主体等于这帧没抠出什么东西，跟抠图失败一样处理。
            guard let subject = measure(output) else { return nil }
            return Matted(image: UIImage(cgImage: output), subject: subject)
        } catch {
            logger.error("抠图失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 扫 alpha 量主体：底边、高度、盆底中心。
    ///
    /// 缩到长边 256 再扫：这几个量只用来做平移和缩放，几个像素的误差在 1280 的帧上看不出来，
    /// 而全分辨率扫 24 帧纯属白烧。
    private static func measure(_ cgImage: CGImage) -> Subject? {
        let longestSide = max(cgImage.width, cgImage.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, 256 / Double(longestSide))
        let width = max(1, Int(Double(cgImage.width) * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        // 像素缓冲区是 context 持有的，withExtendedLifetime 保证扫完之前它不会被释放
        // —— 否则 ARC 有权在 context.data 之后就把它放掉，下面读的就是已释放的内存。
        return withExtendedLifetime(context) { () -> Subject? in
            let pixels = data.assumingMemoryBound(to: UInt8.self)

            // 一行里至少要有这么多不透明像素才算主体：抠图边缘常留几个散点，
            // 拿它们当边界，量出来的东西会一帧一个样。
            let minimumOpaque = max(2, width / 100)

            // 位图里第 0 行是画面顶边。没主体的行留 -1。
            var rowMinX = [Int](repeating: 0, count: height)
            var rowMaxX = [Int](repeating: -1, count: height)
            for row in 0..<height {
                var opaque = 0
                var minX = width
                var maxX = -1
                let alphaBase = row * bytesPerRow + 3
                for column in 0..<width where pixels[alphaBase + column * 4] > 128 {
                    opaque += 1
                    minX = min(minX, column)
                    maxX = column
                }
                if opaque >= minimumOpaque {
                    rowMinX[row] = minX
                    rowMaxX[row] = maxX
                }
            }

            guard let top = (0..<height).first(where: { rowMaxX[$0] >= 0 }),
                  let bottom = (0..<height).last(where: { rowMaxX[$0] >= 0 })
            else { return nil }

            // 水平锚点只看盆底那一小段：整个轮廓的重心会随角度左右摆
            // —— 植株歪着长的话那是真实信息，抹掉反而假。盆底不会摆。
            let subjectHeight = bottom - top + 1
            let bandTop = max(top, bottom - max(1, subjectHeight / 10))
            var baseMinX = width
            var baseMaxX = -1
            for row in bandTop...bottom where rowMaxX[row] >= 0 {
                baseMinX = min(baseMinX, rowMinX[row])
                baseMaxX = max(baseMaxX, rowMaxX[row])
            }

            return Subject(
                baseline: Double(bottom + 1) / Double(height),
                height: Double(subjectHeight) / Double(height),
                baseCenterX: (Double(baseMinX) + Double(baseMaxX) + 1) / 2 / Double(width),
                isClipped: top == 0 || bottom == height - 1
            )
        }
    }
}
