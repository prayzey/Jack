import AppKit
import SwiftUI

/// Shared sizing for the floating dictation caption.
///
/// The **NSPanel** stays at max height for the whole session (bottom edge pinned
/// once). Only the caption **card** inside changes height, bottom-aligned, so new
/// lines extend upward — the shell never translates on screen.
enum DictationCaptionLayout {
    static let shadowMargin: CGFloat = 24
    static let captionWidth: CGFloat = 360
    static let minimumCaptionWidth: CGFloat = 320
    static let maximumCaptionWidth: CGFloat = 900
    static let maxHeight: CGFloat = 196

    /// One inset for the text and the control row, so their left and right
    /// edges line up on the same vertical.
    static let inset: CGFloat = 12
    static let fontSize: CGFloat = 13
    static let horizontalPadding: CGFloat = inset
    static let verticalPadding: CGFloat = 11
    static let controlSize: CGFloat = 26
    static let controlBarHeight: CGFloat = controlSize + inset
    static let cornerRadius: CGFloat = 22
    static let modeGlyphReserve: CGFloat = 20

    /// The text area hugs one line while listening and grows up to three
    /// before older lines scroll away under the top fade.
    /// Same line height the caret measurer lays text out with, so three lines fit exactly.
    static let lineHeight: CGFloat = NSLayoutManager().defaultLineHeight(
        for: NSFont.systemFont(ofSize: fontSize, weight: .medium)
    )
    static var textAreaMinHeight: CGFloat { lineHeight + verticalPadding * 2 }
    static var textAreaMaxHeight: CGFloat { lineHeight * 3 + verticalPadding * 2 }
    static var minimumCardHeight: CGFloat { textAreaMinHeight + controlBarHeight }

    /// Fixed panel slot for one dictation session — caption card grows inside this.
    static var sessionPanelSize: NSSize {
        let margin = shadowMargin * 2
        return NSSize(
            width: captionWidth + margin,
            height: maxHeight + margin
        )
    }

    static func clampedCaptionWidth(_ requested: Double, availableWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        let width = requested.isFinite ? CGFloat(requested) : captionWidth
        let ceiling = max(minimumCaptionWidth, min(maximumCaptionWidth, availableWidth - shadowMargin * 2))
        return min(max(width, minimumCaptionWidth), ceiling)
    }

    static func modeGlyphReserve(for mode: DictationMode) -> CGFloat {
        switch mode {
        case .askScreen, .actions: return modeGlyphReserve
        default: return 0
        }
    }
}
