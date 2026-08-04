import Photos
import SwiftUI

/// 把 App 里的照片存进系统相册，并暴露保存状态供界面提示。
///
/// 全屏看图和生长记录详情都要存图，逻辑放这里共用。
@MainActor
final class PhotoSaver: ObservableObject {
    enum State: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var isSaving: Bool { state == .saving }

    func save(filename: String) {
        guard state != .saving else { return }
        guard let image = PhotoStore.shared.image(named: filename) else {
            finish(with: .failed("找不到这张照片"))
            return
        }

        state = .saving
        Task {
            // 只申请「添加」权限，不需要读用户整个相册。
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                finish(with: .failed("没有相册写入权限"))
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                finish(with: .saved)
            } catch {
                finish(with: .failed("保存失败"))
            }
        }
    }

    /// 结果提示两秒后自行消失。
    private func finish(with newState: State) {
        state = newState
        Task {
            try? await Task.sleep(for: .seconds(2))
            if state == newState { state = .idle }
        }
    }
}

/// 保存状态的浮层提示。idle 时什么都不显示。
struct PhotoSaveBadge: View {
    let state: PhotoSaver.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            badge("正在保存…", symbol: "arrow.down.circle")
        case .saved:
            badge("已存进相册", symbol: "checkmark.circle.fill")
        case let .failed(reason):
            badge(reason, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func badge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
