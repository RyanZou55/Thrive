import Foundation
import SwiftData

/// 封面照片在详情页那块区域里怎么显示。展示相关的几个属性在 PlantDetailView 里。
enum CoverDisplayMode: String, Codable, CaseIterable, Identifiable {
    /// 裁掉多余部分，铺满整块区域。
    case fill
    /// 完整显示整张照片，居中，两边留白。
    case fit

    var id: String { rawValue }
}

@Model
final class Plant {
    /// 主键。永不复用、永不修改。
    var id: UUID = UUID()
    var name: String = ""
    /// 只存文件名，图片本体在共享容器的文件系统里。
    var coverPhotoFilename: String?
    /// 品种和类型：v1.0 界面上没有入口，按文档「只做加法」的原则保留字段，
    /// 将来想加分类不用改表。
    var species: String?
    var caudexType: String?
    var acquiredDate: Date?
    /// 封面在详情页里怎么摆，见 CoverDisplayMode。
    /// 存成可选的：轻量迁移不会给已有的行补默认值，读出来就是 nil。
    var storedCoverDisplayMode: CoverDisplayMode?
    var lastWateredAt: Date?
    var sortOrder: Int = 0
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// 预留给 SwiftData 轻量迁移。
    var schemaVersion: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \GrowthEntry.plant)
    var growthEntries: [GrowthEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \CareRecord.plant)
    var careRecords: [CareRecord]? = []

    init(
        name: String,
        coverPhotoFilename: String? = nil,
        acquiredDate: Date? = nil,
        sortOrder: Int = 0,
        notes: String? = nil
    ) {
        let now = Date()
        self.id = UUID()
        self.name = name
        self.coverPhotoFilename = coverPhotoFilename
        self.acquiredDate = acquiredDate
        self.sortOrder = sortOrder
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
        self.schemaVersion = 1
    }
}

// MARK: - 计算属性（不入库）

extension Plant {
    /// 没设置过就按填满裁剪来。
    var coverDisplayMode: CoverDisplayMode {
        get { storedCoverDisplayMode ?? .fill }
        set { storedCoverDisplayMode = newValue }
    }

    /// 时间轴，按拍摄时间倒序（最新在前）。
    var sortedGrowthEntries: [GrowthEntry] {
        (growthEntries ?? []).sorted { $0.capturedAt > $1.capturedAt }
    }

    /// 上一张照片 —— 拍照时拿它做幽灵叠影的参考。
    var latestGrowthEntry: GrowthEntry? {
        sortedGrowthEntries.first
    }

    var sortedCareRecords: [CareRecord] {
        (careRecords ?? []).sorted { $0.performedAt > $1.performedAt }
    }

    /// 距上次浇水过了几天。从没浇过返回 nil。
    var daysSinceWatering: Int? {
        guard let lastWateredAt else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastWateredAt),
            to: calendar.startOfDay(for: Date())
        ).day
    }

    /// 首页卡片和详情页顶部那行字。
    var lastWateredText: String {
        guard let days = daysSinceWatering else { return String(localized: "还没浇过水") }
        if days <= 0 { return String(localized: "今天浇过水") }
        if days == 1 { return String(localized: "昨天浇过水") }
        return String(localized: "\(days) 天前浇水")
    }

    /// 任何修改后调用，维护 updatedAt。
    func touch() {
        updatedAt = Date()
    }
}
