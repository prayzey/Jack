import SwiftUI

/// Overlay shown when the trial has expired and no valid license is present.
/// Used across all view modes (tray, drawer, grid, radial).
struct LicenseGateView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.openWindow) private var openWindow

    @State private var licenseKeyInput = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Lock icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 56, height: 56)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Message
                VStack(spacing: 6) {
                    Text(L10n.string("ui.trial.ended", default: "Trial Ended"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Enter a license key to keep using \(AppBrand.displayName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }

                // Inline key entry
                HStack(spacing: 8) {
                    TextField("License key", text: $licenseKeyInput)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .frame(maxWidth: 240)
                        .onSubmit {
                            activateKey()
                        }

                    Button(action: activateKey) {
                        Group {
                            if store.isLicenseBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SettingsTheme.primaryAccent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLicenseBusy)
                }

                if let error = store.licenseErrorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }

                // Actions row
                HStack(spacing: 16) {
                    Button {
                        SettingsNavigation.requestTab(rawValue: SettingsTab.license.rawValue)
                        openWindow(id: SettingsNavigation.windowID)
                    } label: {
                        Text(L10n.string("common.settings", default: "Settings"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let url = URL(string: PolarConstants.checkoutURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Buy \(AppBrand.displayName) for $10")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsTheme.primaryAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color.black.opacity(0.85)
                // Subtle gradient for depth
                LinearGradient(
                    colors: [
                        Color(white: 0.08),
                        Color(white: 0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.6)
            }
        )
    }

    private func activateKey() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task {
            await store.activateLicenseKey(key)
            if store.licenseState.isLicensed {
                licenseKeyInput = ""
            }
        }
    }
}
