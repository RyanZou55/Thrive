import SwiftUI

/// 时间轴上被点开的那张图。fullScreenCover(item:) 需要 Identifiable。
struct ViewedPhoto: Identifiable {
    let id = UUID()
    let filename: String
}

/// 全屏看图：双指缩放、双击放大、可存进系统相册。
struct PhotoViewerView: View {
    let filename: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var saver = PhotoSaver()
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    ZoomableImageView(image: image)
                } else {
                    ProgressView().tint(.white)
                }

                PhotoSaveBadge(state: saver.state)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        saver.save(filename: filename)
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }
                    .disabled(saver.isSaving)
                }
            }
        }
        .task(id: filename) {
            let name = filename
            image = await Task.detached(priority: .userInitiated) {
                PhotoStore.shared.image(named: name)
            }.value
        }
    }
}
