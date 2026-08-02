import Combine
import CoreMotion
import Foundation
import OSLog

/// 拍照瞬间手机的姿态，单位：度。
struct DevicePose: Equatable {
    var pitch: Double  // 俯仰：手机前后倾
    var roll: Double   // 翻滚：手机左右歪
    var yaw: Double    // 偏航：水平朝向

    /// 与参考姿态的差值。yaw 用的是磁北参考，室内会漂，
    /// 所以对齐判断只看 pitch 和 roll —— 这两个是重力参考的，稳。
    func difference(from reference: DevicePose) -> (pitch: Double, roll: Double) {
        (
            pitch: DevicePose.normalizedAngle(pitch - reference.pitch),
            roll: DevicePose.normalizedAngle(roll - reference.roll)
        )
    }

    /// 把角度收进 -180…180，免得 179° 和 -179° 被当成差了 358°。
    static func normalizedAngle(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}

/// 对齐状态：绿灯 / 黄灯 / 没有参考。
enum PoseAlignment: Equatable {
    case noReference
    case aligned
    case off(pitchDelta: Double, rollDelta: Double)

    /// 差多少度算「对齐」。3° 是试出来的：再严会一直闪红，再松肉眼就看得出偏了。
    static let tolerance: Double = 3.0

    static func evaluate(current: DevicePose?, reference: DevicePose?) -> PoseAlignment {
        guard let current, let reference else { return .noReference }
        let delta = current.difference(from: reference)
        if abs(delta.pitch) <= tolerance && abs(delta.roll) <= tolerance {
            return .aligned
        }
        return .off(pitchDelta: delta.pitch, rollDelta: delta.roll)
    }

    var isAligned: Bool {
        if case .aligned = self { return true }
        return false
    }

    /// 给用户看的提示文案。
    var hint: String {
        switch self {
        case .noReference:
            return "第一张照片，随意构图 —— 之后都会以它为准"
        case .aligned:
            return "角度对上了，按快门"
        case let .off(pitchDelta, rollDelta):
            var parts: [String] = []
            if abs(pitchDelta) > PoseAlignment.tolerance {
                parts.append(pitchDelta > 0 ? "手机前倾一点" : "手机后仰一点")
            }
            if abs(rollDelta) > PoseAlignment.tolerance {
                parts.append(rollDelta > 0 ? "向左转正" : "向右转正")
            }
            return parts.joined(separator: " · ")
        }
    }
}

/// 读陀螺仪，实时吐出当前姿态。
@MainActor
final class MotionService: ObservableObject {
    @Published private(set) var currentPose: DevicePose?
    @Published private(set) var isAvailable: Bool = false

    private let manager = CMMotionManager()
    private let logger = Logger(subsystem: "com.ryanzou.thrive", category: "Motion")

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            // 模拟器没有陀螺仪，这里会走到。相机页面会隐藏姿态条。
            isAvailable = false
            logger.info("设备不支持 DeviceMotion（模拟器通常如此）")
            return
        }
        guard !manager.isDeviceMotionActive else { return }

        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let attitude = motion.attitude
            self.currentPose = DevicePose(
                pitch: attitude.pitch * 180 / .pi,
                roll: attitude.roll * 180 / .pi,
                yaw: attitude.yaw * 180 / .pi
            )
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
