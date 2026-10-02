import AppKit
import SwiftUI

/// The frosted menu material behind the sound panel. Drawn inside SwiftUI
/// (not as the window's own background) so it resizes in the same animation
/// as the rows; resizing the window instead made the content shake.
struct SoundPanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
