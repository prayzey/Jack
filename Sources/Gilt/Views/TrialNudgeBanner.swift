import SwiftUI

/// Subtle banner shown during the 24-hour trial period, reminding the user to buy.
/// Appears at the top of the clip area in tray/drawer/grid modes.
struct TrialNudgeBanner: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var dismissed = false

    var body: some View {
        if !dismissed, case .trialActive(let remaining) = store.appAccessState,
           remaining < .infinity
        {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(trialColor(remaining))

                Text(trialMessage(remaining))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    if let url = URL(string: PolarConstants.checkoutURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(L10n.string("ui.buy.for.10", default: "Buy for $10"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.85, green: 0.65, blue: 0.25))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func trialMessage(_ remaining: TimeInterval) -> String {
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 12 {
            return "Trial: \(hours)h left"
        } else if hours > 0 {
            return "Trial: \(hours)h \(minutes)m left"
        } else {
            return "Trial: \(minutes)m left"
        }
    }

    private func trialColor(_ remaining: TimeInterval) -> Color {
        let hours = remaining / 3600
        if hours > 12 {
            return Color(red: 0.85, green: 0.65, blue: 0.25) // gold
        } else if hours > 4 {
            return .orange
        } else {
            return .red
        }
    }
}
