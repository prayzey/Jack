import SwiftUI

/// One line of live words inside the pill. Letters ink in behind a soft edge
/// at the pace `DictationPillMotion` sets, unconfirmed words stay a shade
/// lighter, and once the line outgrows the pill it slides left with the
/// oldest words fading out at the leading edge.
struct DictationCaptionRibbon: View {
    let words: [String]
    let stableWordCount: Int
    let color: Color
    let viewportWidth: CGFloat
    /// Points of the line shown so far, to the far side of the soft edge.
    let revealedWidth: CGFloat
    var isWorking = false

    /// Width of the soft edge letters fade in across.
    static let inkEdge: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scrollOffset: CGFloat {
        let shown = min(DictationCaptionLayout.lineWidth(of: words), revealedWidth)
        return -max(0, shown - viewportWidth)
    }

    var body: some View {
        WordLine(words: words, stableWordCount: stableWordCount, color: color)
            .equatable()
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.black.frame(width: max(0, revealedWidth - Self.inkEdge))
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: min(Self.inkEdge, max(0, revealedWidth)))
                    Spacer(minLength: 0)
                }
            }
            .offset(x: scrollOffset)
            .frame(width: viewportWidth, height: DictationCaptionLayout.pillHeight, alignment: .leading)
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    // Fully clear for the first few points, so no sliver of a scrolled word shows.
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.2), .init(color: .black, location: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
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

/// The words themselves. Equatable, so the per-frame reveal only moves masks
/// and offsets and never rebuilds a long line of text.
private struct WordLine: View, Equatable {
    let words: [String]
    let stableWordCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: DictationCaptionLayout.wordSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .fixedSize()
                    .frame(width: DictationCaptionLayout.wordWidth(word), alignment: .leading)
                    .foregroundStyle(color.opacity(index < stableWordCount ? 1 : 0.6))
                    .contentTransition(.opacity)
            }
        }
        .font(.system(size: DictationCaptionLayout.fontSize, weight: .medium))
        .lineLimit(1)
        // A recognizer's fix to a word already shown crossfades in place.
        .animation(.easeOut(duration: 0.22), value: words)
        .animation(.easeOut(duration: 0.3), value: stableWordCount)
        .fixedSize()
    }
}
