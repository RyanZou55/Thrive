import Foundation
import SwiftData

/// 养护类型。v1.0 只用 water，将来施肥、换盆只是多一个 rawValue，
/// 不新建表、不改结构 —— 这是 schema 稳定的关键。
enum CareType: String, CaseIterable, Identifiable {
    case water
    case fertilize
    case repot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .water: return "浇水"
        case .fertilize: return "施肥"
        case .repot: return "换盆"
        }
    }

    var symbolName: String {
        switch self {
        case .water: return "drop.fill"
        case .fertilize: return "leaf.fill"
        case .repot: return "shippingbox.fill"
        }
    }
}

@Model
final class CareRecord {
    var id: UUID = UUID()
    var performedAt: Date = Date()
    /// 对应 CareType.rawValue。
    var type: String = CareType.water.rawValue
    var amountMl: Double?
    var note: String?
    /// 这次浇水随手拍的照片文件名。可选 —— 不拍照也能记一笔。
    var photoFilename: String?
    var createdAt: Date = Date()
    var schemaVersion: Int = 1

    var plant: Plant?

    init(
        performedAt: Date = Date(),
        type: CareType = .water,
        amountMl: Double? = nil,
        note: String? = nil,
        photoFilename: String? = nil
    ) {
        self.id = UUID()
        self.performedAt = performedAt
        self.type = type.rawValue
        self.amountMl = amountMl
        self.note = note
        self.photoFilename = photoFilename
        self.createdAt = Date()
        self.schemaVersion = 1
    }
}

extension CareRecord {
    /// 未知类型（比如未来版本写入的新枚举）不会崩，只是显示成「其他」。
    var careType: CareType? {
        CareType(rawValue: type)
    }

    var displayName: String {
        careType?.displayName ?? "其他养护"
    }

    var symbolName: String {
        careType?.symbolName ?? "sparkles"
    }
}
