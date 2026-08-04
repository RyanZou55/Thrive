import Foundation

/// 时间轴上的一条 —— 可能是生长记录，也可能是养护记录（浇水）。
///
/// 两者存在不同的表里，但在详情页汇成一条按时间排的流。
enum TimelineItem: Identifiable {
    case growth(GrowthEntry)
    case care(CareRecord)

    var id: UUID {
        switch self {
        case let .growth(entry): return entry.id
        case let .care(record): return record.id
        }
    }

    var date: Date {
        switch self {
        case let .growth(entry): return entry.capturedAt
        case let .care(record): return record.performedAt
        }
    }
}

extension Plant {
    /// 生长记录 + 养护记录合成的时间轴，最新在前。
    var timelineItems: [TimelineItem] {
        let growth = (growthEntries ?? []).map(TimelineItem.growth)
        let care = (careRecords ?? []).map(TimelineItem.care)
        return (growth + care).sorted { $0.date > $1.date }
    }
}
