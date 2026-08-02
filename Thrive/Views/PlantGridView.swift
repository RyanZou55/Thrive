import SwiftData
import SwiftUI

/// 首页：所有植物的网格。
struct PlantGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Plant.sortOrder), SortDescriptor(\Plant.createdAt)])
    private var plants: [Plant]

    @State private var isAddingPlant = false

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
                        Button("已浇水", systemImage: "drop.fill") {
                            water(plant)
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            delete(plant)
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
        Task { await WateringScheduler.shared.reschedule(for: plant) }
    }

    private func delete(_ plant: Plant) {
        WateringScheduler.shared.cancel(for: plant.id)

        // 级联删除只管数据库记录，磁盘上的照片得自己清。
        PhotoStore.shared.delete(filename: plant.coverPhotoFilename)
        for entry in plant.growthEntries ?? [] {
            PhotoStore.shared.delete(filename: entry.photoFilename)
        }

        modelContext.delete(plant)
        try? modelContext.save()
    }
}

#Preview {
    PlantGridView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
