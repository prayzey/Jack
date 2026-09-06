import SwiftUI

/// Post-release caption — frozen live transcript, writing frontier, and a static
/// dim wash so the user knows transcribe / polish / paste is still in flight.
struct DictationProcessingCaptionView: View {
    let transcript: String
    let statusLabel: String
    let palette: DictationPillPalette
    let frontierColor: Color
    let width: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    var leadingContentInset: CGFloat = 0
    var trailingContentInset: CGFloat = 0
    var emphasizesPaste: Bool = false

    private static let orbDiameter: CGFloat = 9
    private static let orbGap: CGFloat = 5

    @State private var frontier = TextFrontierMetrics()

    private var trimmed: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var textMaxWidth: CGFloat {
        max(1, width - horizontalPadding * 2 - leadingContentInset - trailingContentInset)
    }

    private var orbCenter: CGPoint {
        CGPoint(
            x: leadingContentInset + horizontalPadding + frontier.caretTrailingX + Self.orbGap + Self.orbDiameter * 0.5,
            y: verticalPadding + frontier.caretCenterY
        )
    }

    private var naturalHeight: CGFloat {
        frontier.contentHeight + verticalPadding * 2
    }

    private var displayHeight: CGFloat {
        min(max(naturalHeight, minHeight), maxHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if trimmed.isEmpty {
                emptyStatus
            } else {
                frozenTranscriptLayer
                frontierGlow
                processingOrbLayer
            }

            processingOverlay
        }
        .frame(width: width, height: displayHeight, alignment: .topLeading)
        .clipped()
        .onAppear { refreshFrontier() }
        .onChange(of: transcript) { _, _ in refreshFrontier() }
    }

    // MARK: - Layers

    private var frozenTranscriptLayer: some View {
        Text(trimmed)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(palette.captionText.opacity(0.42))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: textMaxWidth, alignment: .leading)
            .padding(.leading, horizontalPadding + leadingContentInset)
            .padding(.trailing, horizontalPadding + trailingContentInset)
            .padding(.vertical, verticalPadding)
    }

    private var emptyStatus: some View {
        Text(statusLabel)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(palette.captionText.opacity(0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, horizontalPadding + leadingContentInset)
            .padding(.trailing, horizontalPadding + trailingContentInset)
    }

    /// Static dim wash — no TimelineView; avoids continuous redraw during ANE work.
    private var processingOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(emphasizesPaste ? 0.06 : 0.04))
            .allowsHitTesting(false)
    }

    private var frontierGlow: some View {
        let lineSpan = fontSize * 1.35
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        frontierColor.opacity(0.45),
                        frontierColor.opacity(0.1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2.5, height: lineSpan)
            .position(
                x: leadingContentInset + horizontalPadding + frontier.caretTrailingX + Self.orbGap * 0.35 + 1,
                y: verticalPadding + frontier.caretCenterY
            )
            .opacity(0.65)
    }

    private var processingOrbLayer: some View {
        DictationCaptionOrb(color: frontierColor, level: emphasizesPaste ? 0.72 : 0.48)
            .position(orbCenter)
    }

    private func refreshFrontier() {
        frontier = TextFrontierMeasurer.measure(
            text: trimmed,
            fontSize: fontSize,
            maxWidth: textMaxWidth
        )
    }
}