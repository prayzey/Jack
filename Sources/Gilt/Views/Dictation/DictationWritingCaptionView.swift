import AppKit
import SwiftUI

// MARK: - Text measurement

/// Glyph-accurate caret position for wrapped caption text.
struct TextFrontierMetrics: Equatable {
    var caretTrailingX: CGFloat = 0
    var caretCenterY: CGFloat = 0
    var contentHeight: CGFloat = 0
}

enum TextFrontierMeasurer {
    static func measure(
        text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight = .medium,
        maxWidth: CGFloat
    ) -> TextFrontierMetrics {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let lineHeight = font.ascender - font.descender + font.leading

        guard !text.isEmpty else {
            return TextFrontierMetrics(
                caretTrailingX: 0,
                caretCenterY: lineHeight * 0.5,
                contentHeight: lineHeight
            )
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
            ]
        )

        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let container = NSTextContainer(
            size: NSSize(width: max(1, maxWidth), height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        let glyphRange = layout.glyphRange(for: container)
        guard glyphRange.length > 0 else {
            return TextFrontierMetrics(
                caretTrailingX: 0,
                caretCenterY: lineHeight * 0.5,
                contentHeight: lineHeight
            )
        }

        let lastGlyph = glyphRange.upperBound - 1
        let caretRect = layout.boundingRect(
            forGlyphRange: NSRange(location: lastGlyph, length: 1),
            in: container
        )
        let usedRect = layout.usedRect(for: container)

        return TextFrontierMetrics(
            caretTrailingX: caretRect.maxX,
            caretCenterY: caretRect.midY,
            contentHeight: max(usedRect.height, lineHeight)
        )
    }
}

// MARK: - Writing frontier caption

/// Live caption with an Aqua-inspired **writing frontier**: confirmed transcript
/// on the left and a theme-colored orb at the insertion point. The container
/// size is fixed. Text and its cursor move together in one clipped viewport.
struct DictationWritingCaptionView: View {
    let transcript: String
    /// Leading words rendered sharp; the tentative tail stays readable at a lighter weight.
    var stableWordCount: Int = 0
    let level: Double
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

    private static let orbDiameter: CGFloat = 9
    private static let orbGap: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText = ""
    @State private var displayedStableWordCount = 0
    @State private var textTransition: ContentTransition = .identity
    @State private var frontier = TextFrontierMetrics()

    private var textMaxWidth: CGFloat {
        max(1, width - horizontalPadding * 2 - leadingContentInset - trailingContentInset
            - Self.orbDiameter - Self.orbGap)
    }

    private var naturalHeight: CGFloat {
        frontier.contentHeight + verticalPadding * 2
    }

    private var displayHeight: CGFloat {
        min(max(naturalHeight, minHeight), maxHeight)
    }

    private var orbCenter: CGPoint {
        CGPoint(
            x: leadingContentInset + horizontalPadding + frontier.caretTrailingX + Self.orbGap + Self.orbDiameter * 0.5,
            y: verticalPadding + frontier.caretCenterY
        )
    }

    var body: some View {
        captionContent
        .offset(y: -max(0, naturalHeight - displayHeight))
        .frame(width: width, height: displayHeight, alignment: .topLeading)
        .clipped()
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [naturalHeight > displayHeight ? .clear : .white, .white],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
                Color.white
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("dictation.overlay.transcript", default: "Live transcript"))
        .accessibilityValue(transcript)
        .onChange(of: LiveCaptionComposer.State(text: transcript, stableWordCount: stableWordCount), initial: true) { _, _ in
            updateCaption()
        }
        .onChange(of: textMaxWidth) { _, _ in
            updateCaption()
        }
    }

    private var captionContent: some View {
        ZStack(alignment: .topLeading) {
            transcriptLayer
            ZStack(alignment: .topLeading) {
                frontierGlow
                orbLayer
            }
            // Fade between lines instead of sweeping the cursor diagonally
            // through words when a line wraps. Same-line movement still glides.
            .id(frontier.caretCenterY)
            .transition(.opacity)
        }
        .frame(width: width, alignment: .topLeading)
        .frame(
            minHeight: max(naturalHeight, minHeight),
            alignment: .topLeading
        )
    }

    // MARK: - Layers

    private var transcriptLayer: some View {
        Text(Self.styledText(displayedText, stableWordCount: displayedStableWordCount, color: palette.captionText))
        .font(.system(size: fontSize, weight: .medium))
        // New speech appears immediately. Corrections crossfade briefly;
        // fading the entire paragraph on every appended word causes flicker.
        .contentTransition(textTransition)
        .multilineTextAlignment(.leading)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: textMaxWidth, alignment: .leading)
        .padding(.leading, horizontalPadding + leadingContentInset)
        .padding(.trailing, horizontalPadding + trailingContentInset)
        .padding(.vertical, verticalPadding)
    }

    static func styledText(_ text: String, stableWordCount: Int, color: Color) -> AttributedString {
        let boundary = text.split(whereSeparator: \.isWhitespace)
            .prefix(max(0, stableWordCount)).last?.endIndex ?? text.startIndex
        // Slice the original text so paragraphs and spacing survive confirmation.
        var stable = AttributedString(String(text[..<boundary]))
        stable.foregroundColor = color.opacity(0.9)
        var provisional = AttributedString(String(text[boundary...]))
        provisional.foregroundColor = color.opacity(0.72)
        return stable + provisional
    }

    private var frontierGlow: some View {
        let lineSpan = fontSize * 1.35
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        frontierColor.opacity(0.55),
                        frontierColor.opacity(0.12),
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
            .opacity(displayedText.isEmpty ? 0.35 : 0.75)
    }

    private var orbLayer: some View {
        DictationCaptionOrb(color: frontierColor, level: level)
            .position(orbCenter)
    }

    private func updateCaption() {
        let next = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = TextFrontierMeasurer.measure(text: next, fontSize: fontSize, maxWidth: textMaxWidth)
        let transition: ContentTransition = next == displayedText ? .interpolate
            : next.hasPrefix(displayedText) ? .identity : .opacity
        let motion: Animation? = reduceMotion || displayedText.isEmpty || next.isEmpty
            ? nil : .smooth(duration: 0.2)
        // Publish the text, cursor and vertical follow in the same transaction.
        // A delayed second measurement makes the cursor lag and scrolling jump.
        withAnimation(motion) {
            textTransition = transition
            displayedText = next
            displayedStableWordCount = stableWordCount
            frontier = metrics
        }
    }
}

// MARK: - Orb

struct DictationCaptionOrb: View {
    let color: Color
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let diameter: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22 + 0.18 * level))
                .frame(width: diameter + 4, height: diameter + 4)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(0.98),
                            color.opacity(0.62),
                        ],
                        center: UnitPoint(x: 0.38, y: 0.28),
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                )
        }
        .scaleEffect(1.0 + 0.08 * level)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    }
}
