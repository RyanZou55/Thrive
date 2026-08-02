import SwiftData
import SwiftUI

/// 植物详情：封面 · 浇水按钮 · 生长时间轴。
struct PlantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plant: Plant

    @State private var isCapturing = false
    @State private var selectedEntry: GrowthEntry?

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plant.wateringStatusText)
                        .font(.headline)
                        .foregroundStyle(plant.isWateringDue ? Color.orange : Color.primary)
                    if let lastWateredAt = plant.lastWateredAt {
                        Text("上次浇水 \(lastWateredAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    water()
                } label: {
                    Label("已浇水", systemImage: "drop.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Stepper(
                "间隔 \(plant.wateringIntervalDays) 天",
                value: $plant.wateringIntervalDays,
                in: 1...180
            )
            .font(.subheadline)
            .onChange(of: plant.wateringIntervalDays) { _, _ in
                plant.touch()
                try? modelContext.save()
                Task { await WateringScheduler.shared.reschedule(for: plant) }
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 时间轴

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("生长时间轴")
                    .font(.headline)
                Spacer()
                Text("\(plant.sortedGrowthEntries.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if plant.sortedGrowthEntries.isEmpty {
                VStack(spacing: 8) {
                    Text("还没有生长记录")
                        .foregroundStyle(.secondary)
                    Button("拍第一张") { isCapturing = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(plant.sortedGrowthEntries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        GrowthEntryRow(entry: entry, plant: plant)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 操作

    private func water() {
        let record = CareRecord(type: .water)
        record.plant = plant
        modelContext.insert(record)

        plant.lastWateredAt = record.performedAt
        plant.touch()

        try? modelContext.save()
        Task { await WateringScheduler.shared.reschedule(for: plant) }
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
