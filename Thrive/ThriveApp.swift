import SwiftData
import SwiftUI

@main
struct ThriveApp: App {
    /// 整个 App 共用一个数据库容器。
    private let modelContainer = ModelContainerFactory.makeContainer()

    var body: some Scene {
        WindowGroup {
            PlantGridView()
        }
        .modelContainer(modelContainer)
    }
}
