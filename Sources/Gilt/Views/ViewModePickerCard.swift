import SwiftUI

/// Reusable card for selecting a ViewMode — used in both Settings and Onboarding.
struct ViewModePickerCard: View {
    let mode: ViewMode
    let isSelected: Bool
    var compact: Bool = false
    let action: () -> Void

    private var primaryAccent: Color {
        SettingsTheme.primaryAccent
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 8 : 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: compact ? 10 : 14)
                        .fill(isSelected ? primaryAccent.opacity(0.12) : Color.white.opacity(0.04))
                        .frame(width: compact ? 52 : 72, height: compact ? 44 : 56)

                    Image(systemName: mode.icon)
                        .font(.system(size: compact ? 18 : 22, weight: .medium))
                        .foregroundStyle(isSelected ? primaryAccent : .white.opacity(0.5))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 10 : 14)
                        .strokeBorder(
                            isSelected ? primaryAccent : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )

                VStack(spacing: 2) {
                    Text(mode.label)
                        .font(.system(size: compact ? 11 : 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.7))

                    if !compact {
                        Text(mode.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 100)
                    }
                }
            }
            .padding(.vertical, compact ? 8 : 12)
            .padding(.horizontal, compact ? 10 : 14)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 16)
                    .fill(isSelected ? Color.white.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
