import AppKit
import SwiftUI

/// Shared sizing for the floating dictation caption.
///
/// The **NSPanel** stays at max height for the whole session (bottom edge pinned
/// once). Only the caption **card** inside grows taller, bottom-aligned, so new
/// lines extend upward — the shell never translates on screen.
enum DictationCaptionLayout {
    static let shadowMargin: CGFloat = 24
    static let captionWidth: CGFloat = 360
    static let maxHeight: CGFloat = 196

    /// Fixed-shape session card (Handy-style): the box never grows — text
    /// scrolls up inside `textAreaHeight` and the control bar sits below.
    static let textAreaHeight: CGFloat = 76
    static let controlBarHeight: CGFloat = 34
    static var cardHeight: CGFloat { textAreaHeight + controlBarHeight }
    static let fontSize: CGFloat = 13
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let modeGlyphInset: CGFloat = 8
    static let modeGlyphReserve: CGFloat = 20

    /// Fixed panel slot for one dictation session — caption card grows inside this.
    static var sessionPanelSize: NSSize {
        let margin = shadowMargin * 2
        return NSSize(
            width: captionWidth + margin,
            height: maxHeight + margin
        )
    }

    static func modeGlyphReserve(for mode: DictationMode) -> CGFloat {
        switch mode {
        case .askScreen, .actions: return modeGlyphReserve
        default: return 0
        }
    }
}