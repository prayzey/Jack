import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer until SwiftUI has attached the view to a window.
        // Cancelable WorkItem debounces elsewhere stay on asyncAfter; this is a one-shot hop.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only apply on first update to avoid repeated calls
    }
}
