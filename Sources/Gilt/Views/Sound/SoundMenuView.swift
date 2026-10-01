import AppKit
import SwiftUI

/// Panel behind the speaker icon in the menu bar: system volume on top, then
/// a volume slider for every app that has opened audio, playing apps first.
struct SoundMenuView: View {
    @ObservedObject var mixer: SoundMixer
    @State private var showsOtherApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masterSection

            Divider().padding(.vertical, 10)

            if mixer.needsAudioCapturePermission {
                permissionNote
            }

            sectionLabel(L10n.string("ui.sound.active", default: "Active"))
            if mixer.activeApps.isEmpty {
                Text(L10n.string("ui.sound.no.active.apps", default: "No apps are using sound"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(mixer.activeApps) { row(for: $0) }
            }

            if !mixer.quietApps.isEmpty {
                otherAppsHeader
                if showsOtherApps {
                    ForEach(mixer.quietApps) { row(for: $0) }
                }
            }

            Divider().padding(.vertical, 8)

            Button(L10n.string("ui.sound.settings", default: "Sound Settings…")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.5))
        }
        .padding(14)
        .frame(width: 320)
    }

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.string("ui.sound", default: "Sound"))
                    .font(.system(size: 13, weight: .semibold))
                Text(mixer.outputDeviceName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let volume = mixer.masterVolume {
                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let volume = mixer.masterVolume {
                HStack(spacing: 8) {
                    Button(action: mixer.toggleMasterMute) {
                        Image(systemName: mixer.isMasterMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 12))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mixer.isMasterMuted
                                        ? L10n.string("ui.sound.unmute", default: "Unmute")
                                        : L10n.string("ui.sound.mute", default: "Mute"))

                    Slider(value: Binding(get: { volume }, set: mixer.setMasterVolume), in: 0...1)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.string(
                    "ui.sound.no.volume.control",
                    default: "Change this output's volume on the device itself."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(
                "ui.sound.permission.body",
                default: "If an app's volume doesn't change while it plays, turn on System Audio Recording for Jack."
            ))
            .font(.system(size: 11.5))
            .fixedSize(horizontal: false, vertical: true)

            Button(L10n.string("ui.sound.permission.open", default: "Open Privacy Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
        .padding(.bottom, 10)
    }

    private var otherAppsHeader: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showsOtherApps.toggle() }
        } label: {
            HStack {
                sectionLabel(L10n.string("ui.sound.other.apps", default: "Other apps"))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsOtherApps ? 180 : 0))
            }
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }

    private func row(for app: SoundApp) -> some View {
        SoundAppRow(
            app: app,
            onVolumeChange: { mixer.setVolume($0, for: app.id) },
            onToggleMute: { mixer.toggleMute(for: app.id) }
        )
    }
}
