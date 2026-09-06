import SwiftUI

struct QuickNoteNavigationControls: View {
    @Environment(\.locale) private var locale

    let style: QuickNoteStyle
    let presentation: QuickNoteNavigationControlsStyle
    let navigationState: QuickNoteNavigationState
    let onNavigate: (Int) -> Void
    /// When set (e.g. from wallpaper-aware text color), minimal mode uses this for icon tint.
    var foregroundColor: Color? = nil

    var body: some View {
        HStack(spacing: presentation == .minimal ? 2 : 0) {
            navigationButton(
                systemImage: "arrow.left",
                isEnabled: navigationState.canNavigateBackward,
                labelKey: "quickNote.navigation.previous.label",
                defaultLabel: "Previous note",
                step: -1
            )

            if presentation == .standard {
                Rectangle()
                    .fill(style.cardBorderColor.opacity(style.isLightSurface ? 0.7 : 1))
                    .frame(width: 1, height: 18)
            } else {
                Rectangle()
                    .fill(dividerColor)
                    .frame(width: 1, height: 14)
            }

            navigationButton(
                systemImage: "arrow.right",
                isEnabled: navigationState.canNavigateForward,
                labelKey: "quickNote.navigation.next.label",
                defaultLabel: "Next note",
                step: 1
            )
        }
        .padding(presentation == .standard ? 4 : 0)
        .background {
            if presentation == .standard {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(controlBackground)
            }
        }
        .overlay {
            if presentation == .standard {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        style.cardBorderColor.opacity(style.isLightSurface ? 0.85 : 1),
                        lineWidth: 0.9
                    )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var dividerColor: Color {
        let base = foregroundColor ?? style.textColor
        return base.opacity(style.isLightSurface ? 0.28 : 0.22)
    }

    private var controlBackground: Color {
        if style.isLightSurface {
            return Color.white.opacity(0.82)
        }
        return Color.black.opacity(style == .prismGlass ? 0.18 : 0.28)
    }

    private var enabledIconColor: Color {
        if presentation == .minimal {
            let base = foregroundColor ?? style.textColor
            return base.opacity(style.isLightSurface ? 0.88 : 0.92)
        }
        return style.insertionColor.opacity(style.isLightSurface ? 0.92 : 0.96)
    }

    private var disabledIconColor: Color {
        if presentation == .minimal {
            let base = foregroundColor ?? style.secondaryTextColor
            return base.opacity(0.38)
        }
        return style.secondaryTextColor.opacity(0.65)
    }

    private func navigationButton(
        systemImage: String,
        isEnabled: Bool,
        labelKey: String,
        defaultLabel: String,
        step: Int
    ) -> some View {
        let buttonSize: CGFloat = presentation == .minimal ? 22 : 28
        let buttonHeight: CGFloat = presentation == .minimal ? 20 : 24
        let iconSize: CGFloat = presentation == .minimal ? 10 : 11

        return Button {
            onNavigate(step)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: buttonSize, height: buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? enabledIconColor : disabledIconColor)
        .opacity(isEnabled ? 1 : 0.72)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(L10n.string(labelKey, default: defaultLabel, locale: locale)))
        .help(L10n.string(labelKey, default: defaultLabel, locale: locale))
    }
}
