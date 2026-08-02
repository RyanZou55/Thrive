import Foundation
import SwiftData

/// 植物类型。按文档要求，枚举一律以字符串存库，将来加新类型不会破坏旧数据。
enum PlantKind: String, CaseIterable, Identifiable {
    case cactus
    case caudex
    case succulent
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cactus: return "仙人掌"
        case .caudex: return "块根"
        case .succulent: return "多肉"
        case .other: return "其他"
        }
    }
}

@Model
final class Plant {
    /// 主键。永不复用、永不修改。
    var id: UUID = UUID()
    var name: String = ""
    /// 只存文件名，图片本体在共享容器的文件系统里。
    var coverPhotoFilename: String?
    var species: String?
    /// 对应 PlantKind.rawValue，直接存字符串。
    var caudexType: String?
    var acquiredDate: Date?
    var wateringIntervalDays: Int = 7
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
        species: String? = nil,
        kind: PlantKind? = nil,
        acquiredDate: Date? = nil,
        wateringIntervalDays: Int = 7,
        sortOrder: Int = 0,
        notes: String? = nil
    ) {
        let now = Date()
        self.id = UUID()
        self.name = name
        self.coverPhotoFilename = coverPhotoFilename
        self.species = species
        self.caudexType = kind?.rawValue
        self.acquiredDate = acquiredDate
        self.wateringIntervalDays = wateringIntervalDays
        self.sortOrder = sortOrder
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
        self.schemaVersion = 1
    }
}

// MARK: - 计算属性（不入库）

extension Plant {
    var kind: PlantKind? {
        get { caudexType.flatMap(PlantKind.init(rawValue:)) }
        set {
            caudexType = newValue?.rawValue
            touch()
        }
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

    /// 下次浇水时间 = 上次浇水 + 间隔天数。文档要求实时算出，不入库。
    var nextWateringDate: Date? {
        guard let lastWateredAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: wateringIntervalDays, to: lastWateredAt)
    }

    /// 距下次浇水还剩几天。负数表示已经逾期。从未浇过水返回 nil。
    var daysUntilWatering: Int? {
        guard let nextWateringDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let due = calendar.startOfDay(for: nextWateringDate)
        return calendar.dateComponents([.day], from: today, to: due).day
    }

    /// 首页卡片上那行字。
    var wateringStatusText: String {
        guard let days = daysUntilWatering else { return "还没浇过水" }
        if days > 0 { return "还剩 \(days) 天浇水" }
        if days == 0 { return "今天该浇水" }
        return "逾期 \(-days) 天"
    }

    var isWateringDue: Bool {
        guard let days = daysUntilWatering else { return true }
        return days <= 0
    }

    /// 任何修改后调用，维护 updatedAt。
    func touch() {
        updatedAt = Date()
    }
}
