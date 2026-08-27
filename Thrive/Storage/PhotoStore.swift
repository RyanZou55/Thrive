import Foundation
import ImageIO
import OSLog
import UIKit
import UniformTypeIdentifiers

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

    // MARK: - 转盘帧

    /// 转盘帧比主图小一档：长边 1280、HEIC 0.7。
    ///
    /// 1280 是按 390pt 宽 @3x 屏算的（1170px），刚好够；再降在详情页看得出糊。
    /// HEIC 同画质比 JPEG 小四到五成，而且抠图之后背景是纯色 ——
    /// 大片纯色在 HEIC 里几乎不占字节，单帧能压到 130KB 上下。
    ///
    /// 转盘帧不进 cache：一组 24 帧会把时间轴的缓存整个挤掉（countLimit 只有 80）。
    private static let spinMaxDimension: CGFloat = 1280
    private static let spinQuality: CGFloat = 0.7

    /// 存一组转盘帧，返回的文件名顺序就是角度顺序。
    /// 中途失败就把已经写下去的删掉再返回 nil —— 半组转盘播不了，不如不留。
    func saveSpinFrames(_ images: [UIImage]) -> [String]? {
        var filenames: [String] = []
        for image in images {
            guard let filename = saveHEIC(image) else {
                logger.error("转盘帧写入中断，回滚已写入的 \(filenames.count) 帧")
                deleteSpinFrames(filenames)
                return nil
            }
            filenames.append(filename)
        }
        return filenames
    }

    func deleteSpinFrames(_ filenames: [String]?) {
        guard let filenames else { return }
        for filename in filenames {
            delete(filename: filename)
        }
    }

    /// 帧的来源是 4K 视频抽帧，一定会走到缩放那一步，
    /// 而缩放是重绘出来的，方向已经正过了 —— 所以这里直接用 cgImage。
    private func saveHEIC(_ image: UIImage) -> String? {
        let resized = image.resizedPreservingAspect(maxDimension: Self.spinMaxDimension)
        guard let cgImage = resized.cgImage else {
            logger.error("拿不到 CGImage，转盘帧没法编码")
            return nil
        }

        let filename = "\(UUID().uuidString).heic"
        let url = AppContainer.photosURL.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            logger.error("创建 HEIC 编码器失败")
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: Self.spinQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            logger.error("HEIC 编码失败")
            return nil
        }
        return filename
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
