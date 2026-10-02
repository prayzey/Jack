import SwiftUI

/// Menu items for picking a speaker. For an app, the first item sends it back
/// to wherever the Mac is playing (`selectedUID == nil`).
struct SoundOutputMenu: View {
    let devices: [AudioOutputDevice]
    /// The chosen device's UID; nil means "same as the Mac".
    let selectedUID: String?
    /// Set when picking for an app, to offer the follow-the-Mac option.
    var macOutputName: String?
    let onSelect: (String?) -> Void

    var body: some View {
        if let macOutputName {
            Button {
                onSelect(nil)
            } label: {
                item(String(format: L10n.string("ui.sound.output.same.as.mac", default: "Same as Mac (%@)"), macOutputName),
                     selected: selectedUID == nil)
            }
            Divider()
        }
        ForEach(devices) { device in
            Button {
                onSelect(device.uid)
            } label: {
                item(device.name, selected: device.uid == selectedUID)
            }
        }
    }

    @ViewBuilder
    private func item(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
