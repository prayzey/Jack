import SwiftUI

/// Volume slider for the sound panel.
///
/// `.master` is a thick bar like Control Center's, with the speaker glyph
/// riding inside the fill. `.row` is slim with a thumb; when `showsLevel` is
/// on, the fill dims and the live level pulses brighter inside it, so you can
/// see how loud an app is right now against where its volume is set.
struct SoundSlider: View {
    enum Style { case master, row }

    let value: Double
    var level: Float = 0
    var showsLevel = false
    var style: Style = .row
    var symbol = "speaker.wave.2.fill"
    let label: String
    let onChange: (Double) -> Void

    @State private var isDragging = false
    @State private var isHovering = false

    private var trackHeight: CGFloat { style == .master ? 22 : 5 }
    private var thumbSize: CGFloat { 13 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                if style == .master {
                    masterTrack(width: width)
                } else {
                    rowTrack(width: width)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let inset = style == .row ? thumbSize / 2 : 0
                        onChange(min(1, max(0, (drag.location.x - inset) / max(width - inset * 2, 1))))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: style == .master ? trackHeight : 16)
        .onHover { isHovering = $0 }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, value + 0.05))
            case .decrement: onChange(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }

    private func masterTrack(width: CGFloat) -> some View {
        // Never thinner than the glyph's circle, so 0% still reads as a control.
        let fill = max(trackHeight, width * value)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.13))
            Capsule()
                .fill(Color.primary.opacity(isDragging ? 0.95 : 0.88))
                .frame(width: fill)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .frame(width: trackHeight, height: trackHeight)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: trackHeight)
        .animation(isDragging ? nil : .snappy(duration: 0.18), value: value)
    }

    private func rowTrack(width: CGFloat) -> some View {
        let usable = max(width - thumbSize, 1)
        let fill = thumbSize / 2 + usable * value
        let meter = fill * CGFloat(min(max(level, 0), 1))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.12))
                .frame(height: trackHeight)
            Capsule()
                .fill(Color.primary.opacity(showsLevel ? 0.32 : 0.62))
                .frame(width: fill, height: trackHeight)
            if showsLevel {
                Capsule()
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: meter, height: trackHeight)
                    .animation(.linear(duration: 1.0 / 24), value: level)
            }
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(isDragging ? 1.12 : (isHovering ? 1.05 : 1))
                .offset(x: usable * value)
                .animation(.snappy(duration: 0.15), value: isDragging)
        }
        .animation(isDragging ? nil : .snappy(duration: 0.18), value: value)
    }
}
