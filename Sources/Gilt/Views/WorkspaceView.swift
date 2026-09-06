import SwiftUI
import AppKit

/// Two-pane workspace layout: combined sidebar | detail.
///
/// Layout intents:
/// - **One navigation surface.** The sidebar holds the section nav (top
///   icon-strip), the search field, and the contextual folders/items list
///   for whatever section is active. The middle column from the previous
///   design was folded back into the sidebar because it duplicated content
///   the sidebar already showed.
/// - **Per-pane scrims** keep text readable over any wallpaper. The
///   wallpaper still renders behind the whole window via
///   `WorkspaceSurfaceBackground`; it just stops bleeding through where
///   text lives. Sidebar uses `.strong`, detail uses `.light`.
/// - **Resizable divider.** A single vertical drag handle between sidebar
///   and detail lets the user dial the sidebar to taste. State is held
///   here in `@State` (per-window) so resizes survive section switches.
struct WorkspaceView: View {
    @EnvironmentObject private var store: ClipboardStore

    // Sidebar width — bigger than the old slim nav because it now carries
    // folders + items too. Min/max prevent the sidebar from being collapsed
    // past usability or from squeezing the detail pane.
    @State private var sidebarWidth: CGFloat = 320

    private let sidebarMin: CGFloat = 240
    private let sidebarMax: CGFloat = 460
    private let detailMin: CGFloat = 360

    var body: some View {
        // The hosting window keeps a real (transparent) titlebar so we get
        // native edge resize and a top drag region. SwiftUI honors that
        // titlebar as a top safe-area inset, which used to push the whole
        // card ~28pt down and leave a transparent band above it where macOS
        // drew its own rounded window outline — the "overextending border"
        // artifact. Fix: the card chrome fills the entire window
        // (ignoresSafeArea) while the interactive content keeps the titlebar
        // inset, because anything placed in that band can't be clicked — the
        // titlebar drag view sits above the content view and swallows
        // mouse-downs.
        GeometryReader { proxy in
            let titlebarInset = proxy.safeAreaInsets.top
            HStack(spacing: 0) {
                // Sidebar — nav + search + contextual content. Strong scrim so
                // every label is readable over any wallpaper.
                WorkspaceSidebarView()
                    .environmentObject(store)
                    .padding(.top, titlebarInset)
                    .frame(width: sidebarWidth)
                    .workspaceScrim(.strong)

                // Single resize handle. Scrim matches the lighter neighbour
                // (detail = light) so the only visible scrim step happens cleanly
                // at the 1px separator on the sidebar side.
                ColumnResizeHandle(
                    width: $sidebarWidth,
                    minWidth: sidebarMin,
                    maxWidth: sidebarMax,
                    scrim: .light
                )

                // Detail pane — tabs + open content. Light scrim so the
                // wallpaper is most visible here, where there's the most
                // negative space and the largest type that can carry its own
                // contrast.
                VStack(spacing: 0) {
                    WorkspaceTabStripView()
                        .environmentObject(store)
                    WorkspaceDetailView()
                        .environmentObject(store)
                }
                .padding(.top, titlebarInset)
                .frame(minWidth: detailMin, maxWidth: .infinity, maxHeight: .infinity)
                .workspaceScrim(.light)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                WorkspaceSurfaceBackground(
                    appearance: store.settings.workspaceAppearance,
                    cornerRadius: 24
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay {
                WorkspaceResizeOverlayView()
                    .environmentObject(store)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.45), radius: 28, y: 18)
            .ignoresSafeArea()
        }
        .onAppear { store.ensureDefaultWorkspaceTab() }
        .onKeyPress(.escape) {
            AppWindowManager.shared.toggleWindow(source: "workspace-escape")
            return .handled
        }
        // Drop a voice note / audio file anywhere on the workspace to transcribe
        // it. Filtering + progress + the result clip are all handled by the
        // coordinator.
        .audioFileDropTarget(source: .workspaceDrop)
    }
}

// MARK: - Column resize handle

/// Thin vertical drag handle between two workspace columns.
///
/// Uses SwiftUI's `DragGesture` (safe here — we're updating @State, not the
/// window frame, so we don't trigger the coordinate-feedback loop documented
/// in `AppKitResizeHandle`). The visible affordance is 1px; the hit target
/// is 8px so the handle is actually grabbable. Hover changes the cursor to
/// the system resize-left-right shape so the affordance is discoverable.
///
/// Critical detail: the 8px hit area MUST be filled with a scrim, not left
/// transparent. Earlier versions used `Color.clear` and the wallpaper bled
/// through as a vertical strip — the workspace looked like floating
/// islands instead of one continuous surface. The `scrim` parameter lets the
/// caller match the handle to its neighbour panes so the join reads as a
/// hairline divider over one unified room.
private struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// Scrim level used to fill the handle's 8px hit area. Match this to the
    /// lighter neighbour so there's no visible scrim step on that side.
    let scrim: WorkspaceScrimLevel

    /// Captures the width when the drag begins so subsequent deltas are
    /// applied to a stable baseline. Without this the handle drifts because
    /// `value.translation` is from drag-start, not last-frame.
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            // Continues the pane scrim across the handle's footprint. Without
            // this the wallpaper shows as a visible vertical strip between
            // panes — see header doc.
            .workspaceScrim(scrim)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.resizeLeftRight.set()
                case .ended:  NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startWidth == nil { startWidth = width }
                        let proposed = (startWidth ?? width) + value.translation.width
                        width = min(maxWidth, max(minWidth, proposed))
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}
