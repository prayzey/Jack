import AppKit

/// Window-level resize chrome for borderless floating panels (Quick Note).
///
/// SwiftUI `NSViewRepresentable` edge strips sit *inside* `NSHostingView` and
/// lose hit-testing to `NSTextView` on the left/right — users never see resize
/// cursors and drags feel dead. The fix used across macOS utilities is one
/// transparent `NSView` pinned **above** the hosting view on the window's
/// `contentView`, with edge-band `hitTest` + `resetCursorRects` in a single
/// layer AppKit controls end-to-end.
///
/// Quick Note adds a second constraint: the visible card is inset 30–46 pt inside
/// the window frame. Resize zones must hug that card perimeter (where users aim),
/// not the outer transparent margin.
@MainActor
final class WindowEdgeResizeChromeNSView: NSView {
    struct Configuration {
        var minSize: CGSize
        var maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize
        var edgeThickness: CGFloat = 22
        var topEdgeThickness: CGFloat = 12
        var cornerSize: CGFloat = 32
        /// Inset between the window frame and the visible card. Resize bands hug
        /// this inner rect so grabs land where the rounded card edge appears.
        var contentInset: CGFloat = 0
        /// Recompute `contentInset` from `quickNoteWindowCanvasInset` on layout.
        var usesDynamicQuickNoteCanvasInset = false
        /// Click-through width at the top-center so the drag header underneath
        /// can move the window. When `usesDynamicTopDragGap` is true, the gap
        /// tracks live card width (55%, clamped 200–340pt).
        var topEdgeCenterGap: CGFloat = 0
        var usesDynamicTopDragGap = false
        var onResizeFinished: ((NSRect) -> Void)? = nil
    }

    private struct ResizeZone {
        let rect: NSRect
        let edge: WindowResizeEdge
        let outset: CGFloat
    }

    private var configuration = Configuration(minSize: CGSize(width: 320, height: 220))
    private var pressedEdge: WindowResizeEdge?
    private var initialMouseLocation: NSPoint = .zero
    private var initialFrame: NSRect = .zero
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    func apply(_ configuration: Configuration) {
        self.configuration = configuration
        window?.invalidateCursorRects(for: self)
    }

    func configure(
        minSize: CGSize,
        maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize,
        edgeThickness: CGFloat = 22,
        topEdgeThickness: CGFloat = 12,
        cornerSize: CGFloat = 32,
        contentInset: CGFloat = 0,
        usesDynamicQuickNoteCanvasInset: Bool = false,
        topEdgeCenterGap: CGFloat = 0,
        usesDynamicTopDragGap: Bool = false,
        onResizeFinished: ((NSRect) -> Void)? = nil
    ) {
        apply(
            Configuration(
                minSize: minSize,
                maxSize: maxSize,
                edgeThickness: edgeThickness,
                topEdgeThickness: topEdgeThickness,
                cornerSize: cornerSize,
                contentInset: contentInset,
                usesDynamicQuickNoteCanvasInset: usesDynamicQuickNoteCanvasInset,
                topEdgeCenterGap: topEdgeCenterGap,
                usesDynamicTopDragGap: usesDynamicTopDragGap,
                onResizeFinished: onResizeFinished
            )
        )
    }

    private var effectiveContentInset: CGFloat {
        if configuration.usesDynamicQuickNoteCanvasInset {
            return quickNoteWindowCanvasInset(for: bounds.size)
        }
        return configuration.contentInset
    }

    private var cardRect: NSRect {
        let inset = effectiveContentInset
        guard inset > 0, bounds.width > inset * 2, bounds.height > inset * 2 else {
            return bounds
        }
        return bounds.insetBy(dx: inset, dy: inset)
    }

    private var effectiveTopDragGap: CGFloat {
        if configuration.usesDynamicTopDragGap {
            return min(max(cardRect.width * 0.55, 200), 340)
        }
        return configuration.topEdgeCenterGap
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.zPosition = 10_000
        // Keep this exactly clear: even a 2% fill paints a visible gray rectangle
        // around the rounded note on white backgrounds.
        layer?.backgroundColor = NSColor.clear.cgColor
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        if let superview {
            superview.addSubview(self, positioned: .above, relativeTo: nil)
        }
        window?.invalidateCursorRects(for: self)
    }

