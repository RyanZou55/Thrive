import Foundation
import OSLog
import UserNotifications

/// 浇水提醒。提醒时间不入库 —— 每次都用「上次浇水 + 间隔」实时算，
/// 所以只要植物数据变了，重排一次通知就永远是对的。
@MainActor
final class WateringScheduler {
    static let shared = WateringScheduler()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.ryanzou.thrive", category: "Notifications")

    private init() {}

    /// 请通知权限。第一次进 App 时调一次。
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                logger.error("申请通知权限失败: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// 重排一株植物的提醒。先撤旧的，再按当前数据排新的。
    func reschedule(for plant: Plant) async {
        let identifier = Self.identifier(for: plant.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard let dueDate = plant.nextWateringDate else { return }

        // 提醒定在到期当天早上 9 点；已经过去的时间点不排。
        guard let fireDate = Self.reminderTime(on: dueDate), fireDate > Date() else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.second = 0

        let content = UNMutableNotificationContent()
        content.title = "该给「\(plant.name)」浇水了"
        content.body = "距上次浇水已经 \(plant.wateringIntervalDays) 天。"
        content.sound = .default
        content.userInfo = ["plantID": plant.id.uuidString]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await center.add(request)
        } catch {
            logger.error("排通知失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancel(for plantID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: plantID)])
    }

    /// 全量重排。App 启动时跑一次，保证提醒和数据一致。
    func rescheduleAll(plants: [Plant]) async {
        for plant in plants {
            await reschedule(for: plant)
        }
    }

    // MARK: - 辅助

    private static func identifier(for plantID: UUID) -> String {
        "watering-\(plantID.uuidString)"
    }

    private static func reminderTime(on date: Date) -> Date? {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }
}
