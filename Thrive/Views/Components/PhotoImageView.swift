import SwiftUI

/// 按文件名从共享容器里读图并显示。读盘放后台，避免滚动时卡顿。
struct PhotoImageView: View {
    let filename: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if !isLoading {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .task(id: filename) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        let name = filename
        let loaded = await Task.detached(priority: .userInitiated) {
            PhotoStore.shared.image(named: name)
        }.value
        image = loaded
        isLoading = false
    }
}
