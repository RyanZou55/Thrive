@preconcurrency import AVFoundation
import OSLog
import UIKit

/// 把录下来的那段视频，按选好的时刻抽成一组帧。
enum SpinExtractor {
    private static let logger = Logger(subsystem: "com.ryanzou.thrive", category: "SpinExtractor")

    /// 抽帧。`frames` 里的 time 是 uptime，减去录制起点才是视频里的秒数。
    ///
    /// 容差设成 zero：转盘要的是严格等角间隔，让生成器就近找关键帧会让间隔忽大忽小。
    static func extractFrames(
        fromMovieAt url: URL,
        frames: [SpinFrameSelector.Frame],
        recordingStartUptime: TimeInterval
    ) async -> [UIImage] {
        guard !frames.isEmpty else { return [] }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // 让生成器直接出小图，比出 4K 再自己缩省内存也省时间。
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let times = frames.map {
            CMTime(seconds: $0.time - recordingStartUptime, preferredTimescale: 600)
        }

        // images(for:) 不保证按请求顺序返回，按请求时间归位。
        var imagesByTime: [Double: UIImage] = [:]
        for await result in generator.images(for: times) {
            switch result {
            case let .success(requestedTime, image, _):
                imagesByTime[requestedTime.seconds] = UIImage(cgImage: image)
            case let .failure(requestedTime, error):
                logger.error("第 \(requestedTime.seconds, privacy: .public) 秒抽帧失败: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 缺帧就整组作废 —— 少一帧转起来会卡一下，比不给转更难受。
        let ordered = times.compactMap { imagesByTime[$0.seconds] }
        guard ordered.count == times.count else {
            logger.error("抽帧不全：要 \(times.count) 帧，只拿到 \(ordered.count) 帧")
            return []
        }
        return ordered
    }
}
