import SwiftData
import SwiftUI

/// 单张生长记录的大图 + 元数据。
struct GrowthEntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entry: GrowthEntry
    let plant: Plant

    /// 备注是可选的，空串存回 nil，免得库里留一堆空字符串。
    private var noteText: Binding<String> {
        Binding(
            get: { entry.note ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.note = trimmed.isEmpty ? nil : trimmed
                entry.touch()
            }
        )
    }

    @State private var isConfirmingDelete = false
    @State private var viewedPhoto: ViewedPhoto?
    @StateObject private var saver = PhotoSaver()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 点开进全屏，那里能双指缩放
                    Button {
                        viewedPhoto = ViewedPhoto(filename: entry.photoFilename)
                    } label: {
                        PhotoImageView(filename: entry.photoFilename, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    NoteEditor(text: noteText, placeholder: "这次有什么变化？（可选）")

                    metadata
                }
                .padding(16)
            }
            .navigationTitle(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        saver.save(filename: entry.photoFilename)
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }
                    .disabled(saver.isSaving)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("删除", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
            .overlay(alignment: .bottom) {
                PhotoSaveBadge(state: saver.state)
                    .padding(.bottom, 40)
            }
            .fullScreenCover(item: $viewedPhoto) { photo in
                PhotoViewerView(filename: photo.filename)
            }
            .onDisappear {
                // 备注是边打边写进模型的，关掉时落一次盘。
                try? modelContext.save()
            }
            .confirmationDialog("删除这条记录？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("照片也会一并删除，无法恢复。")
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pose = entry.pose {
                Label("拍摄角度", systemImage: "gyroscope")
                    .font(.subheadline.weight(.medium))
                Text(String(format: String(localized: "俯仰 %.1f° · 翻滚 %.1f° · 偏航 %.1f°"), pose.pitch, pose.roll, pose.yaw))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("这些数据会一直保留，将来做「自动对齐」时可以回溯使用。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Label("这张没有记录拍摄角度", systemImage: "gyroscope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func delete() {
        let filename = entry.photoFilename
        let spinFilenames = entry.spinFilenames
        // 封面正好用的是这张的话，回退到剩下最新的一张。
        if plant.coverPhotoFilename == filename {
            let remaining = plant.sortedGrowthEntries.first { $0.id != entry.id }
            plant.coverPhotoFilename = remaining?.photoFilename
            plant.touch()
        }

        modelContext.delete(entry)
        try? modelContext.save()
        PhotoStore.shared.delete(filename: filename)
        PhotoStore.shared.deleteSpinFrames(spinFilenames)
        dismiss()
    }
}
