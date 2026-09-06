import AppKit
import OSLog
import SwiftUI

/// Owns the standalone "Voice Compose" window — a focusable editor where the
/// user dictates into Jack itself (rather than pasting into another app) and
/// folds copied links/clips into the middle of what they're saying.
///
/// Mirrors `QuickNoteWindowManager`'s focusable-borderless-window pattern: a
/// borderless window can't become key by default, which would block keyboard
/// input into the editor, so we use a subclass that opts in and explicitly
/// make it key + first-responder on show.
///
/// While the window is open it installs `coordinator.onComposeText`, the sink
/// that routes finished `.compose` dictations into the editor at the caret.
/// Closing the window clears the sink so a stray compose session can never
/// deliver text into a window the user can't see.
@MainActor
final class DictationComposeWindowManager: NSObject, NSWindowDelegate {
    static let shared = DictationComposeWindowManager()

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "VoiceCompose")
    private let windowSize = NSSize(width: 540, height: 440)
    private let minimumSize = NSSize(width: 360, height: 280)

    private var coordinator: DictationCoordinator?
    private weak var clipboardStore: ClipboardStore?
    /// One controller for the app's lifetime, so composed text survives a
    /// close/reopen even though the editor view is rebuilt each show.
    private let controller = DictationComposeController()
    private let pasteService = DictationPasteService()

    private var window: NSWindow?
    /// The app the user was in before opening compose, captured so "Paste into
    /// the last app" can reactivate it and send the text there.
    private weak var previousApp: NSRunningApplication?

    func configure(coordinator: DictationCoordinator, clipboardStore: ClipboardStore) {
        self.coordinator = coordinator
        self.clipboardStore = clipboardStore
    }

    // MARK: - Toggle / Show / Hide

    func toggle() {
        if let window, window.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let coordinator, let clipboardStore else {
            logger.error("show() called before configure(coordinator:dictationStore:clipboardStore:)")
            return
        }

        // Remember who was frontmost so paste-into-app can return there.
        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
        }

        // Route compose-mode dictations into the editor while the window is up.
        coordinator.onComposeText = { [weak self] text in
            self?.controller.insertDictation(text)
        }

        let window = ensureWindow(coordinator: coordinator, store: clipboardStore)
        positionWindow(window)
        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusEditor(in: window)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window, window.isVisible else { return }
        // A compose session in flight would deliver into a hidden window —
        // cancel it rather than dropping the audio silently mid-transcription.
        if let coordinator, coordinator.isActive, coordinator.currentMode == .compose {
            coordinator.cancelSession()
        }
        coordinator?.onComposeText = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak window] in
                window?.orderOut(nil)
                window?.alphaValue = 1
            }
        }
    }

    // MARK: - Paste into the previous app

    /// Copy the composed text to the clipboard, return to the app the user came
    /// from, and send Cmd+V there. We don't restore the prior pasteboard — the
    /// composed text staying on the clipboard matches "I just sent this," and
    /// the clipboard monitor will capture it as a normal clip.
    private func pasteToPreviousApp(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hide()
        previousApp?.activate()
        Task { @MainActor in
            // Let the previous app come frontmost before the synthetic Cmd+V,
            // otherwise the keystroke lands on whatever is still in front.
            try? await Task.sleep(nanoseconds: 120_000_000)
            pasteService.paste(text: text, restorePasteboard: false)
        }
    }

    // MARK: - Window construction

    private func ensureWindow(coordinator: DictationCoordinator, store: ClipboardStore) -> NSWindow {
        if let window { return window }

        let root = DictationComposeView(
            controller: controller,
            coordinator: coordinator,
            onClose: { [weak self] in self?.hide() },
            onPasteToApp: { [weak self] text in self?.pasteToPreviousApp(text) }
        )
        .environmentObject(store)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        let newWindow = ComposeBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.isMovableByWindowBackground = true
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.minSize = minimumSize
        // Sit above the dock-level tray + Settings preview, same band Quick Note
        // uses, so compose stays reachable over the rest of Jack's chrome.
        newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 3)
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.delegate = self
        newWindow.contentView = host
        host.frame = NSRect(origin: .zero, size: windowSize)

        window = newWindow
        return newWindow
    }

    private func positionWindow(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func focusEditor(in window: NSWindow) {
        DispatchQueue.main.async { [weak window] in
            guard let window, let editor = Self.firstTextView(in: window.contentView) else { return }
            _ = window.makeFirstResponder(editor)
        }
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        coordinator?.onComposeText = nil
    }
}

/// Borderless windows can't become key (which blocks keyboard input) unless
/// they opt in — required so the compose editor can receive typing + dictation.
private final class ComposeBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
