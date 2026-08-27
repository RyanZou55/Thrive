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

    /// 一组帧一起抠。
    ///
    /// 只要有一帧没抠成，整组都退回原图 —— 23 帧干净背景里混进一帧带房间的，
    /// 转到那儿会闪一下，比整组都留着背景更像出了 bug。
    static func matteAll(_ images: [UIImage]) async -> [UIImage] {
        guard !images.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            // 24 帧共用一个 CIContext。每帧新建一个的话，光是建上下文就比抠图本身还慢。
            let context = CIContext()
            var matted: [UIImage] = []
            matted.reserveCapacity(images.count)

            for image in images {
                guard let result = matte(image, context: context) else {
                    logger.info("有帧没抠出主体，整组保留原图")
                    return images
                }
                matted.append(result)
            }
            return matted
        }.value
    }

    private static func matte(_ image: UIImage, context: CIContext) -> UIImage? {
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
            return UIImage(cgImage: output)
        } catch {
            logger.error("抠图失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
