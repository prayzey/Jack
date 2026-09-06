import AppKit
import SwiftUI

enum RadialScrollAction {
    case resize(deltaY: CGFloat)
    case page(deltaX: CGFloat)
}

/// Determines whether a scroll event should be consumed for radial resize.
/// We only consume vertical-intent scrolls within the circular radial canvas.
func radialScrollAction(
    deltaX: CGFloat,
    deltaY: CGFloat,
    locationInView: CGPoint,
    bounds: CGRect
) -> RadialScrollAction? {
    guard bounds.contains(locationInView) else { return nil }

    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let radius = min(bounds.width, bounds.height) * 0.5
    let dx = locationInView.x - center.x
    let dy = locationInView.y - center.y
    let distance = sqrt((dx * dx) + (dy * dy))
    guard distance <= radius else { return nil }

    if abs(deltaY) > abs(deltaX), abs(deltaY) > 0.5 {
        return .resize(deltaY: deltaY)
    }

    if abs(deltaX) > abs(deltaY), abs(deltaX) > 0.5 {
        return .page(deltaX: deltaX)
    }

    return nil
}

/// Transparent overlay that captures scroll-wheel events to resize the radial menu.
/// Mouse clicks and drags pass through to the SwiftUI content underneath.
struct RadialScrollResizeOverlay: NSViewRepresentable {
    var onPageScroll: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> ScrollCaptureView {
        let view = ScrollCaptureView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.onPageScroll = onPageScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
        nsView.onPageScroll = onPageScroll
    }

    final class ScrollCaptureView: NSView {
        private var scrollMonitor: Any?
        var onPageScroll: (CGFloat) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installScrollMonitor()
            } else {
                removeScrollMonitor()
            }
        }

        override func removeFromSuperview() {
            removeScrollMonitor()
            super.removeFromSuperview()
        }

        private func installScrollMonitor() {
            removeScrollMonitor()
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, window.isVisible else { return event }
                guard event.window?.windowNumber == window.windowNumber else { return event }
                let windowPoint = event.locationInWindow
                let pointInView = self.convert(windowPoint, from: nil)
                let deltaX = event.scrollingDeltaX
                let deltaY = event.scrollingDeltaY
                guard let action = radialScrollAction(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    locationInView: pointInView,
                    bounds: self.bounds
                ) else { return event }

                switch action {
                case .resize(let dy):
                    let current = AppWindowManager.shared.radialSize
                    let step: CGFloat = event.hasPreciseScrollingDeltas ? dy * 0.8 : dy * 4
                    AppWindowManager.shared.setRadialSize(current + step)
                case .page(let deltaX):
                    self.onPageScroll(deltaX)
                }
                return nil // Consume the event
            }
        }

        private func removeScrollMonitor() {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
    }
}
