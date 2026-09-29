import SwiftUI

/// Shared layout for the previous/next arrows and the AppKit resize chrome.
///
/// The resize overlay sits *above* the SwiftUI hosting view, so extra SwiftUI
/// padding alone cannot save the left arrow — the top-left stretch zone still
/// eats the click. These numbers keep a thin grab strip on the card border and
/// a click-through pocket over the arrows. Change them in one place.
enum QuickNoteNavigationHitMetrics {
    static let headerHorizontalPadding: CGFloat = 14
    static let headerTopPadding: CGFloat = 10
    /// Extra inset on the overlay, on top of the header padding. Standard
    /// style used to use 4pt here, which parked the previous-note arrow
    /// inside the 36pt top-left stretch corner.
    static let overlayLeadingPadding: CGFloat = 16
    static let overlayTopPadding: CGFloat = 8

    static var cardLeadingInset: CGFloat {
        headerHorizontalPadding + overlayLeadingPadding
    }

    static var cardTopInset: CGFloat {
        headerTopPadding + overlayTopPadding
    }

    /// Hit box for the previous/next cluster after the remaining resize
    /// strip. Sized for the larger standard pill, plus a few points of slop.
    static let clusterSize = CGSize(width: 90, height: 46)

    /// Outer card-border strip that still stretches the window around the
    /// arrows. Keep this smaller than `cardLeadingInset` so the left arrow
    /// never sits on the grab band.
    static let resizeEdgeClearance: CGFloat = 10
}

func quickNoteDragHeaderHeight(for style: QuickNoteStyle) -> CGFloat {
    switch style {
    case .cleanCanvas:
        return 46
    case .paper:
        return 54
    case .obsidian:
        return 46
    case .midnightGrid:
        return 48
    case .prismGlass:
        return 46
    case .aurora:
        return 46
    case .sunset:
        return 48
    case .terminal:
        return 46
    case .sakura:
        return 52
    case .oceanic:
        return 46
    case .parchment:
        return 54
    case .cyberpunk:
        return 46
    case .sage:
        return 48
    case .graphite:
        return 46
    case .lavender:
        return 48
    case .blueprint:
        return 48
    }
}

struct QuickNoteDragHeader: View {
    let style: QuickNoteStyle
    let navigationControlsStyle: QuickNoteNavigationControlsStyle
    let navigationState: QuickNoteNavigationState
    let onNavigate: (Int) -> Void
    /// 1.0 when the note is scrolled to the very top, 0.0 once the user has
    /// scrolled past the fade distance. Only applied to the navigation controls —
    /// the drag handle and grip stay visible so the window remains draggable.
    var controlsOpacity: Double = 1
    /// Resolved foreground colour (style default, custom override, or
    /// backdrop-aware auto pick). Used for navigation control tinting.
    var foregroundColor: Color? = nil

    var body: some View {
        let headerHeight = quickNoteDragHeaderHeight(for: style)
        ZStack(alignment: .top) {
            // Full-width drag band — the entire header is draggable, not just
            // a thin pip (which was hard to hit and overlapped resize zones).
            WindowDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)

            // Extra grab target in the top-center gap between nav arrows and
            // the trailing chrome pills. Without this, export/sync controls
            // steal most of the header width and the center feels dead.
            WindowDragHandle()
                .frame(minWidth: 140, maxWidth: .infinity)
                .frame(height: headerHeight)
                .padding(.horizontal, 96)
        }
        .overlay(alignment: .topLeading) {
            if navigationControlsStyle != .hidden {
                QuickNoteNavigationControls(
                    style: style,
                    presentation: navigationControlsStyle,
                    navigationState: navigationState,
                    onNavigate: onNavigate,
                    foregroundColor: foregroundColor
                )
                .padding(.top, QuickNoteNavigationHitMetrics.overlayTopPadding)
                .padding(.leading, QuickNoteNavigationHitMetrics.overlayLeadingPadding)
                .opacity(controlsOpacity)
                .allowsHitTesting(controlsOpacity > 0.05)
                .animation(.easeOut(duration: 0.18), value: controlsOpacity)
            }
        }
        .padding(.horizontal, QuickNoteNavigationHitMetrics.headerHorizontalPadding)
        .padding(.top, QuickNoteNavigationHitMetrics.headerTopPadding)
    }
}
