@preconcurrency import AVFoundation
import CoreImage
import OSLog
import UIKit

/// 录完之后到帧存好之间的整条流水线：挑帧 → 抽帧 → 抠图 → 对齐 → 落盘。
///
/// 一帧一帧地走，手里同时只有一两帧。
/// 24 帧 1280px 解码开来是 200MB 上下，全收进数组再处理会被系统直接杀掉。
enum SpinPipeline {
    private static let logger = Logger(subsystem: "com.ryanzou.thrive", category: "SpinPipeline")

    struct Output {
        /// 转盘帧文件名，顺序即角度顺序。
        var spinFilenames: [String]
        /// 第 0 帧的大图，存成记录的主照片。
        var coverImage: UIImage
        /// 这一圈走得稳不稳：对齐之前各帧之间的落差，单位是画面高度的比例。
        var wobble: Double
        /// 每一帧在视频里的时刻，和 spinFilenames 一一对应。
        /// 确认页换主照片要靠它回视频里重抽 —— 转盘帧只有 1280、抠过图又对齐过，当不了主照片。
        var frameTimes: [CMTime]
    }

    private enum Attempt {
        /// 帧文件名，以及各帧量出来的主体（不抠图时为空）。
        case saved([String], subjects: [SpinMatter.Subject])
        /// 有帧没抠出主体。整组重来，不抠图。
        case matteFailed
        case failed
    }

    private struct Aligned {
        var filenames: [String]
        var wobble: Double
    }

    /// 整组要对齐到的位置和大小，都取各帧的中位数。
    private struct Targets {
        var baseline: Double
        /// 只由没被切边的帧算出来。一组帧全都贴边时为 nil，那就整组都不缩放。
        var height: Double?
        var centerX: Double
    }

    /// 一帧该怎么改：绕 anchor 缩放 scale，再把 anchor 挪到 target。
    private struct Correction {
        var scale: CGFloat
        var anchor: CGPoint
        var target: CGPoint
    }

    /// 一帧最多上下挪画面高度的多少、左右挪画面宽度的多少。
    ///
    /// 基准取的是中位数，正常帧偏离不了多少；真挪到这个上限，说明那帧的主体
    /// 圈得离谱（比如把地面也抠进来了）。让它歪着，也别把植物推出画面。
    private static let maximumShiftRatio: CGFloat = 0.2
    private static let maximumHorizontalShiftRatio: CGFloat = 0.15
    /// 缩放最多修正一成。差得比这还多，多半是主体被画面边缘切掉了，量出来的高度不可信。
    private static let maximumScaleCorrection: CGFloat = 0.1

    /// 抖成什么样就该提醒重拍。0.12 是拍脑袋定的起点 —— 等真机拍够几十组再回来调。
    static let wobbleWarningThreshold = 0.12

    /// 挑清晰帧时，目标时刻前后各看多远。
    ///
    /// 正常步速下 40ms 只走过 0.6°，比 15° 的帧间隔小一个数量级，
    /// 换来的清晰度值这个偏差。
    private static let sharpnessSearchWindow = CMTime(value: 40, timescale: 1000)
    /// 评清晰度时的解码尺寸。再往下缩，模糊本身就被缩没了，分不出高低。
    private static let sharpnessScanDimension: CGFloat = 640

