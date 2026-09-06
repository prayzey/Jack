import AppKit
import SwiftUI

/// Owns the borderless floating panel that shows transcription progress.
///
/// A standalone panel (not a sheet or a view inside the tray) is the only thing
/// that works regardless of which view mode is active — drops can come from the
/// menu bar with no Jack window on screen at all. It never becomes key, so it
/// never steals focus from whatever the user is doing.
@MainActor
final class TranscriptionHUDWindowManager {
    static let shared = TranscriptionHUDWindowManager()

    private var panel: NSPanel?
    private weak var coordinator: AudioTranscriptionCoordinator?

    private let contentSize = NSSize(width: 340, height: 108)

    private init() {}

    func configure(coordinator: AudioTranscriptionCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            // The completion handler fires on the main thread, but isn't
            // statically main-actor isolated — assert it so we can order the
            // panel out without an isolation warning.
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
    }

    // MARK: - Panel construction

    private func makePanel() -> NSPanel {
        let coordinator = self.coordinator ?? .shared
        let hosting = NSHostingController(
            rootView: TranscriptionHUDView(coordinator: coordinator) { [weak self] in
                self?.hide()
            }
        )
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI card draws its own shadow
        panel.isMovableByWindowBackground = true
        // Above the dock-level tray and the workspace window; below system menus.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Top-center of whichever screen currently has the pointer, tucked just
    /// under the menu bar.
    private func position(_ panel: NSPanel) {
        let screen = screenUnderPointer() ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setContentSize(contentSize)
        let x = visible.midX - contentSize.width / 2
        let y = visible.maxY - contentSize.height - 8
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }
}
