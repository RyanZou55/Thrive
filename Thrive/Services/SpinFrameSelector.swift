import Foundation

/// 从一段 yaw 轨迹里挑出转盘该用的那几帧。
///
/// 录制时 CoreMotion 的采样和视频帧是两条独立的时间线。这里只做一件事：
/// 算出「转过 15° / 30° / 45°… 分别是在第几秒」，剩下的交给抽帧器去那些时刻取画面。
///
/// 整个文件不碰 AVFoundation 也不碰 UIKit —— 这是第 2 步唯一容易算错的地方，
/// 得能脱离相机单独验。
enum SpinFrameSelector {
    /// 24 帧 / 15°。12 帧转起来能看出跳格，24 往上提升几乎感觉不到。
    static let frameCount = 24
    static let stepDegrees = 360.0 / Double(frameCount)
    /// 少于这个数说明用户没转够，当普通单张记录处理。
    static let minimumFrames = 8

    /// 一次 yaw 采样。time 用 CMDeviceMotion.timestamp（开机以来的秒数）。
    struct Sample: Equatable {
        var time: TimeInterval
        var yaw: Double
    }

    /// 选中的一帧：去视频的第几秒取，以及它相对第 0 帧转过了多少度。
    struct Frame: Equatable {
        var time: TimeInterval
        var angle: Double
    }

    /// 挑帧。返回的第一帧永远是轨迹起点（0°），后面每 15° 一帧。
    /// 覆盖角度不足 8 帧时返回空 —— 半组转盘播不了。
    static func select(from samples: [Sample]) -> [Frame] {
        guard samples.count >= 2 else { return [] }

        // 1. 把 yaw 展开成累计角度，跨 ±180 时不会突然跳 360。
        var cumulative = [0.0]
        for index in 1..<samples.count {
            let delta = normalizedAngle(samples[index].yaw - samples[index - 1].yaw)
            cumulative.append(cumulative[index - 1] + delta)
        }

        // 2. 定方向：绕着走可能顺时针也可能逆时针，取走得最远的那一侧。
        let forwardPeak = cumulative.max() ?? 0
        let backwardPeak = -(cumulative.min() ?? 0)
        let direction: Double = forwardPeak >= backwardPeak ? 1 : -1

        // 3. 沿轨迹走，每次跨过一个 15° 的坎就记下时刻。
        //    用「走到过的最远处」当基准，手抖回退一点不会重复出帧。
        var frames = [Frame(time: samples[0].time, angle: 0)]
        var peak = 0.0
        var nextTarget = stepDegrees

        for index in 1..<samples.count where frames.count < frameCount {
            let progress = direction * cumulative[index]
            guard progress > peak else { continue }

            let previous = direction * cumulative[index - 1]
            // 一次采样跨过好几个坎也照样都取到（走得快时会发生）。
            while nextTarget <= progress && frames.count < frameCount {
                let time = interpolatedTime(
                    target: nextTarget,
                    from: (previous, samples[index - 1].time),
                    to: (progress, samples[index].time)
                )
                frames.append(Frame(time: time, angle: nextTarget))
                nextTarget += stepDegrees
            }
            peak = progress
        }

        return frames.count >= minimumFrames ? frames : []
    }

    /// 目标角度落在两次采样之间，按比例插出时刻。
    private static func interpolatedTime(
        target: Double,
        from start: (progress: Double, time: TimeInterval),
        to end: (progress: Double, time: TimeInterval)
    ) -> TimeInterval {
        let span = end.progress - start.progress
        guard span > 0 else { return end.time }
        let ratio = (target - start.progress) / span
        return start.time + (end.time - start.time) * ratio
    }

    /// 收进 -180…180，免得 179° 和 -179° 被当成差了 358°。
    private static func normalizedAngle(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
