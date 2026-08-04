import PhotosUI
import SwiftData
import SwiftUI

/// 植物详情：封面 · 浇水按钮 · 时间轴。
struct PlantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plant: Plant

    @State private var isCapturing = false
    @State private var selectedEntry: GrowthEntry?

    // 浇水时可以顺手拍一张
    @State private var isChoosingWaterPhoto = false
    @State private var isShowingCamera = false
    @State private var isPickingFromLibrary = false
    @State private var waterPhotoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                wateringCard
                timeline
            }
            .padding(16)
        }
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCapturing = true
                } label: {
                    Label("拍生长照", systemImage: "camera")
                }
            }
        }
        .fullScreenCover(isPresented: $isCapturing) {
            CaptureView(plant: plant)
        }
        .sheet(item: $selectedEntry) { entry in
            GrowthEntryDetailView(entry: entry, plant: plant)
        }
        .confirmationDialog("记录这次浇水", isPresented: $isChoosingWaterPhoto, titleVisibility: .visible) {
            if CameraPicker.isAvailable {
                Button("拍照") { isShowingCamera = true }
            }
            Button("从相册选择") { isPickingFromLibrary = true }
            Button("只记录，不拍照") { saveWatering(photo: nil) }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                if let image { saveWatering(photo: image) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isPickingFromLibrary, selection: $waterPhotoItem, matching: .images)
        .onChange(of: waterPhotoItem) { _, newValue in
            Task { await saveWatering(from: newValue) }
        }
    }

    // MARK: - 封面

    private var header: some View {
        VStack(spacing: 8) {
            PhotoImageView(filename: plant.latestGrowthEntry?.photoFilename ?? plant.coverPhotoFilename)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                if let kind = plant.kind {
                    Label(kind.displayName, systemImage: "leaf")
                }
                if let species = plant.species, !species.isEmpty {
                    Text(species)
                }
                if let acquiredDate = plant.acquiredDate {
                    Text("入手于 \(acquiredDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 浇水

    private var wateringCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plant.lastWateredText)
                    .font(.headline)
                if let lastWateredAt = plant.lastWateredAt {
                    Text(lastWateredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                isChoosingWaterPhoto = true
            } label: {
                Label("浇水", systemImage: "drop.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 时间轴

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间轴")
                    .font(.headline)
                Spacer()
                Text("\(plant.sortedGrowthEntries.count) 张生长照")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if plant.timelineItems.isEmpty {
                VStack(spacing: 8) {
                    Text("还没有记录")
                        .foregroundStyle(.secondary)
                    Button("拍第一张") { isCapturing = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(plant.timelineItems) { item in
                    switch item {
                    case let .growth(entry):
                        Button {
                            selectedEntry = entry
                        } label: {
                            GrowthEntryRow(entry: entry, plant: plant)
                        }
                        .buttonStyle(.plain)
                    case let .care(record):
                        CareRecordRow(record: record)
                    }
                }
            }
        }
    }

    // MARK: - 操作

    /// 从相册选完图后走这条。
    private func saveWatering(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        waterPhotoItem = nil
        saveWatering(photo: image)
    }

    /// photo 为 nil 就是「只记录，不拍照」。
    private func saveWatering(photo: UIImage?) {
        let record = CareRecord(
            type: .water,
            photoFilename: photo.flatMap { PhotoStore.shared.save($0) }
        )
        record.plant = plant
        modelContext.insert(record)

        plant.lastWateredAt = record.performedAt
        plant.touch()

        try? modelContext.save()
    }
}

/// 时间轴上的一条养护记录。带照片的显示缩略图，没照片的收成一行。
struct CareRecordRow: View {
    let record: CareRecord

    var body: some View {
        HStack(spacing: 12) {
            if let filename = record.photoFilename, !filename.isEmpty {
                PhotoImageView(filename: filename)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: record.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.quaternary, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(.subheadline.weight(.medium))
                Text(record.performedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 时间轴上的一行。
struct GrowthEntryRow: View {
    let entry: GrowthEntry
    let plant: Plant

    /// 距离入手 / 第一张照片过了多少天，让时间跨度更直观。
    private var dayLabel: String? {
        let origin = plant.acquiredDate
            ?? plant.sortedGrowthEntries.last?.capturedAt
            ?? plant.createdAt
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: origin),
            to: Calendar.current.startOfDay(for: entry.capturedAt)
        ).day ?? 0
        return days > 0 ? "第 \(days) 天" : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoImageView(filename: entry.photoFilename)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.medium))
                    if let dayLabel {
                        Text(dayLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if entry.pose != nil {
                    Label("已记录拍摄角度", systemImage: "gyroscope")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
