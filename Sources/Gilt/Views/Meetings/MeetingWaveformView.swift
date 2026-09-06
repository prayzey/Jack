import SwiftUI

/// Calm bar waveform reacting to the live audio RMS level. Single-color
/// (the recording accent) so it inherits whatever color the parent passes —
/// no purple, no gradients of its own.
struct MeetingWaveformView: View {
    let level: Double
    let accent: Color
    var barCount: Int = 56
    var minBarHeight: CGFloat = 4
    var maxBarHeight: CGFloat = 56

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            Canvas { canvasContext, size in
                draw(canvasContext: canvasContext, size: size, date: context.date)
            }
        }
        .frame(height: maxBarHeight)
        .accessibilityHidden(true)
    }

    private func draw(canvasContext: GraphicsContext, size: CGSize, date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        let gap: CGFloat = 4
        let barWidth = max(2, (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
        let midY = size.height / 2

        for i in 0..<barCount {
            let x = CGFloat(i) * (barWidth + gap)
            let normalizedIndex = Double(i) / Double(barCount - 1)
            // Subtle breathing motion + RMS-weighted center emphasis so the
            // waveform never looks dead during silent moments.
            let centerWeight = pow(1 - abs(0.5 - normalizedIndex) * 2, 1.6)
            let waveComponent = sin(normalizedIndex * .pi * 4 + now * 2.0) * 0.08
            let noise = sin(normalizedIndex * 12 + now * 1.7) * 0.04
            let activity = level * (0.45 + centerWeight * 1.0) + waveComponent + noise
            let amplitude = max(0.04, min(1.0, activity))

            let height = max(minBarHeight, CGFloat(amplitude) * maxBarHeight)
            let rect = CGRect(
                x: x,
                y: midY - height / 2,
                width: barWidth,
                height: height
            )

            // Center bars at full accent, taper toward the edges so the waveform
            // reads as a single shape instead of a noisy strip.
            let edgeFade = 0.45 + centerWeight * 0.55
            canvasContext.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(accent.opacity(edgeFade))
            )
        }
    }
}
