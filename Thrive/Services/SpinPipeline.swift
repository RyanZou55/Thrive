@preconcurrency import AVFoundation
import CoreImage
import OSLog
import UIKit

/// 录完之后到帧存好之间的整条流水线：抽帧 → 抠图 → 落盘。
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
    }

    private enum Attempt {
        case saved([String])
        /// 有帧没抠出主体。整组重来，不抠图。
        case matteFailed
        case failed
    }

    static func process(
        movieAt url: URL,
        frames: [SpinFrameSelector.Frame],
        recordingStartUptime: TimeInterval
    ) async -> Output? {
        guard !frames.isEmpty else { return nil }

        let asset = AVURLAsset(url: url)
        let times = frames.map {
            CMTime(seconds: $0.time - recordingStartUptime, preferredTimescale: 600)
        }

        var filenames: [String]
        switch await attemptSave(asset: asset, times: times, matting: true) {
        case let .saved(names):
            filenames = names
        case .matteFailed:
            logger.info("有帧没抠出主体，整组不抠图重来")
            guard case let .saved(names) = await attemptSave(asset: asset, times: times, matting: false) else {
                return nil
            }
            filenames = names
        case .failed:
            return nil
        }

        guard let cover = await coverImage(asset: asset, at: times[0]) else {
            PhotoStore.shared.deleteSpinFrames(filenames)
            return nil
        }
        return Output(spinFilenames: filenames, coverImage: cover)
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
                image = matted
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
        return .saved(filenames)
    }

    /// 主照片单独抽一次，尺寸放到 2048 —— 它要当封面和下次拍照的叠影底图，
    /// 不能跟转盘帧一样只有 1280。
    private static func coverImage(asset: AVURLAsset, at time: CMTime) async -> UIImage? {
        let generator = makeGenerator(asset: asset, maxDimension: 2048)
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
