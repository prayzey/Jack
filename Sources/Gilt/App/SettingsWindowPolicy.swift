import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum SettingsWindowPolicy {
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 420
    static let defaultWidth: CGFloat = 860
    static let defaultHeight: CGFloat = 640
    static let maximumWidth: CGFloat = 1800
    static let maximumHeight: CGFloat = 1400
    static let leadingTrafficLightClearanceTop: CGFloat = 38
    static let requiredCollectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary
    ]
    static let windowBackgroundColor = NSColor(
        srgbRed: 0.98,
        green: 0.98,
        blue: 0.97,
        alpha: 1
    )

    static var minimumContentSize: NSSize {
        NSSize(width: minimumWidth, height: minimumHeight)
    }

    static var defaultContentSize: NSSize {
        NSSize(width: defaultWidth, height: defaultHeight)
    }

    static var maximumContentSize: NSSize {
        NSSize(width: maximumWidth, height: maximumHeight)
    }

    @MainActor
    static func frameMinimumSize(for window: NSWindow) -> NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
    }

    @MainActor
    static func apply(to window: NSWindow) {
        let minimumSize = minimumContentSize

        // A borderless Settings window looks custom, but it prevents the normal
        // macOS edge/corner resize affordance from behaving like System Settings.
        if window.styleMask.contains(.borderless) {
            window.styleMask.remove(.borderless)
        }

        // Ensure .titled is present - required for edge resize cursors to appear
        if window.styleMask.contains(.titled) == false {
            window.styleMask.insert(.titled)
        }

        if window.styleMask.contains(.closable) == false {
            window.styleMask.insert(.closable)
        }

        if window.styleMask.contains(.miniaturizable) == false {
            window.styleMask.insert(.miniaturizable)
        }

        // Keep the standard traffic lights while letting content occupy the
        // title-bar region so Settings does not show a separate blank header.
        if window.styleMask.contains(.fullSizeContentView) == false {
            window.styleMask.insert(.fullSizeContentView)
        }

        // Ensure .resizable is present for edge dragging
        if window.styleMask.contains(.resizable) == false {
            window.styleMask.insert(.resizable)
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.backgroundColor = windowBackgroundColor
        // Settings should follow the active macOS Space when reopened instead of
        // remaining stranded in the last desktop where it was shown.
        window.collectionBehavior.formUnion(requiredCollectionBehavior)
        // Enable the resize indicator (the visual affordance)
        window.showsResizeIndicator = true

        window.contentMinSize = minimumSize
        window.minSize = frameMinimumSize(for: window)
        // Match Workspace's generous ceiling with concrete dimensions. Real
        // bounds behave more predictably in SwiftUI Settings scenes than
        // greatestFiniteMagnitude, which can be treated like a small clamp.
        window.contentMaxSize = maximumContentSize
        window.maxSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: maximumContentSize)).size
    }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyPolicy(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyPolicy(from: nsView)
    }

    private func applyPolicy(from view: NSView) {
        for delay in [0.0, 0.1, 0.35, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                guard let window = view?.window else { return }
                SettingsWindowPolicy.apply(to: window)
            }
        }
    }
}
