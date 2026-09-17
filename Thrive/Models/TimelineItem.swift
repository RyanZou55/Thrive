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

/// 拍照时拿来做叠影的那张照片。
///
/// 只管叠影，不管姿态 —— 姿态只有生长照存了，那条参考在 CaptureView 里单独取。
struct PhotoReference {
    var filename: String
    /// 来自生长记录时记下它的 id，存新记录时写进 refEntryID。
    var growthEntryID: UUID?
}

extension Plant {
    /// 最近拍的一张照片，浇水时随手拍的也算 —— 对齐看的是上一张长什么样，
    /// 跟它记在哪张表里没关系。
    var latestPhotoReference: PhotoReference? {
        for item in timelineItems {
            switch item {
            case let .growth(entry):
                return PhotoReference(filename: entry.photoFilename, growthEntryID: entry.id)
            case let .care(record):
                // 浇水不一定拍照，没拍就继续往前找。
                if let filename = record.photoFilename, !filename.isEmpty {
                    return PhotoReference(filename: filename)
                }
            }
        }
        return nil
    }
}
