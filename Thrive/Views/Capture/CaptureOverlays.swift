import SwiftUI

/// 对齐三件套之一：构图网格（九宫格 + 可选中心参考框）。
struct CompositionGrid: View {
    var showsReferenceBox: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                Path { path in
                    for index in 1...2 {
                        let x = size.width * CGFloat(index) / 3
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))

                        let y = size.height * CGFloat(index) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(.white.opacity(0.35), lineWidth: 0.5)

                if showsReferenceBox {
                    // 参考框：花盆每次放在同一个位置，比只看叠影更好使。
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .frame(width: size.width * 0.62, height: size.height * 0.52)
                        .position(x: size.width / 2, y: size.height * 0.52)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 对齐三件套之二：幽灵叠影 —— 上一张照片半透明压在实时取景上。
struct GhostOverlay: View {
    let filename: String?
    var opacity: Double

    var body: some View {
        PhotoImageView(filename: filename)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// 对齐三件套之三：姿态指示条。对齐时变绿。
struct PoseIndicatorBar: View {
    let alignment: PoseAlignment

    private var tint: Color {
        switch alignment {
        case .aligned: return .green
        case .off: return .orange
        case .noReference: return .white
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: alignment.isAligned ? "checkmark.circle.fill" : "gyroscope")
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(alignment.hint)
                    .font(.subheadline.weight(.medium))
                if case let .off(pitchDelta, rollDelta) = alignment {
                    Text(String(format: "俯仰 %+.1f° · 翻滚 %+.1f°", pitchDelta, rollDelta))
                        .font(.caption2.monospacedDigit())
                        .opacity(0.8)
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.15), value: alignment.isAligned)
    }
}
