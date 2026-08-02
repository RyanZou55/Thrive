import PhotosUI
import SwiftData
import SwiftUI

/// 添加植物。名字 + 封面照片必填，其余可选。
struct AddPlantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var species = ""
    @State private var kind: PlantKind = .cactus
    @State private var wateringIntervalDays = 7
    @State private var acquiredDate = Date()
    @State private var hasAcquiredDate = false

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
                    PhotosPicker(selection: $pickerItem, matching: .images) {
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

                    Picker("类型", selection: $kind) {
                        ForEach(PlantKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    TextField("品种（可选）", text: $species)
                }

                Section("浇水") {
                    Stepper(
                        "每 \(wateringIntervalDays) 天浇一次",
                        value: $wateringIntervalDays,
                        in: 1...180
                    )
                    Text("到期当天早上 9 点提醒你。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("入手日期（可选）") {
                    Toggle("记录入手日期", isOn: $hasAcquiredDate.animation())
                    if hasAcquiredDate {
                        DatePicker("入手于", selection: $acquiredDate, displayedComponents: .date)
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
            .onChange(of: pickerItem) { _, newValue in
                Task { await loadImage(from: newValue) }
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

        let trimmedSpecies = species.trimmingCharacters(in: .whitespacesAndNewlines)
        let plant = Plant(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            coverPhotoFilename: filename,
            species: trimmedSpecies.isEmpty ? nil : trimmedSpecies,
            kind: kind,
            acquiredDate: hasAcquiredDate ? acquiredDate : nil,
            wateringIntervalDays: wateringIntervalDays,
            sortOrder: nextSortOrder()
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
