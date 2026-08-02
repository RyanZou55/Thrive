import PhotosUI
import SwiftData
import SwiftUI

/// 拍摄页 —— App 的核心亮点。
///
/// 对齐三件套同时工作：
/// 1. 幽灵叠影：上一张照片半透明压在取景上，把植株挪回原位
/// 2. 姿态指示：拿当前俯仰/翻滚角和上次拍摄时存的角度比，对上了震一下
/// 3. 构图网格：九宫格 + 参考框，让花盆每次落在同一个位置
struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plant: Plant

    @StateObject private var camera = CameraService()
    @StateObject private var motion = MotionService()

    @State private var ghostOpacity: Double = 0.4
    @State private var showsGrid = true
    @State private var showsReferenceBox = false

    @State private var capturedImage: UIImage?
    @State private var poseAtCapture: DevicePose?
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var wasAligned = false

    /// 用来做叠影和角度对比的那张 —— 就是最近一张生长记录。
    private var referenceEntry: GrowthEntry? {
        plant.latestGrowthEntry
    }

    private var alignment: PoseAlignment {
        PoseAlignment.evaluate(current: motion.currentPose, reference: referenceEntry?.pose)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let capturedImage {
                reviewScreen(image: capturedImage)
            } else {
                cameraScreen
            }
        }
        .task {
            await camera.start()
            motion.start()
        }
        .onDisappear {
            camera.stop()
            motion.stop()
        }
        .onChange(of: camera.capturedImage) { _, newValue in
            guard let newValue else { return }
            // 快门按下那一刻的姿态，跟着照片一起存。
            poseAtCapture = motion.currentPose
            capturedImage = newValue
        }
        .onChange(of: alignment.isAligned) { _, isAligned in
            // 刚好对上时轻震一下，眼睛可以一直盯着取景框。
            if isAligned && !wasAligned {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            wasAligned = isAligned
        }
        .onChange(of: pickerItem) { _, newValue in
            Task { await loadFromLibrary(newValue) }
        }
    }

    // MARK: - 取景

    private var cameraScreen: some View {
        ZStack {
            switch camera.status {
            case .ready:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            case .denied:
                unavailableScreen(
                    title: "没有相机权限",
                    message: "去「设置 → Thrive → 相机」打开权限，或者直接从相册选一张。"
                )
            case let .unavailable(reason):
                unavailableScreen(title: "用不了相机", message: reason)
            case .idle:
                ProgressView().tint(.white)
            }

            if case .ready = camera.status {
                GhostOverlay(filename: referenceEntry?.photoFilename, opacity: ghostOpacity)
                    .ignoresSafeArea()

                if showsGrid {
                    CompositionGrid(showsReferenceBox: showsReferenceBox)
                        .ignoresSafeArea()
                }
            }

            VStack {
                topBar
                Spacer()
                bottomControls
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }

            Spacer()

            Button {
                showsGrid.toggle()
            } label: {
                Image(systemName: showsGrid ? "grid" : "grid.circle")
                    .font(.title3)
                    .foregroundStyle(showsGrid ? .yellow : .white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }

            Button {
                showsReferenceBox.toggle()
            } label: {
                Image(systemName: showsReferenceBox ? "rectangle.dashed" : "rectangle")
                    .font(.title3)
                    .foregroundStyle(showsReferenceBox ? .yellow : .white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if motion.isAvailable && referenceEntry?.pose != nil {
                PoseIndicatorBar(alignment: alignment)
                    .padding(.horizontal, 16)
            }

            if referenceEntry != nil {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.white)
                    Slider(value: $ghostOpacity, in: 0...0.85)
                    Text("叠影")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
            }

            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.35), in: Circle())
                }

                Spacer()

                Button {
                    camera.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(alignment.isAligned ? Color.green : Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(camera.status != .ready || camera.isCapturing)
                .opacity(camera.status == .ready ? 1 : 0.4)

                Spacer()

                // 占位，让快门保持居中。
                Color.clear.frame(width: 52, height: 52)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func unavailableScreen(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    // MARK: - 确认页

    private func reviewScreen(image: UIImage) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                        // 保留叠影，方便在保存前最后确认一次对得齐不齐。
                        if let referenceEntry, ghostOpacity > 0 {
                            PhotoImageView(filename: referenceEntry.photoFilename, contentMode: .fit)
                                .opacity(ghostOpacity * 0.6)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    TextField("这次有什么变化？（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)

                    if let poseAtCapture {
                        Label(
                            String(format: "已记录角度：俯仰 %.1f° · 翻滚 %.1f°", poseAtCapture.pitch, poseAtCapture.roll),
                            systemImage: "gyroscope"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .navigationTitle("这张留下吗？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重拍") { discard() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(image: image) }
                }
            }
        }
    }

    // MARK: - 操作

    private func loadFromLibrary(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        // 相册里的图没有实时姿态可言，pose 就留空。
        poseAtCapture = nil
        capturedImage = image
    }

    private func discard() {
        capturedImage = nil
        camera.capturedImage = nil
        poseAtCapture = nil
        pickerItem = nil
        note = ""
    }

    private func save(image: UIImage) {
        guard let filename = PhotoStore.shared.save(image) else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = GrowthEntry(
            photoFilename: filename,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            refEntryID: referenceEntry?.id,
            pose: poseAtCapture
        )
        entry.plant = plant
        modelContext.insert(entry)

        // 第一张生长照顺手当封面。
        if plant.coverPhotoFilename == nil {
            plant.coverPhotoFilename = filename
        }
        plant.touch()

        try? modelContext.save()
        dismiss()
    }
}
