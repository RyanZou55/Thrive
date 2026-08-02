import Foundation
import OSLog
import SwiftData

/// 建 SwiftData 容器。数据库文件放在共享容器里（见 AppContainer）。
enum ModelContainerFactory {
    private static let logger = Logger(subsystem: "com.ryanzou.thrive", category: "ModelContainer")

    /// 三张核心表。将来加表在这里追加即可。
    static let schema = Schema([
        Plant.self,
        GrowthEntry.self,
        CareRecord.self,
    ])

    static func makeContainer() -> ModelContainer {
        AppContainer.migrateLocalDataToSharedContainerIfNeeded()

        let configuration = ModelConfiguration(schema: schema, url: AppContainer.storeURL)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // 走到这里通常是模型改了但没写迁移。开发期让它响亮地失败，
            // 比默默丢数据好。
            logger.fault("创建 ModelContainer 失败: \(error.localizedDescription, privacy: .public)")
            fatalError("无法创建数据库：\(error)")
        }
    }

    /// SwiftUI 预览用的内存容器，不落盘。
    static func makePreviewContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // 预览容器建不出来说明模型本身有问题，直接崩掉即可。
        return try! ModelContainer(for: schema, configurations: configuration)
    }
}
