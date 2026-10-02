import SwiftUI

/// One muffle style in dictation settings: pick it, or preview it on
/// whatever is playing right now.
struct MuffleStyleRow: View {
    let style: SoundMuffle
    let isSelected: Bool
    let isPreviewing: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: style.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : SettingsTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? SettingsTheme.primaryAccent : SettingsTheme.primaryAccent.opacity(0.07))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(style.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(action: onPreview) {
                HStack(spacing: 4) {
                    Image(systemName: isPreviewing ? "waveform" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .symbolEffect(.variableColor.iterative, isActive: isPreviewing)
                    Text(isPreviewing
                         ? L10n.string("ui.muffle.previewing", default: "Playing")
                         : L10n.string("ui.muffle.preview", default: "Preview"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(SettingsTheme.textPrimary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(SettingsTheme.primaryAccent.opacity(isHovering || isPreviewing ? 0.1 : 0.06)))
            }
            .buttonStyle(.plain)
            .help(L10n.string("ui.muffle.preview.help", default: "Hear this style on whatever is playing for a few seconds"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? SettingsTheme.primaryAccent.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? SettingsTheme.primaryAccent.opacity(0.35) : SettingsTheme.border, lineWidth: isSelected ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: L10n.string("ui.muffle.preview", default: "Preview"), onPreview)
    }
}
