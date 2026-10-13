import SwiftUI

/// One line of live words inside the pill. New words rise into place,
/// unconfirmed words stay a shade lighter, and once the line outgrows the pill
/// it slides left with the oldest words fading out at the leading edge.
struct DictationCaptionRibbon: View {
    let words: [String]
    let stableWordCount: Int
    let color: Color
    let viewportWidth: CGFloat
    var isWorking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scrollOffset: CGFloat { -max(0, DictationCaptionLayout.lineWidth(of: words) - viewportWidth) }

    var body: some View {
        HStack(spacing: DictationCaptionLayout.wordSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .fixedSize()
                    .frame(width: DictationCaptionLayout.wordWidth(word), alignment: .leading)
                    .foregroundStyle(color.opacity(index < stableWordCount ? 1 : 0.6))
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .wordArrival, removal: .opacity))
            }
        }
        .font(.system(size: DictationCaptionLayout.fontSize, weight: .medium))
        .lineLimit(1)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: words)
        .fixedSize()
        // A spring keeps its speed when the next word retargets it, so a burst
        // of words reads as one glide instead of small steps.
        .offset(x: scrollOffset)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1), value: scrollOffset)
        .frame(width: viewportWidth, height: DictationCaptionLayout.pillHeight, alignment: .leading)
        .mask(alignment: .leading) {
            HStack(spacing: 0) {
                // Fully clear for the first few points, so no sliver of a scrolled word shows.
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.2), .init(color: .black, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: scrollOffset < 0 ? 36 : 0)
                Color.black
            }
        }
        .mask { workingSheen }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("dictation.overlay.transcript", default: "Live transcript"))
        .accessibilityValue(words.joined(separator: " "))
    }

    /// While Jack polishes, a band of light passes over the words.
    @ViewBuilder
    private var workingSheen: some View {
        if isWorking, !reduceMotion {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                let center = -0.3 + phase * 1.6
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .black.opacity(0.45), location: min(1, max(0, center - 0.18))),
                        .init(color: .black, location: min(1, max(0, center))),
                        .init(color: .black.opacity(0.45), location: min(1, max(0, center + 0.18))),
                        .init(color: .black.opacity(0.45), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        } else {
            Color.black.opacity(isWorking ? 0.7 : 1)
        }
    }
}

private struct WordArrival: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 3)
            .offset(y: (1 - progress) * 5)
    }
}

private extension AnyTransition {
    static var wordArrival: AnyTransition {
        .modifier(active: WordArrival(progress: 0), identity: WordArrival(progress: 1))
    }
}
