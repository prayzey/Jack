import Foundation

enum SettingsNavigation {
    static let windowID = "gilt-settings"
    static let requestTabNotification = Notification.Name("Jack.requestSettingsTab")
    /// Posted to ask the main window (which owns `@Environment(\.openWindow)`) to
    /// open the Settings window. AppKit contexts like the command palette can't
    /// call `openWindow` directly, so they post this and ContentView opens it.
    static let openSettingsNotification = Notification.Name("Jack.openSettingsWindow")
    private static let requestedTabDefaultsKey = "Gilt.requestedSettingsTab"
    static let foldersTabRawValue = SettingsTab.folders.rawValue

    static func requestTab(rawValue: String) {
        let defaults = UserDefaults.standard
        defaults.set(rawValue, forKey: requestedTabDefaultsKey)
        NotificationCenter.default.post(name: requestTabNotification, object: rawValue)
    }

    /// Request the Settings window to open (optionally on a specific tab) from any
    /// context, including AppKit code that lacks SwiftUI's `openWindow` action.
    static func openSettings(tabRawValue: String? = nil) {
        if let tabRawValue {
            requestTab(rawValue: tabRawValue)
        }
        NotificationCenter.default.post(name: openSettingsNotification, object: nil)
    }

    static func consumeRequestedTabRawValue() -> String? {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.string(forKey: requestedTabDefaultsKey) else { return nil }
        defaults.removeObject(forKey: requestedTabDefaultsKey)
        return rawValue
    }
}
