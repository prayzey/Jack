import AppKit
import SwiftUI

/// Panel behind the speaker icon in the menu bar: the Mac's volume and
/// output, saved scenes, every app that's making sound (with its live level),
/// browser tabs, and the automatic sound features.
struct SoundMenuView: View {
    @ObservedObject var mixer: SoundMixer
    /// Not observed here: each row's slider observes it, so 24 meter
    /// updates a second don't redraw the whole panel.
    let meters: SoundMeters
    @ObservedObject var nowPlaying: MediaNowPlaying
    @ObservedObject var tabs: BrowserTabBridge
    @Binding var callModeEnabled: Bool
    /// The panel window sizes itself from this, so it grows downward.
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @State private var showsOtherApps = false

    /// "Other apps" scrolls past this many rows so the panel stays on screen.
    private static let maxOtherAppRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if mixer.showsScenes {
                SoundScenesBar(
                    scenes: mixer.scenes,
                    currentID: mixer.currentSceneID,
                    onApply: mixer.applyScene,
                    onSave: mixer.saveScene(named:),
                    onDelete: mixer.deleteScene
                )
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }

            divider

            if mixer.needsAudioCapturePermission { permissionNote }

            sectionHeader(L10n.string("ui.sound.active", default: "Active"))
            if mixer.activeApps.isEmpty {
                Text(L10n.string("ui.sound.no.active.apps", default: "No apps are making sound"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ForEach(mixer.activeApps) { app in
                    row(for: app, compact: false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if !tabs.tabs.isEmpty { tabsSection }

            if !mixer.quietApps.isEmpty { otherAppsSection }

            divider

            footer
        }
        .padding(10)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background { panelChrome }
        // Nothing draws outside the panel's rounded edge, even mid-animation.
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .background { panelShadow }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.5)
        }
        .animation(.snappy(duration: 0.22), value: mixer.activeApps.map(\.id))
        .animation(.snappy(duration: 0.22), value: tabs.tabs.map(\.id))
        .onGeometryChange(for: CGFloat.self, of: \.size.height, action: onHeightChange)
        // The window is a fixed canvas; the panel hangs from its top and the
        // room around it is for the shadow.
        .padding(.top, SoundMenuBarController.shadowInset.top)
        .padding(.horizontal, SoundMenuBarController.shadowInset.left)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static let cornerRadius: CGFloat = 12

    /// Material and corners, drawn here rather than by the window so they
    /// resize in the same animation as the content.
    private var panelChrome: some View {
        SoundPanelBackground()
            .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Kept outside the clip so the shadow can spread past the panel's edge.
    private var panelShadow: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Text(L10n.string("ui.sound", default: "Sound"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                outputPicker
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(SoundIconButtonStyle())
                    .help(L10n.string("ui.sound.jack.settings", default: "Jack's sound settings"))
                    .accessibilityLabel(L10n.string("ui.sound.jack.settings", default: "Jack's sound settings"))
            }
            if let volume = mixer.masterVolume {
                HStack(spacing: 10) {
                    SoundSlider(
                        value: mixer.isMasterMuted ? 0 : volume,
                        style: .master,
                        symbol: mixer.menuBarSymbol,
                        label: L10n.string("ui.sound", default: "Sound"),
                        onChange: mixer.setMasterVolume
                    )
                    Text(mixer.isMasterMuted ? L10n.string("ui.sound.muted", default: "Muted") : "\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            } else {
                Text(L10n.string("ui.sound.no.volume.control", default: "Change this output's volume on the device itself."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var outputPicker: some View {
        let current = mixer.outputDevices.first { $0.uid == mixer.outputDeviceUID }
        return Menu {
            SoundOutputMenu(devices: mixer.outputDevices, selectedUID: mixer.outputDeviceUID) { uid in
                if let uid { mixer.setSystemOutput(uid) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: current?.symbolName ?? "hifispeaker")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(mixer.outputDeviceName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("ui.sound.output.help", default: "Choose where your Mac plays sound"))
    }

    // MARK: - Sections

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
    }

    private var tabsSection: some View {
        let browsers = Set(tabs.tabs.map(\.browserName))
        let title = browsers.count == 1
            ? String(format: L10n.string("ui.sound.tabs.in", default: "Tabs in %@"), browsers.first ?? "")
            : L10n.string("ui.sound.browser.tabs", default: "Browser tabs")
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title).padding(.top, 10)
            ForEach(tabs.tabs) { tab in
                SoundTabRow(
                    tab: tab,
                    onVolume: { tabs.setVolume($0, for: tab.id) },
                    onToggleMute: { tabs.setMuted(!tab.isMuted, for: tab.id) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var otherAppsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { showsOtherApps.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.string("ui.sound.other.apps", default: "Other apps"))
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(mixer.quietApps.count)")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .rotationEffect(.degrees(showsOtherApps ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            otherAppsList
                // Grow from nothing instead of inserting at full size: the
                // rows are revealed top to bottom while the footer and the
                // panel's background move down in the same animation, so
                // nothing overlaps or spills past the panel's edge.
                .frame(height: showsOtherApps ? otherAppsHeight : 0, alignment: .top)
                .clipped()
                .opacity(showsOtherApps ? 1 : 0)
                .allowsHitTesting(showsOtherApps)
                .accessibilityHidden(!showsOtherApps)
        }
    }

    /// Rows have a fixed height, so the list's height is known exactly and
    /// can animate.
    private var otherAppsHeight: CGFloat {
        CGFloat(min(mixer.quietApps.count, Self.maxOtherAppRows)) * SoundAppRow.compactHeight
    }

    @ViewBuilder
    private var otherAppsList: some View {
        let rows = VStack(spacing: 0) {
            ForEach(mixer.quietApps) { row(for: $0, compact: true) }
        }
        if mixer.quietApps.count > Self.maxOtherAppRows {
            ScrollView { rows }
                // Keeps an always-visible scroll bar off the mute buttons.
                .contentMargins(.trailing, 10, for: .scrollContent)
        } else {
            rows
        }
    }

    private func row(for app: SoundApp, compact: Bool) -> some View {
        let isMedia = MediaNowPlaying.supportedBundleIDs.contains(app.id)
        return SoundAppRow(
            app: app,
            track: nowPlaying.tracks[app.id],
            meters: compact ? nil : meters,
            compact: compact,
            isSoloed: mixer.rules.soloAppID == app.id,
            outputDevices: mixer.outputDevices,
            macOutputName: mixer.outputDeviceName,
            actions: SoundAppActions(
                setVolume: { mixer.setVolume($0, for: app.id) },
                toggleMute: { mixer.toggleMute(for: app.id) },
                toggleSolo: { mixer.toggleSolo(app.id) },
                setOutput: { mixer.setOutput($0, for: app.id) },
                reset: { mixer.resetApp(app.id) },
                playPause: isMedia ? { nowPlaying.playPause(app.id) } : nil,
                nextTrack: isMedia ? { nowPlaying.nextTrack(app.id) } : nil
            )
        )
    }

    private var permissionNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(L10n.string(
                    "ui.sound.permission.body",
                    default: "If an app's volume doesn't change while it plays, turn on System Audio Recording for Jack."
                ))
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            .font(.system(size: 11.5))

            Button(L10n.string("ui.sound.permission.open", default: "Open Privacy Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                    NSWorkspace.shared.open(url)
                }
                onDismiss()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.bottom, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 2) {
            SoundMenuItem(
                symbol: "phone.fill",
                title: L10n.string("ui.sound.call.mode", default: "Lower others during calls"),
                detail: callModeDetail,
                action: nil
            ) {
                Toggle("", isOn: $callModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            if mixer.showsCrackleFix {
                SoundMenuItem(
                    symbol: "waveform.path",
                    title: L10n.string("ui.sound.crackle.fix", default: "Fix Crackling"),
                    detail: L10n.string("ui.sound.crackle.fix.detail", default: "Restarts macOS audio. Asks for your password."),
                    action: mixer.isRestartingAudio ? nil : { mixer.restartAudioSystem() }
                ) {
                    if mixer.isRestartingAudio { ProgressView().controlSize(.mini) }
                }
            }
            SoundMenuItem(
                symbol: "slider.horizontal.3",
                title: L10n.string("ui.sound.settings", default: "Sound Settings…")
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
                onDismiss()
            }
        }
    }

    /// "Zoom is using the mic" while call mode is lowering things.
    private var callModeDetail: String? {
        guard callModeEnabled, let caller = mixer.rules.micApps.sorted(by: { $0.key < $1.key }).first?.value else { return nil }
        return String(format: L10n.string("ui.sound.call.mode.active", default: "%@ is using the mic"), caller)
    }
}
