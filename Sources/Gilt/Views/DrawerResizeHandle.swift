import AppKit
import SwiftUI

/// An AppKit-based horizontal resize handle for the side drawer.
/// INVARIANT: Do not replace with SwiftUI DragGesture. DragGesture tracks in
/// view-relative coordinates; calling window.setFrame() mid-drag shifts the
/// coordinate origin, creating a feedback loop that causes jitter/shake.
/// Screen-coordinate tracking via window.trackEvents() is immune to frame changes.
struct DrawerResizeHandle: NSViewRepresentable {
    let side: DrawerSide

    func makeNSView(context: Context) -> DrawerResizeHandleNSView {
        let view = DrawerResizeHandleNSView()
        view.side = side
        return view
    }

    func updateNSView(_ nsView: DrawerResizeHandleNSView, context: Context) {
        nsView.side = side
    }
}

final class DrawerResizeHandleNSView: NSView {
    var side: DrawerSide = .right
    private var initialMouseX: CGFloat = 0
    private var initialWidth: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseX = NSEvent.mouseLocation.x
        initialWidth = AppWindowManager.shared.drawerWidth

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .default
        ) { [weak self] event, stop in
            guard let self, let event else {
                stop.pointee = true
                return
            }

            if event.type == .leftMouseUp {
                stop.pointee = true
                return
            }

            let currentX = NSEvent.mouseLocation.x
            let delta: CGFloat
            switch self.side {
            case .left:
                // Handle on the right edge of a left-side drawer.
                delta = currentX - self.initialMouseX
            case .right:
                // Handle on the left edge of a right-side drawer.
                delta = self.initialMouseX - currentX
            }
            let newWidth = self.initialWidth + delta
            AppWindowManager.shared.setDrawerWidth(newWidth)
        }
    }
}
