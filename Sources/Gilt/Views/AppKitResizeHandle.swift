import AppKit
import SwiftUI

/// An AppKit-based resize handle that tracks mouse in screen coordinates.
/// This avoids SwiftUI's DragGesture coordinate-space feedback loop where
/// calling window.setFrame() mid-drag shifts the view origin, causing jitter.
struct AppKitResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView {
        ResizeHandleNSView()
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    private var initialMouseY: CGFloat = 0
    private var initialHeight: CGFloat = 0
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
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        // Capture start position in screen coordinates — immune to frame changes
        initialMouseY = NSEvent.mouseLocation.y
        initialHeight = AppWindowManager.shared.shelfHeight
        AppWindowManager.shared.beginInteractiveResize()

        // Enter a local event-tracking loop.
        // This gives us every mouse event at display refresh rate,
        // completely bypassing SwiftUI's gesture system.
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
                AppWindowManager.shared.endInteractiveResize()
                return
            }

            // Screen coordinates never shift when the window frame changes
            let currentY = NSEvent.mouseLocation.y
            let delta = currentY - self.initialMouseY
            let newHeight = self.initialHeight + delta
            AppWindowManager.shared.setShelfHeight(newHeight, animated: false)
        }
    }
}
