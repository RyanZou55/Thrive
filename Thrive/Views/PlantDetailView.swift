import SwiftData
import SwiftUI

/// 植物详情：封面 · 浇水按钮 · 时间轴。
struct PlantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plant: Plant

    /// 非 nil 就是正在拍照，值决定这张最后存成生长照还是浇水记录。
    @State private var capturePurpose: CapturePurpose?
    @State private var selectedEntry: GrowthEntry?
    @State private var selectedCareRecord: CareRecord?
    @State private var viewedPhoto: ViewedPhoto?

    // 浇水时可以顺手拍一张
    @State private var isChoosingWaterPhoto = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                actionCard
                timeline
            }
            .padding(16)
        }
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $capturePurpose) { purpose in
            CaptureView(plant: plant, purpose: purpose)
        }
        .sheet(item: $selectedEntry) { entry in
            GrowthEntryDetailView(entry: entry, plant: plant)
        }
        .sheet(item: $selectedCareRecord) { record in
            CareRecordDetailView(record: record)
        }
        .fullScreenCover(item: $viewedPhoto) { photo in
            PhotoViewerView(filename: photo.filename)
        }
        .confirmationDialog("记录这次浇水", isPresented: $isChoosingWaterPhoto, titleVisibility: .visible) {
            Button("拍照") { capturePurpose = .watering }
            Button("只记录，不拍照") { saveWatering() }
            Button("取消", role: .cancel) {}
        }
        .onDisappear {
            // 入手日期和封面显示方式是直接写进模型的，关掉时落一次盘。
            try? modelContext.save()
        }
    }

    // MARK: - 封面

    /// 顶部展示的是最新一张生长照，没有就退回封面。
    private var headerPhotoFilename: String? {
        plant.latestGrowthEntry?.photoFilename ?? plant.coverPhotoFilename
    }

    private var header: some View {
        VStack(spacing: 8) {
            coverPhoto

            VStack(alignment: .leading, spacing: 6) {
                if let about = plant.notes, !about.isEmpty {
                    Text(about)
                        .font(.subheadline)
                }
                acquiredDateRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 入手日期事后也能改。没记过就先给个补记的入口。
    private var acquiredDateRow: some View {
        HStack(spacing: 6) {
            if plant.acquiredDate == nil {
                Button("记录入手日期") {
                    // 补记时别默认今天 —— 已经养了半年的植株填今天，
                    // 时间轴上的「第 N 天」会全部消失。用最早那张生长照当起点，
                    // 和 dayLabel 算天数时的回退链保持一致。
                    plant.acquiredDate = plant.sortedGrowthEntries.last?.capturedAt ?? plant.createdAt
                    plant.touch()
                }
            } else {
                Text("入手于")
                    .foregroundStyle(.secondary)
                DatePicker(
                    "入手日期",
                    selection: acquiredDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()

                Button {
                    plant.acquiredDate = nil
                    plant.touch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("不记录入手日期"))
            }
        }
        .font(.caption)
    }

    /// acquiredDate 是可选的，DatePicker 要非可选，这里桥一下。
    /// 只在 plant.acquiredDate != nil 时使用。
    private var acquiredDate: Binding<Date> {
        Binding(
            get: { plant.acquiredDate ?? Date() },
            set: { newValue in
                plant.acquiredDate = newValue
                plant.touch()
            }
        )
    }

    /// 点开看大图；右下角那个小按钮换显示方式。
    private var coverPhoto: some View {
        Button {
            if let headerPhotoFilename {
                viewedPhoto = ViewedPhoto(filename: headerPhotoFilename)
            }
        } label: {
            PhotoImageView(filename: headerPhotoFilename, contentMode: plant.coverDisplayMode.contentMode)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
        }
        .buttonStyle(.plain)
        .disabled(headerPhotoFilename == nil)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            displayModeMenu
                .padding(10)
        }
    }

    private var displayModeMenu: some View {
        Menu {
            Picker(selection: $plant.coverDisplayMode) {
                ForEach(CoverDisplayMode.allCases) { mode in
                    Label { Text(mode.title) } icon: { Image(systemName: mode.symbolName) }
                        .tag(mode)
                }
            } label: {
                Text("显示方式")
            }
        } label: {
            Image(systemName: "aspectratio")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(Text("显示方式"))
    }

    // MARK: - 两个写入口

    /// 拍生长照和浇水是这个 App 仅有的两种记录，做成并排等宽的两个按钮。
    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plant.lastWateredText)
                    .font(.headline)
                if let lastWateredAt = plant.lastWateredAt {
                    Text(lastWateredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // maxHeight + fixedSize：让两个按钮一样高，
            // 否则某种语言下一边的文字折成两行就会比另一边高出一截。
            HStack(spacing: 10) {
                Button {
                    capturePurpose = .growth
                } label: {
                    Label("拍生长照", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button {
                    isChoosingWaterPhoto = true
                } label: {
                    Label("浇水", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                    Button("拍第一张") { capturePurpose = .growth }
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
                        CareRecordRow(
                            record: record,
                            onOpenDetail: { selectedCareRecord = record },
                            onOpenPhoto: { viewedPhoto = ViewedPhoto(filename: $0) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 操作

    /// 「只记录，不拍照」。带照片的那条在 CaptureView 里存。
    private func saveWatering() {
        let record = CareRecord(type: .water)
        record.plant = plant
        modelContext.insert(record)

        plant.lastWateredAt = record.performedAt
        plant.touch()

        try? modelContext.save()
    }
}

extension CoverDisplayMode {
    var title: String {
        switch self {
        case .fill: String(localized: "填满裁剪")
        case .fit: String(localized: "完整显示")
        }
    }

    var symbolName: String {
        switch self {
        case .fill: "rectangle.fill"
        case .fit: "rectangle.inset.filled"
        }
    }

    var contentMode: ContentMode {
        switch self {
        case .fill: .fill
        case .fit: .fit
        }
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
    var onOpenDetail: () -> Void
    var onOpenPhoto: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TimelineIcon(systemName: record.symbolName)

            // 文字区点开详情，在那里补备注
            Button(action: onOpenDetail) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName)
                            .font(.subheadline.weight(.medium))
                        Text(record.performedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let note = record.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
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
        return days > 0 ? String(localized: "第 \(days) 天") : nil
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
