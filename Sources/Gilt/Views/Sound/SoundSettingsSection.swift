import AppKit
import SwiftUI

/// Settings for Jack's sound controls: the menu bar panel, the automatic
/// features, and the browser extension for per-tab volume.
struct SoundSettingsSection: View {
    @EnvironmentObject private var store: ClipboardStore
    @ObservedObject private var tabs = BrowserTabBridge.shared

    var body: some View {
        SettingsSection(L10n.string("ui.sound", default: "Sound")) {
            SettingsToggleRow(
                title: L10n.string("ui.sound.controls.in.menu.bar", default: "Sound controls in menu bar"),
                subtitle: L10n.string("ui.sound.controls.in.menu.bar.subtitle", default: "Change the volume of each app from the menu bar"),
                icon: "speaker.wave.2",
                isOn: $store.settings.showSoundControlsInMenuBar
            )

            if store.settings.showSoundControlsInMenuBar {
                SettingsDivider()
                SettingsToggleRow(
                    title: L10n.string("ui.sound.call.mode", default: "Lower others during calls"),
                    subtitle: L10n.string("ui.sound.call.mode.subtitle", default: "When an app starts using the mic, other apps get quieter until it stops"),
                    icon: "phone",
                    isOn: $store.settings.soundCallModeEnabled
                )
                if store.settings.soundCallModeEnabled {
                    SettingsRow(
                        title: L10n.string("ui.sound.call.mode.level", default: "Other apps during a call"),
                        icon: "speaker.wave.1"
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: $store.settings.soundCallModeLevel, in: 0...0.8)
                                .tint(SettingsTheme.gold)
                                .frame(width: 150)
                            Text("\(Int((store.settings.soundCallModeLevel * 100).rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
                SettingsDivider()
                SettingsToggleRow(
                    title: L10n.string("ui.sound.meeting.call.only", default: "Meeting notes record only the call"),
                    subtitle: L10n.string("ui.sound.meeting.call.only.subtitle", default: "Leaves out music and other apps while a call app uses the mic. Needs macOS 14.4 or later."),
                    icon: "waveform",
                    isOn: $store.settings.soundMeetingCallAudioOnly
                )
                SettingsDivider()
                SettingsToggleRow(
                    title: L10n.string("ui.sound.jack.dances", default: "Jack dances to music"),
                    subtitle: L10n.string("ui.sound.jack.dances.subtitle", default: "When Jack is on screen, he bobs along to whatever is playing"),
                    icon: "music.note",
                    isOn: $store.settings.soundJackDances
                )
                SettingsDivider()
                SettingsToggleRow(
                    title: L10n.string("ui.sound.crackle.fix.setting", default: "Show \"Fix Crackling\" in the sound panel"),
                    subtitle: L10n.string("ui.sound.crackle.fix.setting.subtitle", default: "Restarts macOS audio when the Simulator makes everything crackle. macOS asks for your password each time."),
                    icon: "waveform.path",
                    isOn: $store.settings.soundShowCrackleFix
                )
                SettingsDivider()
                browserTabsRow
            }
        }
    }

    private var browserTabsRow: some View {
        SettingsRow(
            title: L10n.string("ui.sound.browser.extension", default: "Browser tab volume"),
            subtitle: tabs.connectedBrowsers.isEmpty
                ? L10n.string("ui.sound.browser.extension.subtitle", default: "Add Jack's extension to a Chrome-based browser: open its Extensions page, turn on Developer mode, choose Load unpacked, and pick the folder this button shows.")
                : String(format: L10n.string("ui.sound.browser.extension.connected", default: "Connected to %@"),
                         ListFormatter.localizedString(byJoining: tabs.connectedBrowsers)),
            icon: "safari"
        ) {
            Button(L10n.string("ui.sound.browser.extension.show", default: "Show Extension")) {
                if let url = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .controlSize(.small)
        }
    }
}
