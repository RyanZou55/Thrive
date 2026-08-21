import PhotosUI
import SwiftData
import SwiftUI

/// 添加植物。名字 + 封面照片必填，其余可选。
struct AddPlantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var about = ""
    @State private var acquiredDate = Date()
    /// 用户没碰过日期选择器就不记入手日期，保持这一项可选。
    @State private var hasAcquiredDate = false

    // 封面可以拍一张，也可以从相册挑
    @State private var isChoosingCoverSource = false
    @State private var isShowingCamera = false
    @State private var isPickingFromLibrary = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coverImage != nil
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("封面照片") {
                    Button {
                        isChoosingCoverSource = true
                    } label: {
                        if let coverImage {
                            Image(uiImage: coverImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Label("选择一张照片", systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(coverImage == nil ? 16 : 8)
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
                    if !hasAcquiredDate {
                        Text("还没记。选一个日期就记下来。")
                    }
                }
            }
            .navigationTitle("添加植物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
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
                    if let image { coverImage = image }
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

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        coverImage = image
    }

    private func save() {
        guard let coverImage else { return }
        isSaving = true

        guard let filename = PhotoStore.shared.save(coverImage) else {
            isSaving = false
            return
        }

        let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
        let plant = Plant(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            coverPhotoFilename: filename,
            acquiredDate: hasAcquiredDate ? acquiredDate : nil,
            sortOrder: nextSortOrder(),
            notes: trimmedAbout.isEmpty ? nil : trimmedAbout
        )

        modelContext.insert(plant)
        try? modelContext.save()
        dismiss()
    }

    /// 新植物排在最后。
    private func nextSortOrder() -> Int {
        var descriptor = FetchDescriptor<Plant>(sortBy: [SortDescriptor(\Plant.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        let highest = (try? modelContext.fetch(descriptor))?.first?.sortOrder ?? -1
        return highest + 1
    }
}

#Preview {
    AddPlantView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