    /// Interior is click-through; edge bands resize, and the transparent
    /// margin between the window frame and the card is a window-move zone —
    /// otherwise dead space, it gives the borderless window a fat draggable
    /// "frame" on all four sides.
    ///
    /// `hitTest` receives the point in the SUPERVIEW's (unflipped) coordinates
    /// while all zone geometry here is flipped-local — convert first, or the
    /// top/bottom bands test mirrored.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(local) else { return nil }
        if edge(at: local) != nil { return self }
        return isInMoveMargin(local) ? self : nil
    }

    /// True when `point` sits outside the visible card but inside the window
    /// frame. Empty when the card is not inset (cardRect == bounds).
    private func isInMoveMargin(_ point: NSPoint) -> Bool {
        let card = cardRect
        guard !card.equalTo(bounds) else { return false }
        return !card.contains(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        // Move-margin rects stay clear of the resize-band outsets so the
        // resize cursors keep winning right at the card edge.
        if !cardRect.equalTo(bounds) {
            let clearance = WindowResizeHandleMetrics.cornerHitOutset
            let card = cardRect.insetBy(dx: -clearance, dy: -clearance)
            let margins = [
                NSRect(x: 0, y: 0, width: bounds.width, height: card.minY),
                NSRect(x: 0, y: card.maxY, width: bounds.width, height: bounds.height - card.maxY),
                NSRect(x: 0, y: card.minY, width: card.minX, height: card.height),
                NSRect(x: card.maxX, y: card.minY, width: bounds.width - card.maxX, height: card.height)
            ]
            for rect in margins where rect.width > 0 && rect.height > 0 {
                addCursorRect(rect, cursor: .openHand)
            }
        }

        for zone in resizeZones() {
            let rect = zone.rect.insetBy(dx: -zone.outset, dy: -zone.outset)
            addCursorRect(rect, cursor: cursor(for: zone.edge))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let edge = edge(at: point) {
            cursor(for: edge).set()
        } else if isInMoveMargin(point) {
            NSCursor.openHand.set()
        }
        // Interior: leave the cursor alone — the editor owns its I-beam there.
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let edge = edge(at: point) else {
            if isInMoveMargin(point) {
                NSCursor.closedHand.set()
                window.performDrag(with: event)
                NSCursor.openHand.set()
            }
            return
        }

        pressedEdge = edge
        initialMouseLocation = NSEvent.mouseLocation
        initialFrame = window.frame

        let dragCursor = cursor(for: edge)
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

            guard let edge = self.pressedEdge else {
                stop.pointee = true
                return
            }

            let frame = WindowFrameResizeMath.resizedFrame(
                edge: edge,
                initialFrame: self.initialFrame,
                startMouse: self.initialMouseLocation,
                currentMouse: NSEvent.mouseLocation,
                minSize: self.configuration.minSize,
                maxSize: self.configuration.maxSize
            )
            window.setFrame(frame, display: true)
            dragCursor.set()
        }

        window.enableCursorRects()
        pressedEdge = nil
        configuration.onResizeFinished?(window.frame)
    }

    // MARK: - Edge geometry (flipped: origin top-left)

    private func edge(at point: NSPoint) -> WindowResizeEdge? {
        for zone in resizeZones() {
            let expanded = zone.rect.insetBy(dx: -zone.outset, dy: -zone.outset)
            guard expanded.contains(point) else { continue }
            return zone.edge
        }
        return nil
    }

    private func resizeZones() -> [ResizeZone] {
        let card = cardRect
        let width = card.width
        let height = card.height
        guard width > 0, height > 0 else { return [] }

        let side = configuration.edgeThickness
        let top = configuration.topEdgeThickness
        let corner = configuration.cornerSize
        let gap = effectiveTopDragGap

        var zones: [ResizeZone] = []

        func add(_ rect: NSRect, _ edge: WindowResizeEdge, outset: CGFloat) {
            guard rect.width > 0, rect.height > 0 else { return }
            zones.append(ResizeZone(rect: rect, edge: edge, outset: outset))
        }

        let cornerOutset = WindowResizeHandleMetrics.cornerHitOutset
        let edgeOutset = WindowResizeHandleMetrics.edgeHitOutset

        add(
            NSRect(x: card.minX, y: card.minY, width: corner, height: corner),
            .topLeft,
            outset: cornerOutset
        )
        add(
            NSRect(x: card.maxX - corner, y: card.minY, width: corner, height: corner),
            .topRight,
            outset: cornerOutset
        )
        add(
            NSRect(x: card.minX, y: card.maxY - corner, width: corner, height: corner),
            .bottomLeft,
            outset: cornerOutset
        )
        add(
            NSRect(x: card.maxX - corner, y: card.maxY - corner, width: corner, height: corner),
            .bottomRight,
            outset: cornerOutset
        )

        if gap > 0, gap < width - corner * 2 {
            let segmentWidth = (width - gap) / 2 - corner
            if segmentWidth > 0 {
                add(
                    NSRect(x: card.minX + corner, y: card.minY, width: segmentWidth, height: top),
                    .top,
                    outset: edgeOutset
                )
                add(
                    NSRect(
                        x: card.maxX - corner - segmentWidth,
                        y: card.minY,
                        width: segmentWidth,
                        height: top
                    ),
                    .top,
                    outset: edgeOutset
                )
            }
        } else {
            add(
                NSRect(x: card.minX + corner, y: card.minY, width: width - corner * 2, height: top),
                .top,
                outset: edgeOutset
            )
        }

        add(
            NSRect(
                x: card.minX + corner,
                y: card.maxY - side,
                width: width - corner * 2,
                height: side
            ),
            .bottom,
            outset: edgeOutset
        )
        add(
            NSRect(
                x: card.minX,
                y: card.minY + corner,
                width: side,
                height: height - corner * 2
            ),
            .left,
            outset: edgeOutset
        )
        add(
            NSRect(
                x: card.maxX - side,
                y: card.minY + corner,
                width: side,
                height: height - corner * 2
            ),
            .right,
            outset: edgeOutset
        )

        return zones
    }

    private func cursor(for edge: WindowResizeEdge) -> NSCursor {
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

/// Pins resize chrome above an `NSHostingView` so edge grabs beat the editor.
@MainActor
enum WindowEdgeResizeChromeInstaller {
    static func install(
        on host: NSView,
        minSize: CGSize,
        maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize,
        edgeThickness: CGFloat = 22,
        topEdgeThickness: CGFloat = 12,
        cornerSize: CGFloat = 32,
        contentInset: CGFloat = 0,
        usesDynamicQuickNoteCanvasInset: Bool = false,
        topEdgeCenterGap: CGFloat = 0,
        usesDynamicTopDragGap: Bool = false,
        onResizeFinished: ((NSRect) -> Void)? = nil
    ) {
        let chrome: WindowEdgeResizeChromeNSView
        if let existing = host.subviews.compactMap({ $0 as? WindowEdgeResizeChromeNSView }).first {
            chrome = existing
        } else {
            chrome = WindowEdgeResizeChromeNSView(frame: host.bounds)
            chrome.autoresizingMask = [.width, .height]
            host.addSubview(chrome, positioned: .above, relativeTo: nil)
        }
        chrome.frame = host.bounds
        chrome.wantsLayer = true
        chrome.layer?.zPosition = 10_000
        chrome.configure(
            minSize: minSize,
            maxSize: maxSize,
            edgeThickness: edgeThickness,
            topEdgeThickness: topEdgeThickness,
            cornerSize: cornerSize,
            contentInset: contentInset,
            usesDynamicQuickNoteCanvasInset: usesDynamicQuickNoteCanvasInset,
            topEdgeCenterGap: topEdgeCenterGap,
            usesDynamicTopDragGap: usesDynamicTopDragGap,
            onResizeFinished: onResizeFinished
        )
        host.window?.invalidateCursorRects(for: chrome)
    }

    static func remove(from host: NSView) {
        host.subviews.compactMap { $0 as? WindowEdgeResizeChromeNSView }.forEach { $0.removeFromSuperview() }
    }
}
