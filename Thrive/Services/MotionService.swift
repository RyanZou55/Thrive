import Combine
import CoreMotion
import Foundation
import OSLog

/// 拍照瞬间手机的姿态，单位：度。
struct DevicePose: Equatable {
    var pitch: Double  // 俯仰：手机前后倾
    var roll: Double   // 翻滚：手机左右歪
    var yaw: Double    // 偏航：水平朝向

    /// 与参考姿态的差值。yaw 的零点是每次启动时的朝向，两次拍摄之间没有可比性，
    /// 所以跨天的对齐判断只看 pitch 和 roll —— 这两个是重力参考的，稳。
    /// （单次拍摄会话内 yaw 是可靠的，转盘就靠它定位每一帧。）
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
            return String(localized: "第一张照片，随意构图 —— 之后都会以它为准")
        case .aligned:
            return String(localized: "角度对上了，按快门")
        case let .off(pitchDelta, rollDelta):
            var parts: [String] = []
            if abs(pitchDelta) > PoseAlignment.tolerance {
                parts.append(pitchDelta > 0 ? String(localized: "手机前倾一点") : String(localized: "手机后仰一点"))
            }
            if abs(rollDelta) > PoseAlignment.tolerance {
                parts.append(rollDelta > 0 ? String(localized: "向左转正") : String(localized: "向右转正"))
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

    /// 录转盘时的 yaw 轨迹。非 nil 就表示正在录。
    ///
    /// 时刻用 CMDeviceMotion.timestamp（开机以来的秒数），和录制起点记的
    /// systemUptime 同源，两条时间线才对得上。
    private var yawTrack: [SpinFrameSelector.Sample]?

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func start() {
        #if targetEnvironment(simulator)
        // 模拟器没有陀螺仪，姿态条永远不会出现，也就无从验证。
        // 这里造一个来回摆动的假姿态，让它扫过「偏了 → 对齐 → 偏了」，
        // 好把姿态条的渲染和状态切换验证掉。只在模拟器编译，真机没有这段。
        startSimulatedMotion()
        return
        #else
        guard manager.isDeviceMotionAvailable else {
            isAvailable = false
            logger.info("设备不支持 DeviceMotion")
            return
        }
        guard !manager.isDeviceMotionActive else { return }

        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let attitude = motion.attitude
            let yaw = attitude.yaw * 180 / .pi
            self.currentPose = DevicePose(
                pitch: attitude.pitch * 180 / .pi,
                roll: attitude.roll * 180 / .pi,
                yaw: yaw
            )
            self.appendToYawTrack(time: motion.timestamp, yaw: yaw)
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private var simulatedTimer: Timer?

    /// 两个轴同相摆动，振幅比容差大，所以会周期性地穿过基准角度 ——
    /// 能扫出「偏了 → 对齐 → 偏了」的完整来回。
    private func startSimulatedMotion() {
        isAvailable = true
        let start = Date()
        simulatedTimer?.invalidate()
        simulatedTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            let swing = 6 * sin(Date().timeIntervalSince(start) * 0.8)
            Task { @MainActor in
                self?.currentPose = DevicePose(pitch: -2.4 + swing, roll: 1.6 + swing, yaw: 133.3)
            }
        }
    }
    #endif

    // MARK: - 转盘 yaw 轨迹

    func beginYawTrack() {
        yawTrack = []
    }

    /// 取走轨迹并停止记录。
    func endYawTrack() -> [SpinFrameSelector.Sample] {
        defer { yawTrack = nil }
        return yawTrack ?? []
    }

    private func appendToYawTrack(time: TimeInterval, yaw: Double) {
        yawTrack?.append(SpinFrameSelector.Sample(time: time, yaw: yaw))
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
