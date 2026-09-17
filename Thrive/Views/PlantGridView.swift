import SwiftData
import SwiftUI

/// 首页：所有植物的网格。
struct PlantGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Plant.sortOrder), SortDescriptor(\Plant.createdAt)])
    private var plants: [Plant]

    @State private var isAddingPlant = false
    /// 待删除的那株。非 nil 就是确认框开着 —— 长按菜单离「浇水」只有一行，
    /// 而这一下点下去整株连同所有照片都没了。
    @State private var plantPendingDeletion: Plant?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if plants.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Thrive")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingPlant = true
                    } label: {
                        Label("添加植物", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingPlant) {
                AddPlantView()
            }
            .confirmationDialog(
                String(format: String(localized: "删除「%@」？"), plantPendingDeletion?.name ?? ""),
                isPresented: Binding(
                    get: { plantPendingDeletion != nil },
                    set: { if !$0 { plantPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let plantPendingDeletion { delete(plantPendingDeletion) }
                    plantPendingDeletion = nil
                }
                Button("取消", role: .cancel) { plantPendingDeletion = nil }
            } message: {
                Text("所有生长照、转盘和浇水记录都会一起删除，无法恢复。")
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(plants) { plant in
                    NavigationLink(value: plant.id) {
                        PlantCardView(plant: plant)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("浇水", systemImage: "drop.fill") {
                            water(plant)
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            plantPendingDeletion = plant
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationDestination(for: UUID.self) { plantID in
            if let plant = plants.first(where: { $0.id == plantID }) {
                PlantDetailView(plant: plant)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有植物", systemImage: "leaf")
        } description: {
            Text("加入第一株，从今天开始记录它的变化。")
        } actions: {
            Button("添加植物") { isAddingPlant = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 操作

    private func water(_ plant: Plant) {
        let record = CareRecord(type: .water)
        record.plant = plant
        modelContext.insert(record)

        plant.lastWateredAt = record.performedAt
        plant.touch()

        try? modelContext.save()
    }

    private func delete(_ plant: Plant) {
        // 级联删除只管数据库记录，磁盘上的照片得自己清。
        PhotoStore.shared.delete(filename: plant.coverPhotoFilename)
        for entry in plant.growthEntries ?? [] {
            PhotoStore.shared.delete(filename: entry.photoFilename)
            PhotoStore.shared.deleteSpinFrames(entry.spinFilenames)
        }
        for record in plant.careRecords ?? [] {
            PhotoStore.shared.delete(filename: record.photoFilename)
        }

        modelContext.delete(plant)
        try? modelContext.save()
    }
}

#Preview {
    PlantGridView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
