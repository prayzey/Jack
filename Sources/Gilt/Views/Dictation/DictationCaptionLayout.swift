import AppKit
import SwiftUI

/// Shared sizing for the floating dictation pill.
///
/// The **NSPanel** keeps one fixed size for the whole session (bottom edge
/// pinned once). Only the pill inside changes width, centered and
/// bottom-aligned, so the shell never moves on screen.
enum DictationCaptionLayout {
    static let shadowMargin: CGFloat = 24
    /// Default and limits for the pill's widest size. Right-click the pill to change it.
    static let captionWidth: CGFloat = 360
    static let minimumCaptionWidth: CGFloat = 320
    static let maximumCaptionWidth: CGFloat = 900
    /// Panel content height: room for the failure card. The pill itself is `pillHeight`.
    static let maxHeight: CGFloat = 150

    static let pillHeight: CGFloat = 44
    /// The dot grid: 7 dots across on a 4pt pitch, so dots land on whole points.
    static let gridSize: CGFloat = 28
    static let gridInset: CGFloat = (pillHeight - gridSize) / 2
    static let textLeading: CGFloat = gridInset + gridSize + 10
    static let textTrailing: CGFloat = 16
    static let controlSize: CGFloat = 28
    /// Trailing room while the hover buttons show: gap, two buttons, inset.
    static let controlsTrailing: CGFloat = 10 + controlSize * 2 + 4 + gridInset
    static let fontSize: CGFloat = 14
    static let cardCornerRadius: CGFloat = 22
    /// Gap between words, equal to a space in the caption font, so the line reads as normal text.
    static let wordSpacing: CGFloat = NSAttributedString(
        string: " ",
        attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]
    ).size().width

    /// Each word is drawn in a frame of exactly this width, so the line's width
    /// is known before layout and the pill can spring to it in the same frame.
    @MainActor static func wordWidth(_ word: String) -> CGFloat {
        if let width = wordWidths[word] { return width }
        if wordWidths.count > 4_000 { wordWidths.removeAll() }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let width = ceil(NSAttributedString(string: word, attributes: [.font: font]).size().width * 2) / 2
        wordWidths[word] = width
        return width
    }

    @MainActor static func lineWidth(of words: [String]) -> CGFloat {
        words.reduce(0) { $0 + wordWidth($1) } + wordSpacing * CGFloat(max(0, words.count - 1))
    }

    @MainActor private static var wordWidths: [String: CGFloat] = [:]

    enum PillContent: Equatable {
        /// Just the dot grid: a circle.
        case empty
        /// A line of words this wide.
        case text(CGFloat)
        /// The finished label ("Pasted") this wide.
        case label(CGFloat)
    }

    /// The pill hugs its content and stops at `maxWidth`; longer text scrolls inside.
    static func pillWidth(_ content: PillContent, maxWidth: CGFloat, showsControls: Bool) -> CGFloat {
        let trailing = showsControls ? controlsTrailing : textTrailing
        switch content {
        case .empty:
            return showsControls ? gridInset + gridSize + controlsTrailing : pillHeight
        case .text(let width):
            return min(maxWidth, textLeading + ceil(width) + trailing)
        case .label(let width):
            return min(maxWidth, textLeading + ceil(width) + textTrailing)
        }
    }

    /// How much of the line of words is visible inside a pill of this width.
    static func textViewport(pillWidth: CGFloat, showsControls: Bool) -> CGFloat {
        max(0, pillWidth - textLeading - (showsControls ? controlsTrailing : textTrailing))
    }

    /// Fixed panel slot for one dictation session — the pill changes size inside this.
    static var sessionPanelSize: NSSize {
        let margin = shadowMargin * 2
        return NSSize(
            width: captionWidth + margin,
            height: maxHeight + margin
        )
    }

    /// Where the panel sits on a screen: centered above the Dock, moved by the
    /// offset the user dragged it to, and held so the pill stays fully on screen.
    static func panelOrigin(in visibleFrame: CGRect, panelSize: CGSize, offset: CGPoint) -> CGPoint {
        let home = homeOrigin(in: visibleFrame, panelSize: panelSize)
        return CGPoint(
            x: min(max(home.x + offset.x, visibleFrame.minX - shadowMargin), visibleFrame.maxX - panelSize.width + shadowMargin),
            y: min(max(home.y + offset.y, visibleFrame.minY - shadowMargin), visibleFrame.maxY - shadowMargin - pillHeight)
        )
    }

    /// The offset to remember after the user drops the panel at `origin`.
    static func panelOffset(origin: CGPoint, in visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        let home = homeOrigin(in: visibleFrame, panelSize: panelSize)
        return CGPoint(x: origin.x - home.x, y: origin.y - home.y)
    }

    private static func homeOrigin(in visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        CGPoint(x: visibleFrame.midX - panelSize.width / 2, y: visibleFrame.minY + 48)
    }

    static func clampedCaptionWidth(_ requested: Double, availableWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        let width = requested.isFinite ? CGFloat(requested) : captionWidth
        let ceiling = max(minimumCaptionWidth, min(maximumCaptionWidth, availableWidth - shadowMargin * 2))
        return min(max(width, minimumCaptionWidth), ceiling)
    }
}
