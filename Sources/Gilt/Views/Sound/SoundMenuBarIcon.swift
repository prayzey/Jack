import SwiftUI

/// Speaker glyph in the menu bar; its waves follow the system volume.
struct SoundMenuBarIcon: View {
    @ObservedObject var mixer: SoundMixer

    var body: some View {
        Image(systemName: mixer.menuBarSymbol)
            .accessibilityLabel(L10n.string("ui.sound", default: "Sound"))
    }
}
