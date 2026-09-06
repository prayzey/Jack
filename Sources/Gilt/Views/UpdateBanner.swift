import SwiftUI

/// Subtle in-app banner shown when a newer version of Jack is available.
/// Follows the same placement pattern as `TrialNudgeBanner` — appears in
/// tray, drawer, and grid modes above the clip content area.
///
/// Dismissable per session. Reappears on next launch if still outdated.
struct UpdateBanner: View {
    @ObservedObject private var updateService = UpdateCheckService.shared

    var body: some View {
        if !updateService.softBannerDismissed,
           case .updateAvailable(let version, let message, _) = updateService.state
        {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accentGreen)

                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer()

                Button {
                    AppUpdater.shared.checkForUpdates()
                } label: {
                    Text("Update to \(version)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(accentGreen)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        updateService.softBannerDismissed = true
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

    private var accentGreen: Color {
        Color(red: 0.30, green: 0.78, blue: 0.55)
    }
}
