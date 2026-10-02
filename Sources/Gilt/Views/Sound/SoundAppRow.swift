import SwiftUI

/// One app in the sound panel: icon, name, volume slider, and mute button.
struct SoundAppRow: View {
    /// Fixed so a scrolling list can show an exact number of rows.
    static let height: CGFloat = 42

    let app: SoundApp
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(app.isMuted
                         ? L10n.string("ui.sound.muted", default: "Muted")
                         : "\(Int((app.volume * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(get: { app.volume }, set: onVolumeChange),
                    in: 0...1
                )
                .controlSize(.small)
            }
            .opacity(app.isMuted ? 0.5 : 1)

            Button(action: onToggleMute) {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(app.isMuted ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.isMuted
                                ? L10n.string("ui.sound.unmute", default: "Unmute")
                                : L10n.string("ui.sound.mute", default: "Mute"))
        }
        .frame(height: Self.height)
    }
}
