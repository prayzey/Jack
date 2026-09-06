import AppKit
import ApplicationServices
import Foundation

/// Centralized Accessibility permission handling and diagnostics.
enum AccessibilityService {
    static func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    @discardableResult
    static func requestPrompt() -> Bool {
        // String literal avoids Swift 6 strict-concurrency warnings on the global C var.
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static var executablePath: String {
        Bundle.main.executableURL?.path ?? (CommandLine.arguments.first ?? "Unknown executable")
    }

    static var bundleIdentifierText: String {
        Bundle.main.bundleIdentifier ?? "Not bundled (development executable)"
    }
}
