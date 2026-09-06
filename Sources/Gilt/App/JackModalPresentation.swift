import AppKit

/// Helpers to present system modals (open/save panels, alerts) ABOVE Jack's
/// elevated windows.
///
/// The Quick Note, command palette, and mode/workspace windows all sit above the
/// dock window level (`dockWindow + N`), so a default-level open/save panel or
/// alert opens BEHIND them — e.g. the vault folder picker appearing behind the
/// Quick Note. Raising the panel just above the frontmost Jack window fixes it
/// without floating it above unrelated system UI.
@MainActor
enum JackModalPresentation {
    /// Raise `panel` one level above the highest currently-visible app window.
    static func raiseAboveAppWindows(_ panel: NSWindow) {
        let topVisible = NSApp.windows
            .filter { $0 !== panel && $0.isVisible }
            .map { $0.level.rawValue }
            .max() ?? NSWindow.Level.normal.rawValue
        panel.level = NSWindow.Level(rawValue: max(topVisible + 1, NSWindow.Level.modalPanel.rawValue))
    }

    /// AppKit resets an alert or panel to the standard modal level as it opens.
    /// Raise it again after that reset so elevated Jack windows cannot cover it.
    static func raiseAboveAppWindowsWhenKey(_ panel: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                raiseAboveAppWindows(panel)
            }
        }
    }
}

extension NSSavePanel {
    /// Run modal, guaranteed in front of Jack's elevated windows. `NSOpenPanel`
    /// is an `NSSavePanel` subclass, so this covers both.
    @MainActor
    @discardableResult
    func runModalInFront() -> NSApplication.ModalResponse {
        let observer = JackModalPresentation.raiseAboveAppWindowsWhenKey(self)
        defer { NotificationCenter.default.removeObserver(observer) }
        JackModalPresentation.raiseAboveAppWindows(self)
        return runModal()
    }
}

extension NSAlert {
    /// Run modal, guaranteed in front of Jack's elevated windows.
    @MainActor
    @discardableResult
    func runModalInFront() -> NSApplication.ModalResponse {
        let panel = window
        let observer = JackModalPresentation.raiseAboveAppWindowsWhenKey(panel)
        defer { NotificationCenter.default.removeObserver(observer) }
        JackModalPresentation.raiseAboveAppWindows(panel)
        return runModal()
    }
}
