import AppKit
import SwiftUI

/// Presents the universal command palette as a standalone borderless key window,
/// centered-ish near the top of the screen like Spotlight/Raycast. Follows the
/// same standalone-window pattern as QuickNote (never a SwiftUI sheet, which the
/// tray window can't host) and owns the keyboard navigation monitor.
@MainActor
final class CommandPaletteWindowManager: NSObject, NSWindowDelegate {
    static let shared = CommandPaletteWindowManager()

    let model = CommandPaletteModel()

    private weak var store: ClipboardStore?
    private var window: NSWindow?
    private var keyMonitor: Any?

    private let windowSize = NSSize(width: 640, height: 460)

    private override init() { super.init() }

    func configure(store: ClipboardStore) {
        self.store = store
        model.configure(store: store) { [weak self] in
            self?.hide()
        }
    }

    func toggle() {
        if let window, window.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let store else { return }

        // Capture the app the user was in so paste/dictation can restore focus.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            model.capturedPreviousApp = frontmost
        } else {
            model.capturedPreviousApp = nil
        }

        model.reset()
        Analytics.commandPaletteOpened()

        let window = self.window ?? makeWindow(store: store)
        self.window = window
        positionWindow(window)

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        removeKeyMonitor()
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
    }

    // MARK: - Window

    private func makeWindow(store: ClipboardStore) -> NSWindow {
        let host = NSHostingView(
            rootView: CommandPaletteView(model: model).environmentObject(store)
        )
        host.autoresizingMask = [.width, .height]

        let window = CommandPaletteBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        // Above the dock-level tray/grid windows and the Settings preview so the
        // palette is always reachable.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 4)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.contentView = host
        window.delegate = self
        window.title = "Command Palette"
        return window
    }

    private func positionWindow(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let x = visible.midX - windowSize.width / 2
        // Sit in the upper third — the conventional launcher position.
        let y = visible.maxY - visible.height * 0.20 - windowSize.height
        window.setFrame(
            NSRect(x: x, y: max(visible.minY, y), width: windowSize.width, height: windowSize.height),
            display: true
        )
    }

    /// Dismiss when the user clicks away or switches apps — standard launcher feel.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Keyboard navigation

    // A local key monitor owns up/down/return/escape so the focused search field
    // still receives normal typing. Returning nil consumes the event; returning
    // the event lets it flow through to the text field.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            switch event.keyCode {
            case 53: // escape
                self.hide()
                return nil
            case 125: // down arrow
                self.model.moveDown()
                return nil
            case 126: // up arrow
                self.model.moveUp()
                return nil
            case 36, 76: // return / keypad enter
                self.model.activateSelection()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

/// Borderless windows can't become key by default, which would block typing in
/// the search field. Override to allow it.
private final class CommandPaletteBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