    static func process(
        movieAt url: URL,
        frames: [SpinFrameSelector.Frame],
        recordingStartUptime: TimeInterval
    ) async -> Output? {
        guard !frames.isEmpty else { return nil }

        let asset = AVURLAsset(url: url)
        var times = frames.map {
            CMTime(seconds: max(0, $0.time - recordingStartUptime), preferredTimescale: 600)
        }

        // 超过视频长度的时刻会直接取失败，而缺一帧是整组作废的 ——
        // 与其丢掉整组，不如把尾巴上超界的那几帧砍掉，当成转得短一点的一组。
        // 播放器对不满整圈的转盘本来就是拖到头就停，不会绕回去跳。
        var limit: Double?
        if let duration = try? await asset.load(.duration), duration.isNumeric {
            limit = duration.seconds
            let inRange = times.filter { $0.seconds < duration.seconds }
            if inRange.count < times.count {
                logger.info("有 \(times.count - inRange.count) 帧落在视频结束之后，砍掉")
                times = inRange
            }
        }
        guard times.count >= SpinFrameSelector.minimumFrames else {
            logger.error("砍完不够 \(SpinFrameSelector.minimumFrames) 帧，这组不要了")
            return nil
        }

        times = await sharpestTimes(asset: asset, around: times, before: limit)

        var filenames: [String]
        var wobble = 0.0
        switch await attemptSave(asset: asset, times: times, matting: true) {
        case let .saved(names, subjects):
            let aligned = alignFrames(filenames: names, subjects: subjects)
            filenames = aligned.filenames
            wobble = aligned.wobble
        case .matteFailed:
            // 没有抠图就量不到主体，这条路上的帧只能保持原样 —— 晃就晃着。
            logger.info("有帧没抠出主体，整组不抠图重来")
            guard case let .saved(names, _) = await attemptSave(asset: asset, times: times, matting: false) else {
                return nil
            }
            filenames = names
        case .failed:
            return nil
        }

        guard let cover = await frameImage(asset: asset, at: times[0], maxDimension: 2048) else {
            PhotoStore.shared.deleteSpinFrames(filenames)
            return nil
        }
        return Output(spinFilenames: filenames, coverImage: cover, wobble: wobble, frameTimes: times)
    }

    /// 转盘没成的时候，把开头那一帧捞出来当普通生长照 —— 走都走了，别让人空手回去。
    static func singleFrame(movieAt url: URL) async -> UIImage? {
        await frameImage(asset: AVURLAsset(url: url), at: .zero, maxDimension: 2048)
    }

    /// 确认页改用别的帧当主照片时，按那一帧的时刻回视频里重抽一张大图。
    /// 只在临时视频还没删的时候叫得动。
    static func frameImage(movieAt url: URL, at time: CMTime) async -> UIImage? {
        await frameImage(asset: AVURLAsset(url: url), at: time, maxDimension: 2048)
    }

    /// 抽一遍并逐帧落盘。中途出问题就把已经写下去的删干净，不留半组。
    private static func attemptSave(
        asset: AVURLAsset,
        times: [CMTime],
        matting: Bool
    ) async -> Attempt {
        let generator = makeGenerator(asset: asset, maxDimension: 1280)

        // images(for:) 不保证按请求顺序返回，靠请求时刻归位。
        var indexByTime: [Double: Int] = [:]
        for (index, time) in times.enumerated() {
            indexByTime[time.seconds] = index
        }

        var slots = [String?](repeating: nil, count: times.count)
        var subjectSlots = [SpinMatter.Subject?](repeating: nil, count: times.count)
        let context = CIContext()

        func rollback() {
            PhotoStore.shared.deleteSpinFrames(slots.compactMap { $0 })
        }

        for await result in generator.images(for: times) {
            guard case let .success(requestedTime, cgImage, _) = result,
                  let index = indexByTime[requestedTime.seconds]
            else {
                if case let .failure(requestedTime, error) = result {
                    logger.error("第 \(requestedTime.seconds, privacy: .public) 秒抽帧失败: \(error.localizedDescription, privacy: .public)")
                }
                continue
            }

            var image = UIImage(cgImage: cgImage)
            if matting {
                guard let matted = SpinMatter.matte(image, context: context) else {
                    rollback()
                    return .matteFailed
                }
                image = matted.image
                subjectSlots[index] = matted.subject
            }

            guard let filename = PhotoStore.shared.saveSpinFrame(image) else {
                rollback()
                return .failed
            }
            slots[index] = filename
        }

        let filenames = slots.compactMap { $0 }
        // 缺帧就整组作废 —— 少一帧转起来会卡一下，比不给转更难受。
        guard filenames.count == times.count else {
            logger.error("抽帧不全：要 \(times.count) 帧，只拿到 \(filenames.count) 帧")
            rollback()
            return .failed
        }
        return .saved(filenames, subjects: subjectSlots.compactMap { $0 })
    }

    // MARK: - 挑清晰的那一帧

