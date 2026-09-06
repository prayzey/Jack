import SwiftUI

/// Full-screen blocking view shown when the running version is below
/// the remote `minimumVersion`. Presented as a standalone NSWindow
/// via `AppWindowManager` — never as a sheet on the tray.
struct ForceUpdateView: View {
    let latestVersion: String
    let message: String
    let updateURL: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(accentGreen)

                Text(L10n.string("ui.update.required", default: "Update Required"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                Button {
                    AppUpdater.shared.checkForUpdates()
                } label: {
                    Text("Update \(AppBrand.displayName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(accentGreen)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit \(AppBrand.displayName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 460, height: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: NSColor(white: 0.10, alpha: 1.0)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var accentGreen: Color {
        Color(red: 0.30, green: 0.78, blue: 0.55)
    }
}
