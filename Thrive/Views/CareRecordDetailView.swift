import SwiftData
import SwiftUI

/// 一条养护记录的详情：照片（可选）、时间、可编辑的备注。
///
/// 记浇水时不强制写备注，事后想补一句就从时间轴点进这里。
struct CareRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var record: CareRecord

    @State private var viewedPhoto: ViewedPhoto?

    /// 空串存回 nil，免得库里留一堆空字符串。
    private var noteText: Binding<String> {
        Binding(
            get: { record.note ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                record.note = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let filename = record.photoFilename, !filename.isEmpty {
                        Button {
                            viewedPhoto = ViewedPhoto(filename: filename)
                        } label: {
                            PhotoImageView(filename: filename, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Label("这次没有拍照", systemImage: "photo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .background(.background.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    NoteEditor(text: noteText, placeholder: "比如换了新土、浇透了（可选）")
                }
                .padding(16)
            }
            .navigationTitle(record.performedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fullScreenCover(item: $viewedPhoto) { photo in
                PhotoViewerView(filename: photo.filename)
            }
            .onDisappear {
                // 备注是边打边写进模型的，关掉时落一次盘。
                try? modelContext.save()
            }
        }
    }
}
