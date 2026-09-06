import AppKit
import SwiftUI

enum WindowResizeEdge {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// Shared grab-zone sizing for every hand-rolled window resize border
/// (Quick Note, Workspace). Keeping one source of truth is what makes the
/// resize *feel* the same across windows.
///
/// Native macOS uses a ~3-5pt edge band and a ~20pt corner box — famously
/// hard to hit, and even harder on macOS Tahoe where the zone sits partly
/// outside the visible rounded corner. Hand-rolled handles are expected to
/// run fatter so the interior content is still fully clickable while the edge
/// is comfortable to grab.
enum WindowResizeHandleMetrics {
    /// Grab thickness for straight edges. macOS native zones are ~3–5pt and
    /// feel impossible on borderless windows; 14pt is the minimum that reads as
    /// intentional on a hand-rolled overlay.
    static let edgeThickness: CGFloat = 14
    /// Corner squares are the high-value, hard-to-hit target, so they run
    /// larger than the edges — especially on rounded-card windows where the
    /// visual corner sits inset from the frame.
    static let cornerSize: CGFloat = 28
    /// Extra hit slop outside the drawn grab rect. AppKit text views under the
    /// card edge win hit testing by default; outward slop keeps resize grabs
    /// landing even when the cursor looks like it is on the card border.
    static let edgeHitOutset: CGFloat = 8
    static let cornerHitOutset: CGFloat = 12
    /// A practically-unbounded ceiling for callers that don't impose a max.
    static let unboundedSize = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )
}

/// Pure geometry for edge/corner resizing. Extracted from the NSView so the
/// frame math (which corner stays pinned, how min/max clamp) is unit-testable
/// without spinning up an event loop.
enum WindowFrameResizeMath {
    static func resizedFrame(
        edge: WindowResizeEdge,
        initialFrame: NSRect,
        startMouse: NSPoint,
        currentMouse: NSPoint,
        minSize: CGSize,
        maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize
    ) -> NSRect {
        let deltaX = currentMouse.x - startMouse.x
        let deltaY = currentMouse.y - startMouse.y

        var frame = initialFrame

        switch edge {
        case .left:
            frame.origin.x += deltaX
            frame.size.width -= deltaX
        case .right:
            frame.size.width += deltaX
        case .top:
            frame.size.height += deltaY
        case .bottom:
            frame.origin.y += deltaY
            frame.size.height -= deltaY
        case .topLeft:
            frame.origin.x += deltaX
            frame.size.width -= deltaX
            frame.size.height += deltaY
        case .topRight:
            frame.size.width += deltaX
            frame.size.height += deltaY
        case .bottomLeft:
            frame.origin.x += deltaX
            frame.size.width -= deltaX
            frame.origin.y += deltaY
            frame.size.height -= deltaY
        case .bottomRight:
            frame.size.width += deltaX
            frame.origin.y += deltaY
            frame.size.height -= deltaY
        }

        clampWidth(&frame, edge: edge, minWidth: minSize.width, maxWidth: maxSize.width)
        clampHeight(&frame, edge: edge, minHeight: minSize.height, maxHeight: maxSize.height)

        return frame
    }

    /// Clamps width while keeping the edge the user is NOT dragging pinned in
    /// place. For a left/leading drag the right edge must not move, so the
    /// origin is adjusted to absorb the difference; for a right drag the origin
    /// stays put.
    private static func clampWidth(
        _ frame: inout NSRect,
        edge: WindowResizeEdge,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) {
        let movesLeadingEdge: Bool
        switch edge {
        case .left, .topLeft, .bottomLeft:
            movesLeadingEdge = true
        default:
            movesLeadingEdge = false
        }

        if frame.size.width < minWidth {
            let deficit = minWidth - frame.size.width
            if movesLeadingEdge { frame.origin.x -= deficit }
            frame.size.width = minWidth
        } else if frame.size.width > maxWidth {
            let excess = frame.size.width - maxWidth
            if movesLeadingEdge { frame.origin.x += excess }
            frame.size.width = maxWidth
        }
    }

    private static func clampHeight(
        _ frame: inout NSRect,
        edge: WindowResizeEdge,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) {
        // In macOS screen coordinates (origin bottom-left) the bottom-anchored
        // edges grow downward by moving the origin, so they're the ones whose
        // origin must be corrected when height clamps.
        let movesBottomEdge: Bool
        switch edge {
        case .bottom, .bottomLeft, .bottomRight:
            movesBottomEdge = true
        default:
            movesBottomEdge = false
        }

        if frame.size.height < minHeight {
            let deficit = minHeight - frame.size.height
            if movesBottomEdge { frame.origin.y -= deficit }
            frame.size.height = minHeight
        } else if frame.size.height > maxHeight {
            let excess = frame.size.height - maxHeight
            if movesBottomEdge { frame.origin.y += excess }
            frame.size.height = maxHeight
        }
    }
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleNSView {
        WindowDragHandleNSView()
    }

    func updateNSView(_ nsView: WindowDragHandleNSView, context: Context) {}
}

