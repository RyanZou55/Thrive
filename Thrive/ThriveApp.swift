import SwiftData
import SwiftUI

@main
struct ThriveApp: App {
    /// 整个 App 共用一个数据库容器。
    private let modelContainer = ModelContainerFactory.makeContainer()

    var body: some Scene {
        WindowGroup {
            PlantGridView()
                .task {
                    await WateringScheduler.shared.requestAuthorizationIfNeeded()
                    await rescheduleAllReminders()
                }
        }
        .modelContainer(modelContainer)
    }

    /// 启动时按当前数据重排所有提醒 —— 提醒时间是算出来的，重排一次就永远准。
    @MainActor
    private func rescheduleAllReminders() async {
        let context = modelContainer.mainContext
        guard let plants = try? context.fetch(FetchDescriptor<Plant>()) else { return }
        await WateringScheduler.shared.rescheduleAll(plants: plants)
    }
}
