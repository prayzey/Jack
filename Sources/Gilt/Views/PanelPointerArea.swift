import AppKit
import SwiftUI

/// The pointer surface behind a floating panel's content. It reports the
/// pointer entering and leaving even while Jack is not the active app, which
/// SwiftUI's `onHover` does not promise inside a non-activating panel, and a
/// press-and-drag on it moves the whole window. SwiftUI buttons drawn on top
/// still take their own clicks.
struct PanelPointerArea: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> PointerView {
        PointerView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: PointerView, context: Context) {
        view.onHoverChange = onHoverChange
    }

    final class PointerView: NSView {
        var onHoverChange: (Bool) -> Void

        init(onHoverChange: @escaping (Bool) -> Void) {
            self.onHoverChange = onHoverChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onHoverChange(true) }
        override func mouseExited(with event: NSEvent) { onHoverChange(false) }

        // The window server runs the drag, so it stays smooth and never fights SwiftUI layout.
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
