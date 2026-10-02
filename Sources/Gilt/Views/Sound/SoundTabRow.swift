import SwiftUI

/// One browser tab playing sound, controlled through Jack's browser extension.
struct SoundTabRow: View {
    let tab: BrowserTab
    let onVolume: (Double) -> Void
    let onToggleMute: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            favicon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tab.title.isEmpty ? tab.host : tab.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Button(action: onToggleMute) {
                        Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(SoundIconButtonStyle(isActive: tab.isMuted))
                    .accessibilityLabel(tab.isMuted ? L10n.string("ui.sound.unmute", default: "Unmute") : L10n.string("ui.sound.mute", default: "Mute"))
                }
                .frame(height: 22)
                if !tab.host.isEmpty {
                    Text(tab.host)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                }
                HStack(spacing: 8) {
                    SoundSlider(
                        value: tab.volume,
                        label: String(format: L10n.string("ui.sound.volume.of", default: "%@ volume"), tab.title),
                        onChange: onVolume
                    )
                    Text(tab.isMuted ? L10n.string("ui.sound.muted", default: "Muted") : "\(Int((tab.volume * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .opacity(tab.isMuted ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.055 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.16), value: isHovering)
    }

    private var favicon: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .frame(width: 32, height: 32)
            .overlay {
                AsyncImage(url: tab.favIconURL) { image in
                    image.resizable().interpolation(.high).frame(width: 16, height: 16)
                } placeholder: {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
    }
}
