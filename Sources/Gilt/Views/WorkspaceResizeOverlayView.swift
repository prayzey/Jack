import AppKit
import SwiftUI

enum WorkspaceResizeOverlayMetrics {
    // Side + bottom edges use the shared (fatter) grab thickness so resizing
    // the workspace feels identical to Quick Note. 5pt — the old value — was
    // nearly impossible to land on.
    static let edgeThickness: CGFloat = WindowResizeHandleMetrics.edgeThickness
    // The TOP edge stays thin on purpose: the tab strip sits directly below it
    // and the titlebar drag region is up there, so a fat top band would turn
    // tab clicks and window drags into surprise resizes.
    static let topEdgeThickness: CGFloat = 6
    static let cornerSize: CGFloat = WindowResizeHandleMetrics.cornerSize
    static let resizeIndicatorPadding: CGFloat = 8
}

struct WorkspaceResizeOverlayView: View {
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            resizeHandles

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.24))
                .padding(.trailing, WorkspaceResizeOverlayMetrics.resizeIndicatorPadding)
                .padding(.bottom, WorkspaceResizeOverlayMetrics.resizeIndicatorPadding)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resizeHandles: some View {
        WindowFrameResizeOverlay(
            edgeThickness: WorkspaceResizeOverlayMetrics.edgeThickness,
            topEdgeThickness: WorkspaceResizeOverlayMetrics.topEdgeThickness,
            cornerSize: WorkspaceResizeOverlayMetrics.cornerSize,
            minSize: AppWindowManager.workspaceMinimumWindowSize,
            maxSize: AppWindowManager.workspaceMaximumWindowSize,
            onResizeFinished: persistWorkspaceFrame
        )
    }

    private func persistWorkspaceFrame(_ frame: NSRect) {
        let visibleFrame = workspaceVisibleFrame(for: frame)
        let clampedSize = AppWindowManager.clampedWorkspaceWindowSize(
            preferredWidth: frame.width,
            preferredHeight: frame.height,
            visibleFrame: visibleFrame
        )
        store.settings.workspaceWindowWidth = clampedSize.width
        store.settings.workspaceWindowHeight = clampedSize.height
    }

    private func workspaceVisibleFrame(for frame: NSRect) -> NSRect {
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? frame
    }
}
