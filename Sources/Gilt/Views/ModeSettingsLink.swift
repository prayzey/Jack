import AppKit
import SwiftUI

/// Settings launcher for standalone mode windows (drawer/grid/radial).
/// Uses the app-owned Settings window and coordinates
/// window levels so Settings stays interactable without losing live preview.
struct ModeSettingsLink: View {
    @Environment(\.openWindow) private var openWindow

    let source: String
    var iconSize: CGFloat = 12
    var frameSize: CGFloat = 24
    var foregroundColor: Color = .white.opacity(0.5)
    var backgroundColor: Color? = nil

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            AppWindowManager.shared.prepareForSettingsPresentation(source: source)
            openWindow(id: SettingsNavigation.windowID)
        } label: {
            settingsGlyph
        }
        .buttonStyle(.plain)
        .help("Settings")
    }

    private var settingsGlyph: some View {
        Image(systemName: "gearshape")
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(width: frameSize, height: frameSize)
            .background {
                if let backgroundColor {
                    Circle().fill(backgroundColor)
                }
            }
    }
}