    /// 每个目标时刻前后各看一眼，挑最清楚的那张。
    ///
    /// 走着拍必然带运动模糊，而抽帧是卡死在算出来的那个时刻取的 —— 正好落在糊的那帧上就只能认。
    /// 这一趟只解到 640px 用来评分，真正要留的帧回头再按原尺寸重抽。
    private static func sharpestTimes(
        asset: AVURLAsset,
        around times: [CMTime],
        before limit: Double?
    ) async -> [CMTime] {
        var candidates: [CMTime] = []
        var indexByTime: [Double: Int] = [:]
        for (index, time) in times.enumerated() {
            let window = searchWindow(at: index, in: times)
            for candidate in [CMTimeSubtract(time, window), time, CMTimeAdd(time, window)] {
                guard candidate.seconds >= 0, limit.map({ candidate.seconds < $0 }) ?? true else { continue }
                guard indexByTime[candidate.seconds] == nil else { continue }
                indexByTime[candidate.seconds] = index
                candidates.append(candidate)
            }
        }

        var best = times
        var bestScore = [Double](repeating: -1, count: times.count)
        let generator = makeGenerator(asset: asset, maxDimension: sharpnessScanDimension)

        for await result in generator.images(for: candidates) {
            guard case let .success(requestedTime, cgImage, _) = result,
                  let index = indexByTime[requestedTime.seconds]
            else { continue }

            let score = sharpness(of: cgImage)
            if score > bestScore[index] {
                bestScore[index] = score
                best[index] = requestedTime
            }
        }
        return best
    }

    /// 这一帧能往前后找多远。
    ///
    /// 最多 40ms，但不超过到左右邻居间距的一半：两个目标挨得比 80ms 还近时
    /// （快速回正镜头，一个采样间隔里跨过好几个 15° 的坎），各自张满 40ms 的窗口会重叠，
    /// 前一帧挑到后面、后一帧挑到前面，存下来的帧就前后颠倒了，转到那儿会倒退一下。
    /// 卡在中点上最坏也只是两帧选到同一时刻，顺序不会乱。
    private static func searchWindow(at index: Int, in times: [CMTime]) -> CMTime {
        var seconds = sharpnessSearchWindow.seconds
        if index > 0 {
            seconds = min(seconds, (times[index].seconds - times[index - 1].seconds) / 2)
        }
        if index + 1 < times.count {
            seconds = min(seconds, (times[index + 1].seconds - times[index].seconds) / 2)
        }
        return CMTime(seconds: max(0, seconds), preferredTimescale: 1000)
    }

    /// 梯度能量，越大越清楚。
    ///
    /// 只在同一个目标时刻的几个候选之间比大小 —— 它们相差几十毫秒，画面内容几乎一样，
    /// 比出来的差别就是糊的程度。跨时刻比没有意义：背景换了，能量也就换了。
    private static func sharpness(of cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 1,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return 0 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }

