import PhotosUI
import SwiftData
import SwiftUI

/// 一条养护记录的详情：照片（可选）、时间、可编辑的备注。
///
/// 记浇水时不强制写备注也不强制拍照，事后想补、想换、想删都从时间轴点进这里。
struct CareRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var record: CareRecord
    let plant: Plant

    @State private var viewedPhoto: ViewedPhoto?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingPhotoRemoval = false
    @State private var isChoosingPhotoSource = false
    @State private var isShowingCamera = false
    @State private var isPickingFromLibrary = false
    @State private var pickerItem: PhotosPickerItem?

    private var photoFilename: String? {
        guard let filename = record.photoFilename, !filename.isEmpty else { return nil }
        return filename
    }

    /// 有照片是「换一张」，没有是「加一张」，同一个入口。
    private var photoActionTitle: String {
        photoFilename == nil ? String(localized: "添加照片") : String(localized: "更换照片")
    }

    /// 记错日子事后能改。改完「x 天前浇水」得跟着动，所以顺手重算一遍。
    private var performedAt: Binding<Date> {
        Binding(
            get: { record.performedAt },
            set: { newValue in
                record.performedAt = newValue
                refreshLastWatered()
            }
        )
    }

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
                    if let photoFilename {
                        Button {
                            viewedPhoto = ViewedPhoto(filename: photoFilename)
                        } label: {
                            PhotoImageView(filename: photoFilename, contentMode: .fit)
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

                    photoButtons

                    dateRow

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
                ToolbarItem(placement: .primaryAction) {
                    Button("删除", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
            .fullScreenCover(item: $viewedPhoto) { photo in
                PhotoViewerView(filename: photo.filename)
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    isShowingCamera = false
                    if let image { replacePhoto(with: image) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPickingFromLibrary, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newValue in
                Task { await loadImage(from: newValue) }
            }
            .onDisappear {
                // 备注是边打边写进模型的，关掉时落一次盘。
                try? modelContext.save()
            }
            .confirmationDialog(
                photoActionTitle,
                isPresented: $isChoosingPhotoSource,
                titleVisibility: .visible
            ) {
                if CameraPicker.isAvailable {
                    Button("拍照") { isShowingCamera = true }
                }
                Button("从相册选择") { isPickingFromLibrary = true }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog(
                "删掉这张照片？",
                isPresented: $isConfirmingPhotoRemoval,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { removePhoto() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这条记录本身会留着，只是不再带照片。")
            }
            .confirmationDialog("删除这条记录？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("照片也会一并删除，无法恢复。")
            }
        }
    }

    private var photoButtons: some View {
        HStack(spacing: 10) {
            Button(photoActionTitle, systemImage: "photo.badge.plus") {
                isChoosingPhotoSource = true
            }
            if photoFilename != nil {
                Button("删除照片", systemImage: "trash", role: .destructive) {
                    isConfirmingPhotoRemoval = true
                }
            }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
    }

    /// 往前不设限 —— 补记前天忘了记的那次是常事；
    /// 往后卡在今天 —— 记一次还没发生的浇水没有意义。
    private var dateRow: some View {
        HStack {
            Text("记录时间")
                .font(.subheadline.weight(.medium))
            Spacer()
            DatePicker(
                "记录时间",
                selection: performedAt,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
        }
    }

    // MARK: - 操作

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        replacePhoto(with: image)
        // 同一张图再选一次也要能触发 onChange。
        pickerItem = nil
    }

    /// 新的存进去了才删旧的 —— 存失败时至少原来那张还在。
    private func replacePhoto(with image: UIImage) {
        guard let filename = PhotoStore.shared.save(image) else { return }
        let previous = record.photoFilename

        record.photoFilename = filename
        plant.touch()
        try? modelContext.save()

        PhotoStore.shared.delete(filename: previous)
    }

    private func removePhoto() {
        let filename = record.photoFilename

        record.photoFilename = nil
        plant.touch()
        try? modelContext.save()

        PhotoStore.shared.delete(filename: filename)
    }

    /// 最近一次浇水是哪次，重新从记录里取。excluding 给删除用 ——
    /// modelContext.delete 之后关系数组不会马上更新，得把自己滤掉。
    private func refreshLastWatered(excluding excludedID: UUID? = nil) {
        plant.lastWateredAt = plant.sortedCareRecords
            .first { $0.id != excludedID && $0.careType == .water }?
            .performedAt
        plant.touch()
    }

    private func delete() {
        let filename = record.photoFilename
        let deletedID = record.id

        // 删掉的正好是最近一次浇水的话，「x 天前浇水」得退回剩下最近的那次。
        // 关系数组这会儿还没更新，按 id 把自己滤掉。
        refreshLastWatered(excluding: deletedID)

        modelContext.delete(record)
        try? modelContext.save()
        PhotoStore.shared.delete(filename: filename)
        dismiss()
    }
}
