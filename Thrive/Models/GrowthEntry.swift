import Foundation
import SwiftData

/// 一条生长记录 = 一张照片 + 一句备注 + 拍摄时的姿态数据。
///
/// 姿态（pitch/roll/yaw）在 v1.0 只用来做「对齐 / 偏了」的实时提示，
/// 但每次都静默存下来，v1.2 的自动对齐可以回溯使用。
@Model
final class GrowthEntry {
    var id: UUID = UUID()
    var capturedAt: Date = Date()
    /// 只存文件名，图片本体在共享容器里。
    var photoFilename: String = ""
    var note: String?
    /// 本次对齐参考的上一张记录（幽灵叠影用的那张）。
    var refEntryID: UUID?

    // 拍摄姿态，单位：度
    var posePitch: Double?
    var poseRoll: Double?
    var poseYaw: Double?

    /// 转盘帧的文件名，按角度顺序排（第 0 帧和 photoFilename 是同一个角度）。
    /// 没拍转盘就是 nil —— 一条记录仍然可以只有一张照片。
    var spinFilenames: [String]? = nil
    /// 第 0 帧拍摄时的 yaw，单位：度。帧间隔固定 15°，据此能还原出每帧的角度。
    var spinStartYaw: Double? = nil

    // 可选测量值，v1.0 不做输入 UI，先把字段留好
    var heightCm: Double?
    var caudexWidthMm: Double?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var schemaVersion: Int = 1

    var plant: Plant?

    init(
        capturedAt: Date = Date(),
        photoFilename: String,
        note: String? = nil,
        refEntryID: UUID? = nil,
        pose: DevicePose? = nil,
        heightCm: Double? = nil,
        caudexWidthMm: Double? = nil
    ) {
        let now = Date()
        self.id = UUID()
        self.capturedAt = capturedAt
        self.photoFilename = photoFilename
        self.note = note
        self.refEntryID = refEntryID
        self.posePitch = pose?.pitch
        self.poseRoll = pose?.roll
        self.poseYaw = pose?.yaw
        self.heightCm = heightCm
        self.caudexWidthMm = caudexWidthMm
        self.createdAt = now
        self.updatedAt = now
        self.schemaVersion = 1
    }
}

extension GrowthEntry {
    /// 三个角度都存在时，还原成一个 DevicePose，供下次拍照做对比。
    var pose: DevicePose? {
        guard let posePitch, let poseRoll, let poseYaw else { return nil }
        return DevicePose(pitch: posePitch, roll: poseRoll, yaw: poseYaw)
    }

    func touch() {
        updatedAt = Date()
    }
}