        // 像素缓冲区是 context 持有的，扫完之前不能让它被释放。
        return withExtendedLifetime(context) { () -> Double in
            let pixels = data.assumingMemoryBound(to: UInt8.self)

            var total = 0
            for row in 0..<(height - 1) {
                let offset = row * width
                for column in 0..<(width - 1) {
                    let value = Int(pixels[offset + column])
                    total += abs(Int(pixels[offset + column + 1]) - value)
                    total += abs(Int(pixels[offset + width + column]) - value)
                }
            }
            return Double(total) / Double((width - 1) * (height - 1))
        }
    }

    // MARK: - 对齐

    /// 把每帧的主体挪到同一个位置、缩到同一个大小。
    ///
    /// 绕着走没法把手机端在固定高度和固定距离上，成片里植物就会上下晃、忽大忽小 ——
    /// 而抠完图之后，主体的底边、高度、盆底中心正好把这几个偏差都写在脸上了，逐帧纠回去就行。
    ///
    /// 基准全取中位数，而不是拿第 0 帧当准：真要是起手那一下举得偏高偏低，
    /// 剩下二十几帧会被整体推到画面边上，还得连带切掉一截。
    ///
    /// 改过的帧要重新编码一次（HEIC 0.7），所以挪不到一个像素的就别动。
    private static func alignFrames(filenames: [String], subjects: [SpinMatter.Subject]) -> Aligned {
        guard subjects.count == filenames.count,
              let baseline = median(of: subjects.map(\.baseline)),
              let centerX = median(of: subjects.map(\.baseCenterX))
        else { return Aligned(filenames: filenames, wobble: 0) }

        // 贴边的帧高度是截断的，既不能进中位数也不能进抖动指标 —— 否则「离得太近
        // 把盆切掉了」会被读成「植株变矮了」，缩放和警告都跟着反过来。
        let intactHeights = subjects.filter { !$0.isClipped }.map(\.height)
        let targets = Targets(baseline: baseline, height: median(of: intactHeights), centerX: centerX)
        // 底边和高度的落差都是按画面高度算的，取大的那个当这一圈的抖动指标。
        let wobble = max(spread(of: subjects.map(\.baseline)), spread(of: intactHeights))

        var aligned = filenames
        for (index, filename) in filenames.enumerated() {
            guard let image = PhotoStore.shared.spinFrame(
                named: filename,
                maxPixelSize: Int(PhotoStore.spinMaxDimension)
            ) else { continue }

            let size = image.size
            let correction = correction(for: subjects[index], towards: targets, in: size)
            let moved = hypot(correction.target.x - correction.anchor.x, correction.target.y - correction.anchor.y)
            guard moved >= 1 || abs(correction.scale - 1) * size.height >= 1 else { continue }

            // 改不成就留着原来那张：这一帧不对齐而已，整组还是能转。
            guard let correctedName = PhotoStore.shared.saveSpinFrame(transformed(image, by: correction)) else {
                logger.error("第 \(index) 帧对齐后没存下来，保留原帧")
                continue
            }
            PhotoStore.shared.delete(filename: filename)
            aligned[index] = correctedName
        }
        return Aligned(filenames: aligned, wobble: wobble)
    }

    /// 算一帧要挪多少、缩多少。缩放和平移都绕着盆底中心做。
    ///
    /// 被画面切掉一截的帧只挪不缩：它量到的高度比真实的矮，照着缩会把最近的那几帧
    /// 越放越大。挪还是要挪的 —— 底边虽然也被截断，但方向没错，只是纠得不够。
    private static func correction(
        for subject: SpinMatter.Subject,
        towards targets: Targets,
        in size: CGSize
    ) -> Correction {
        var scale: CGFloat = 1
        if !subject.isClipped, let targetHeight = targets.height {
            scale = min(
                max(CGFloat(targetHeight / subject.height), 1 - maximumScaleCorrection),
                1 + maximumScaleCorrection
            )
        }
        let anchor = CGPoint(x: subject.baseCenterX * size.width, y: subject.baseline * size.height)
        let target = CGPoint(
            x: anchor.x + clamped(
                CGFloat(targets.centerX - subject.baseCenterX) * size.width,
                limit: size.width * maximumHorizontalShiftRatio
            ),
            y: anchor.y + clamped(
                CGFloat(targets.baseline - subject.baseline) * size.height,
                limit: size.height * maximumShiftRatio
            )
        )
        return Correction(scale: scale, anchor: anchor, target: target)
    }

    /// 绕 anchor 缩放，再把 anchor 挪到 target。画布大小不变，空出来的部分留透明
    /// —— 背景本来就是透明的，看不出补过。
    private static func transformed(_ image: UIImage, by correction: Correction) -> UIImage {
        let size = image.size
        let scale = correction.scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(
                x: correction.target.x - correction.anchor.x * scale,
                y: correction.target.y - correction.anchor.y * scale,
                width: size.width * scale,
                height: size.height * scale
            ))
        }
    }

    private static func clamped(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        min(max(value, -limit), limit)
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func spread(of values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }

    // MARK: - 抽帧

    /// 单张抽帧。主照片走这条路，尺寸放到 2048 —— 它要当封面和下次拍照的叠影底图，
    /// 不能跟转盘帧一样只有 1280。
    private static func frameImage(
        asset: AVURLAsset,
        at time: CMTime,
        maxDimension: CGFloat
    ) async -> UIImage? {
        let generator = makeGenerator(asset: asset, maxDimension: maxDimension)
        for await result in generator.images(for: [time]) {
            if case let .success(_, cgImage, _) = result {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }

    /// 容差设成 zero：转盘要的是严格等角间隔，
    /// 让生成器就近找关键帧会让间隔忽大忽小。
    private static func makeGenerator(asset: AVURLAsset, maxDimension: CGFloat) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // 让生成器直接出小图，比出 4K 再自己缩省内存也省时间。
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        return generator
    }
}
