import SwiftUI

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
                .padding(.top, navigationControlsStyle == .minimal ? 10 : 8)
                .padding(.leading, navigationControlsStyle == .minimal ? 8 : 4)
                .opacity(controlsOpacity)
                .allowsHitTesting(controlsOpacity > 0.05)
                .animation(.easeOut(duration: 0.18), value: controlsOpacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }
}
