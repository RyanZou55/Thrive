import Foundation
import OSLog
import UIKit

/// 照片的读写。数据库里只有文件名，真正的 JPEG 都归这里管。
final class PhotoStore {
    static let shared = PhotoStore()

    private let logger = Logger(subsystem: "com.ryanzou.thrive", category: "PhotoStore")
    /// 已解码的图片缓存，避免时间轴滚动时反复读盘。
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 80
    }

    // MARK: - 写

    /// 存一张图，返回文件名（存进数据库的就是这个）。
    /// 长边压到 2048px，JPEG 0.85 —— 对比生长足够清晰，又不会几年后撑爆手机。
    @discardableResult
    func save(_ image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.85) -> String? {
        let resized = image.resizedPreservingAspect(maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else {
            logger.error("JPEG 编码失败")
            return nil
        }

        let filename = "\(UUID().uuidString).jpg"
        let url = AppContainer.photosURL.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            cache.setObject(resized, forKey: filename as NSString)
            return filename
        } catch {
            logger.error("写入照片失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - 读

    func image(named filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        if let cached = cache.object(forKey: filename as NSString) { return cached }

        let url = AppContainer.photosURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    func url(for filename: String) -> URL {
        AppContainer.photosURL.appendingPathComponent(filename)
    }

    // MARK: - 删

    func delete(filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        cache.removeObject(forKey: filename as NSString)
        let url = AppContainer.photosURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

extension UIImage {
    /// 等比缩放，长边不超过 maxDimension。本来就小于就原样返回。
    func resizedPreservingAspect(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return self }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
