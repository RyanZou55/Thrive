import PhotosUI
import SwiftData
import SwiftUI

/// 植物详情：封面 · 浇水按钮 · 时间轴。
struct PlantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plant: Plant

    @State private var isCapturing = false
    @State private var selectedEntry: GrowthEntry?
    @State private var viewedPhoto: ViewedPhoto?

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
        .fullScreenCover(item: $viewedPhoto) { photo in
            PhotoViewerView(filename: photo.filename)
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
                        GrowthEntryRow(
                            entry: entry,
                            plant: plant,
                            onOpenDetail: { selectedEntry = entry },
                            onOpenPhoto: { viewedPhoto = ViewedPhoto(filename: $0) }
                        )
                    case let .care(record):
                        CareRecordRow(record: record) { viewedPhoto = ViewedPhoto(filename: $0) }
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

/// 时间轴每行左边那个圆形图标。
struct TimelineIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(.quaternary, in: Circle())
    }
}

/// 时间轴右侧的缩略图，点开看大图。
struct TimelineThumbnail: View {
    let filename: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            PhotoImageView(filename: filename)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 时间轴上的一条养护记录。
struct CareRecordRow: View {
    let record: CareRecord
    var onOpenPhoto: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TimelineIcon(systemName: record.symbolName)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(.subheadline.weight(.medium))
                Text(record.performedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let filename = record.photoFilename, !filename.isEmpty {
                TimelineThumbnail(filename: filename) { onOpenPhoto(filename) }
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 时间轴上的一条生长记录。
struct GrowthEntryRow: View {
    let entry: GrowthEntry
    let plant: Plant
    var onOpenDetail: () -> Void
    var onOpenPhoto: (String) -> Void

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
            TimelineIcon(systemName: "camera.fill")

            // 文字区点开生长记录详情（姿态数据、删除都在那里）
            Button(action: onOpenDetail) {
                HStack(spacing: 6) {
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

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TimelineThumbnail(filename: entry.photoFilename) { onOpenPhoto(entry.photoFilename) }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
