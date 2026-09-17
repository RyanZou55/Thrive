import PhotosUI
import SwiftData
import SwiftUI

/// 编辑植物信息：封面、名字、简介、入手日期。
///
/// 详情页只做展示，要改什么都从那儿的「编辑」进来。
/// 改动都先存在本地 state 里，点保存才写回模型 —— 取消就当没发生过。
struct EditPlantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plant: Plant

    @State private var name: String
    @State private var about: String
    @State private var acquiredDate: Date
    @State private var hasAcquiredDate: Bool
    @State private var displayMode: CoverDisplayMode
    /// 选了新封面先放这儿，点保存才落盘 —— 取消掉不该在磁盘上留一张没人认领的图。
    @State private var newCoverImage: UIImage?

    @State private var isChoosingCoverSource = false
    @State private var isShowingCamera = false
    @State private var isPickingFromLibrary = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isConfirmingCoverReplacement = false
    @State private var isConfirmingCancel = false

    init(plant: Plant) {
        self.plant = plant
        _name = State(initialValue: plant.name)
        _about = State(initialValue: plant.notes ?? "")
        // 补记时别默认今天 —— 已经养了半年的植株填今天，时间轴上的「第 N 天」
        // 会全部消失。用最早那张生长照当起点，和 dayLabel 算天数时的回退链保持一致。
        _acquiredDate = State(
            initialValue: plant.acquiredDate
                ?? plant.sortedGrowthEntries.last?.capturedAt
                ?? plant.createdAt
        )
        _hasAcquiredDate = State(initialValue: plant.acquiredDate != nil)
        _displayMode = State(initialValue: plant.coverDisplayMode)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 保存会不会顺手删掉旧封面 —— 换了新的、而旧那张又不属于任何一条生长记录时才会。
    /// 属于某条记录的话 save() 本来就不会删它，那就没什么可确认的。
    private var savingDeletesOldCover: Bool {
        guard newCoverImage != nil, let previous = plant.coverPhotoFilename else { return false }
        return !plant.sortedGrowthEntries.contains { $0.photoFilename == previous }
    }

    /// 有没有改动没存。取消掉的是这些东西，得先问一句。
    private var hasUnsavedChanges: Bool {
        newCoverImage != nil
            || name != plant.name
            || about != (plant.notes ?? "")
            || displayMode != plant.coverDisplayMode
            || hasAcquiredDate != (plant.acquiredDate != nil)
            || (hasAcquiredDate && acquiredDate != plant.acquiredDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("封面照片") {
                    Button {
                        isChoosingCoverSource = true
                    } label: {
                        coverPreview
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())

                    Picker("显示方式", selection: $displayMode) {
                        ForEach(CoverDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("基本信息") {
                    TextField("名字", text: $name)
                    TextField("简介（可选）", text: $about, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    DatePicker("入手于", selection: $acquiredDate, in: ...Date(), displayedComponents: .date)
                    if hasAcquiredDate {
                        Button("不记录入手日期") { hasAcquiredDate = false }
                    }
                } header: {
                    Text("入手日期（可选）")
                } footer: {
                    if hasAcquiredDate {
                        Text("时间轴上的「第 N 天」从这天算起。")
                    } else {
                        Text("还没记。选一个日期就记下来，不记就从第一张照片算起。")
                    }
                }
            }
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if hasUnsavedChanges {
                            isConfirmingCancel = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if savingDeletesOldCover {
                            isConfirmingCoverReplacement = true
                        } else {
                            save()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("换掉原来的封面？", isPresented: $isConfirmingCoverReplacement, titleVisibility: .visible) {
                Button("保存", role: .destructive) { save() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("原来那张封面会被删除，无法恢复。")
            }
            .confirmationDialog("放弃这些修改？", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                Button("放弃", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .confirmationDialog("封面照片", isPresented: $isChoosingCoverSource, titleVisibility: .visible) {
                if CameraPicker.isAvailable {
                    Button("拍照") { isShowingCamera = true }
                }
                Button("从相册选择") { isPickingFromLibrary = true }
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    isShowingCamera = false
                    if let image { newCoverImage = image }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPickingFromLibrary, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newValue in
                Task { await loadImage(from: newValue) }
            }
            .onChange(of: acquiredDate) { _, _ in
                hasAcquiredDate = true
            }
        }
    }

    /// 没设过封面就退回最新那张生长照，和详情页顶上看到的是同一张。
    @ViewBuilder
    private var coverPreview: some View {
        if let newCoverImage {
            Image(uiImage: newCoverImage)
                .resizable()
                .aspectRatio(contentMode: displayMode.contentMode)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
        } else {
            PhotoImageView(
                filename: plant.coverPhotoFilename ?? plant.latestGrowthEntry?.photoFilename,
                contentMode: displayMode.contentMode
            )
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }

    // MARK: - 操作

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        newCoverImage = image
    }

    private func save() {
        if let newCoverImage, let filename = PhotoStore.shared.save(newCoverImage) {
            let previous = plant.coverPhotoFilename
            plant.coverPhotoFilename = filename
            // 老封面有可能就是某张生长照（详情页里「设为封面」设过来的）——
            // 那张归那条记录所有，换封面不能顺手把它删了。
            let usedByEntry = plant.sortedGrowthEntries.contains { $0.photoFilename == previous }
            if !usedByEntry {
                PhotoStore.shared.delete(filename: previous)
            }
        }

        plant.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.notes = trimmedAbout.isEmpty ? nil : trimmedAbout
        plant.acquiredDate = hasAcquiredDate ? acquiredDate : nil
        plant.coverDisplayMode = displayMode
        plant.touch()

        try? modelContext.save()
        dismiss()
    }
}