struct WindowFrameResizeHandle: NSViewRepresentable {
    let edge: WindowResizeEdge
    let minSize: CGSize
    var maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize
    /// Called on every drag frame with the live frame. Keep this CHEAP — it
    /// runs at display refresh rate. Do not persist state here.
    var onFrameChanged: ((NSRect) -> Void)? = nil
    /// Called once when the drag ends (mouse up). This is where callers should
    /// persist the final window size — never per frame.
    var onResizeFinished: ((NSRect) -> Void)? = nil

    func makeNSView(context: Context) -> WindowFrameResizeHandleNSView {
        let view = WindowFrameResizeHandleNSView()
        view.edge = edge
        view.minSize = minSize
        view.maxSize = maxSize
        view.onFrameChanged = onFrameChanged
        view.onResizeFinished = onResizeFinished
        return view
    }

    func updateNSView(_ nsView: WindowFrameResizeHandleNSView, context: Context) {
        nsView.edge = edge
        nsView.minSize = minSize
        nsView.maxSize = maxSize
        nsView.onFrameChanged = onFrameChanged
        nsView.onResizeFinished = onResizeFinished
    }
}

class WindowInteractionHandleNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private extension WindowResizeEdge {
    var hitTestOutset: CGFloat {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return WindowResizeHandleMetrics.cornerHitOutset
        default:
            return WindowResizeHandleMetrics.edgeHitOutset
        }
    }
}

final class WindowDragHandleNSView: WindowInteractionHandleNSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.performDrag(with: event)
    }
}

final class WindowFrameResizeHandleNSView: WindowInteractionHandleNSView {
    var edge: WindowResizeEdge = .right
    var minSize: CGSize = CGSize(width: 320, height: 220)
    var maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize
    var onFrameChanged: ((NSRect) -> Void)?
    var onResizeFinished: ((NSRect) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var initialMouseLocation: NSPoint = .zero
    private var initialFrame: NSRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let outset = edge.hitTestOutset
        let expanded = bounds.insetBy(dx: -outset, dy: -outset)
        return expanded.contains(point) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Sit above NSTextView siblings inside the hosting tree so edge grabs
        // on Quick Note / Workspace win over the editor underneath.
        layer?.zPosition = 1_000
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingRect = bounds.insetBy(
            dx: -edge.hitTestOutset,
            dy: -edge.hitTestOutset
        )
        let area = NSTrackingArea(
            rect: trackingRect,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let outset = edge.hitTestOutset
        addCursorRect(
            bounds.insetBy(dx: -outset, dy: -outset),
            cursor: cursorForEdge
        )
    }

    override func mouseEntered(with event: NSEvent) {
        cursorForEdge.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialFrame = window.frame

        // Hold the resize cursor for the whole drag. setFrame() rebuilds the
        // window's cursor rects every frame (the drag handle registers an
        // open-hand rect), which would otherwise yank the cursor back to the
        // wrong shape mid-resize — the "cursor gets stuck" feel on corners.
        // Disabling cursor rects for the duration lets our explicit cursor win.
        let dragCursor = cursorForEdge
        window.disableCursorRects()
        dragCursor.set()

        window.trackEvents(
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

            let frame = WindowFrameResizeMath.resizedFrame(
                edge: self.edge,
                initialFrame: self.initialFrame,
                startMouse: self.initialMouseLocation,
                currentMouse: NSEvent.mouseLocation,
                minSize: self.minSize,
                maxSize: self.maxSize
            )
            window.setFrame(frame, display: true)
            // Re-assert each frame so nothing repaints over the resize cursor.
            dragCursor.set()
            self.onFrameChanged?(frame)
        }

        window.enableCursorRects()

        // Persist exactly once, at drag end. Per-frame persistence here would
        // JSON-encode the entire settings struct and force a full SwiftUI
        // re-render on every frame — the stutter users feel while resizing.
        onResizeFinished?(window.frame)
    }

    private var cursorForEdge: NSCursor {
        switch edge {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return .windowResizeNorthWestSouthEast
        case .topRight, .bottomLeft:
            return .windowResizeNorthEastSouthWest
        }
    }
}

extension NSCursor {
    /// AppKit exposes no *public* diagonal resize cursor, so corner handles
    /// historically fell back to `.crosshair` — visibly wrong. These private
    /// class methods back the real window-corner cursors macOS uses itself.
    /// Every lookup is guarded by `responds(to:)` and degrades to `.crosshair`
    /// if a future OS drops them, so there's no crash risk. (Jack ships outside
    /// the Mac App Store, so private-selector review rules don't apply.)
    static var windowResizeNorthWestSouthEast: NSCursor {
        privateResizeCursor("_windowResizeNorthWestSouthEastCursor") ?? .crosshair
    }

    static var windowResizeNorthEastSouthWest: NSCursor {
        privateResizeCursor("_windowResizeNorthEastSouthWestCursor") ?? .crosshair
    }

    private static func privateResizeCursor(_ name: String) -> NSCursor? {
        let selector = NSSelectorFromString(name)
        guard NSCursor.responds(to: selector) else { return nil }
        return NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor
    }
}
