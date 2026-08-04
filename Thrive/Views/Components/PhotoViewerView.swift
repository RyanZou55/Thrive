import Photos
import SwiftUI

/// 时间轴上被点开的那张图。fullScreenCover(item:) 需要 Identifiable。
struct ViewedPhoto: Identifiable {
    let id = UUID()
    let filename: String
}

/// 全屏看图，可以存进系统相册。
struct PhotoViewerView: View {
    let filename: String

    @Environment(\.dismiss) private var dismiss
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                PhotoImageView(filename: filename, contentMode: .fit)

                if saveState != .idle {
                    statusBadge
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 40)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        save()
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }
                    .disabled(saveState == .saving)
                }
            }
        }
    }

    private var statusBadge: some View {
        Group {
            switch saveState {
            case .saving:
                Label("正在保存…", systemImage: "arrow.down.circle")
            case .saved:
                Label("已存进相册", systemImage: "checkmark.circle.fill")
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
            case .idle:
                EmptyView()
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func save() {
        guard let image = PhotoStore.shared.image(named: filename) else {
            saveState = .failed("找不到这张照片")
            return
        }

        saveState = .saving
        Task {
            // 只申请「添加」权限，不需要读用户整个相册。
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveState = .failed("没有相册写入权限")
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                saveState = .saved
            } catch {
                saveState = .failed("保存失败")
            }

            // 提示两秒后自行消失。
            try? await Task.sleep(for: .seconds(2))
            if saveState != .saving { saveState = .idle }
        }
    }
}
