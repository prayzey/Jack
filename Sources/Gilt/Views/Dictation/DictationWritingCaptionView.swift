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
/// size is fixed; only the orb slides as `transcript` grows.
struct DictationWritingCaptionView: View {
    let transcript: String
    /// Leading words rendered sharp; the tail stays blurred until confirmed.
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

    @State private var frontier = TextFrontierMetrics()
    @State private var scrollToken = UUID()
    @State private var frontierMeasureTask: Task<Void, Never>?

    private var trimmed: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var textMaxWidth: CGFloat {
        max(1, width - horizontalPadding * 2 - leadingContentInset - trailingContentInset)
    }

    private var naturalHeight: CGFloat {
        frontier.contentHeight + verticalPadding * 2
    }

    private var displayHeight: CGFloat {
        min(max(naturalHeight, minHeight), maxHeight)
    }

    private var isHeightCapped: Bool {
        naturalHeight > maxHeight + 0.5
    }

    private var orbCenter: CGPoint {
        CGPoint(
            x: leadingContentInset + horizontalPadding + frontier.caretTrailingX + Self.orbGap + Self.orbDiameter * 0.5,
            y: verticalPadding + frontier.caretCenterY
        )
    }

    var body: some View {
        Group {
            if isHeightCapped {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        captionContent
                            .id("writing-caption-anchor")
                    }
                    .onChange(of: transcript) { _, _ in
                        refreshFrontier()
                        scrollToken = UUID()
                    }
                    .onChange(of: scrollToken) { _, _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo("writing-caption-anchor", anchor: .bottom)
                        }
                    }
                }
            } else {
                captionContent
                    .onChange(of: transcript) { _, _ in
                        refreshFrontier()
                    }
            }
        }
        .frame(width: width, height: displayHeight, alignment: .topLeading)
        .clipped()
        .onChange(of: stableWordCount) { _, _ in
            refreshFrontier()
        }
        .onAppear {
            refreshFrontier()
        }
    }

    private var captionContent: some View {
        ZStack(alignment: .topLeading) {
            transcriptLayer
            frontierGlow
            orbLayer
        }
        .frame(width: width, alignment: .topLeading)
        .frame(
            minHeight: max(naturalHeight, minHeight),
            alignment: .topLeading
        )
    }

    // MARK: - Layers

    private var transcriptParts: (stable: String, provisional: String) {
        LiveCaptionComposer.splitStableProvisional(trimmed, stableWordCount: stableWordCount)
    }

    @ViewBuilder
    private var transcriptLayer: some View {
        let parts = transcriptParts
        let captionFont = Font.system(size: fontSize, weight: .medium)

        stableProvisionalText(parts: parts, font: captionFont)
        .multilineTextAlignment(.leading)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: textMaxWidth, alignment: .leading)
        .padding(.leading, horizontalPadding + leadingContentInset)
        .padding(.trailing, horizontalPadding + trailingContentInset)
        .padding(.vertical, verticalPadding)
    }

    @ViewBuilder
    private func stableProvisionalText(parts: (stable: String, provisional: String), font: Font) -> some View {
        if trimmed.isEmpty {
            Text(" ")
                .font(font)
        } else if parts.provisional.isEmpty {
            Text(parts.stable)
                .font(font)
                .foregroundStyle(palette.captionText.opacity(0.9))
        } else if parts.stable.isEmpty {
            Text(parts.provisional)
                .font(font)
                .foregroundStyle(palette.captionText.opacity(0.42))
        } else {
            (Text(parts.stable)
                .foregroundStyle(palette.captionText.opacity(0.9))
                + Text(" " + parts.provisional)
                .foregroundStyle(palette.captionText.opacity(0.42)))
                .font(font)
        }
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
            .opacity(trimmed.isEmpty ? 0.35 : 0.75)
    }

    private var orbLayer: some View {
        DictationCaptionOrb(color: frontierColor, level: level)
            .position(orbCenter)
    }

    private func refreshFrontier() {
        frontierMeasureTask?.cancel()
        let sample = trimmed
        let width = textMaxWidth
        let size = fontSize
        frontierMeasureTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            frontier = TextFrontierMeasurer.measure(
                text: sample,
                fontSize: size,
                maxWidth: width
            )
            scrollToken = UUID()
        }
    }
}

// MARK: - Orb

struct DictationCaptionOrb: View {
    let color: Color
    let level: Double

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
    }
}