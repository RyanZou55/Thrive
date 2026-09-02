import SwiftUI

/// 转盘播放器：左右拖动换帧。
///
/// 不拖它就是张静止的照片 —— 停在哪一帧由外面决定，
/// 详情页打开时停在封面那一帧，和这条记录的主照片同一个角度。
struct SpinPlayerView: View {
    let filenames: [String]
    /// 当前停在第几帧。外面拿着，确认页要靠它知道选了哪一帧当封面。
    @Binding var index: Int
    var onTap: () -> Void

    /// 解码尺寸。按满屏宽度的 2 倍左右取的 —— 24 帧全按 1280 解开是 200MB，
    /// 屏幕上根本用不到那么多像素。
    ///
    /// 实测（iPhone 17 Pro 模拟器，24 帧）：打开这页占用从 55MB 涨到 124MB，
    /// 峰值 129MB；反复进出四轮，占用和峰值都不再动 —— 关掉时确实放掉了。
    private static let decodeMaxPixelSize = 1000
    /// 手指划过多少点换一帧。整屏宽度大致对应转一圈。
    private static let pointsPerFrame: CGFloat = 14

    @State private var frames: [UIImage] = []
    /// 这一次拖动的起点帧。没在拖就是 nil。
    @State private var indexAtDragStart: Int?

    /// index 是外面给的，越界了也不能崩。
    private var safeIndex: Int {
        min(max(index, 0), max(filenames.count - 1, 0))
    }

    private var currentFilename: String? {
        filenames.isEmpty ? nil : filenames[safeIndex]
    }

    /// 整圈才首尾相接。半圈的转盘绕回去会跳一下，不如拖到头就停。
    private var isFullCircle: Bool {
        filenames.count == SpinFrameSelector.frameCount
    }

    var body: some View {
        ZStack {
            if frames.isEmpty {
                // 解码这一小会儿先拿这一帧的图顶上，别闪一块空白。
                PhotoImageView(filename: currentFilename, contentMode: .fit)
            } else {
                Image(uiImage: frames[min(safeIndex, frames.count - 1)])
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Label("\(safeIndex + 1)/\(frames.isEmpty ? filenames.count : frames.count)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard !frames.isEmpty else { return }
                    // 起点在第一下 onChanged 里记，index 是外面给的，不能假定从 0 开始。
                    let start = indexAtDragStart ?? index
                    indexAtDragStart = start
                    let steps = Int(value.translation.width / Self.pointsPerFrame)
                    // 往右拖，植物跟着手指往右转，露出的是原本在左边的那一面。
                    index = wrapped(start - steps)
                }
                .onEnded { _ in
                    indexAtDragStart = nil
                }
        )
        .onTapGesture(perform: onTap)
        .task { await loadFrames() }
        .onDisappear { frames = [] }
    }

    private func wrapped(_ raw: Int) -> Int {
        let count = frames.count
        guard count > 0 else { return 0 }
        guard isFullCircle else { return min(max(raw, 0), count - 1) }
        return ((raw % count) + count) % count
    }

    private func loadFrames() async {
        let names = filenames
        let size = Self.decodeMaxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) {
            names.compactMap { PhotoStore.shared.spinFrame(named: $0, maxPixelSize: size) }
        }.value

        // 缺帧就不进转盘模式，退回静态图 —— 少一帧转起来会卡一下。
        guard decoded.count == names.count else { return }
        frames = decoded
    }
}
