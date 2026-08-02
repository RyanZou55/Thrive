import Foundation
import OSLog

/// 数据与照片的落盘位置。
///
/// 文档要求「从第一天就放 App Group 共享容器」，为将来的 Widget 预留。
/// 但 App Group 需要付费开发者账号才能签名，免费账号打开工程会直接编译失败。
/// 所以这里做了一层抽象：
///
/// - 能拿到共享容器 → 用共享容器（Widget 可读）
/// - 拿不到 → 退回 App 自己的 Application Support 目录，功能完全不受影响
///
/// 将来你开通了 App Group，第一次启动会自动把本地数据搬进共享容器，
/// 上层代码一行都不用动。
enum AppContainer {
    /// 开启 App Group 时在 Xcode → Signing & Capabilities 里填的就是这个字符串。
    static let appGroupIdentifier = "group.com.ryanzou.thrive"

    private static let logger = Logger(subsystem: "com.ryanzou.thrive", category: "AppContainer")

    /// 共享容器是否可用（即 App Group 是否已配置好）。
    static var isUsingSharedContainer: Bool {
        sharedContainerURL != nil
    }

    private static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static var localContainerURL: URL {
        // Application Support 不一定存在，用到时再建。
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
    }

    /// 所有 Thrive 数据的根目录。
    static var rootURL: URL {
        let base = sharedContainerURL ?? localContainerURL
        let url = base.appendingPathComponent("Thrive", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    /// SwiftData 数据库文件。
    static var storeURL: URL {
        rootURL.appendingPathComponent("Thrive.store")
    }

    /// 照片目录。数据库里只存文件名，图片本体都在这。
    static var photosURL: URL {
        let url = rootURL.appendingPathComponent("Photos", isDirectory: true)
        ensureDirectoryExists(url)
        return url
    }

    static func ensureDirectoryExists(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            logger.error("创建目录失败 \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 一次性迁移：App Group 刚变得可用，而旧数据还留在本地目录时，整体搬过去。
    /// 幂等 —— 目标已有数据就什么都不做。
    static func migrateLocalDataToSharedContainerIfNeeded() {
        guard let sharedContainerURL else { return }

        let fileManager = FileManager.default
        let localRoot = localContainerURL.appendingPathComponent("Thrive", isDirectory: true)
        let sharedRoot = sharedContainerURL.appendingPathComponent("Thrive", isDirectory: true)

        // 本地没有旧数据，或共享容器已经有数据了，都不迁移。
        guard fileManager.fileExists(atPath: localRoot.path) else { return }
        guard !fileManager.fileExists(atPath: sharedRoot.appendingPathComponent("Thrive.store").path) else { return }

        do {
            ensureDirectoryExists(sharedRoot)
            for item in try fileManager.contentsOfDirectory(at: localRoot, includingPropertiesForKeys: nil) {
                let destination = sharedRoot.appendingPathComponent(item.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                try fileManager.moveItem(at: item, to: destination)
            }
            logger.info("已把本地数据迁移到 App Group 共享容器")
        } catch {
            logger.error("迁移到共享容器失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
