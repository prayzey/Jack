import Combine
import SwiftUI

/// Settings section for picking the mic and tuning input gain. Used in both
/// the Dictation settings panel and the Meetings settings sheet, so it takes
/// bindings rather than reaching into either store directly.
///
/// Behavior follows what we researched in CoreAudio land:
///   - Picker lists real input devices only (virtual loopback drivers like
///     "Microsoft Teams Audio" and BlackHole are filtered out by the
///     `AudioInputDeviceManager`).
///   - The "Default" row shows the live system-default device name as a
///     subtitle, so users see what their "follow the system" choice actually
///     resolves to right now.
///   - Slider range and label flip based on whether the bound device exposes
///     settable hardware volume:
///       - settable → `0...1`, label "System gain"
///       - not settable → `1...2`, label "Software boost"
///     Detection happens against the user's chosen UID (or the system default
///     if they picked "Default") and refreshes whenever the device list does.
struct MicrophoneSettingsSection: View {
    /// Two-way binding to the persisted device UID. `nil` = follow system
    /// default. Stored on `DictationSettings.preferredMicDeviceUID` /
    /// `MeetingSettings.preferredMicDeviceUID`.
    @Binding var selectedDeviceUID: String?
    /// Two-way binding to the persisted gain. `1.0` is neutral in both modes.
    /// See `DictationSettings.inputGain` for full semantics.
    @Binding var inputGain: Float

    @StateObject private var devices = AudioInputDeviceManagerObserver()

    var body: some View {
        SettingsSection(L10n.string("settings.advanced.microphone.title", default: "Microphone")) {
            VStack(alignment: .leading, spacing: 0) {
                microphonePickerRow
                SettingsDivider()
                inputGainRow
            }
        }
    }

    // MARK: - Device picker

    private var microphonePickerRow: some View {
        SettingsRow(
            title: "Input device",
            subtitle: pickerSubtitle,
            icon: "mic.fill"
        ) {
            HStack(spacing: 6) {
                Menu {
                    // "Default" sentinel — selecting this clears the saved UID,
                    // so we follow whatever macOS currently treats as the
                    // default input.
                    Button {
                        selectedDeviceUID = nil
                    } label: {
                        HStack {
                            Text(defaultMenuLabel)
                            Spacer()
                            if selectedDeviceUID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    if !devices.availableDevices.isEmpty {
                        Divider()
                    }

                    ForEach(devices.availableDevices) { device in
                        Button {
                            selectedDeviceUID = device.uid
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                if selectedDeviceUID == device.uid {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentDeviceLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(SettingsTheme.textSecondary)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SettingsTheme.sidebarBackground)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                // Manual refresh — the manager already listens for CoreAudio
                // device-change notifications, but USB enumeration can have a
                // short delay after plug-in. Giving users an explicit nudge
                // matches what Handy does.
                Button {
                    devices.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(SettingsTheme.sidebarBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Refresh device list")
            }
        }
    }

    private var pickerSubtitle: String {
        if selectedDeviceUID != nil, devices.device(forUID: selectedDeviceUID) == nil {
            return "This mic isn't connected. Using the system default instead."
        }
        return "Used for dictation and meetings."
    }

    private var currentDeviceLabel: String {
        if let uid = selectedDeviceUID, let device = devices.device(forUID: uid) {
            return device.name
        }
        if selectedDeviceUID != nil {
            return "Default"
        }
        return "Default"
    }

    private var defaultMenuLabel: String {
        if let systemDefault = devices.systemDefaultDeviceName {
            return "Default (\(systemDefault))"
        }
        return "Default"
    }

    // MARK: - Input gain

    private var inputGainRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("common.inputVolume", default: "Input volume"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Spacer()
                Text(gainPercentLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }

            // The slider always runs 0...maxGain so the thumb position is
            // intuitive, but `maxGain` differs by mode: 1.0 in hardware mode
            // (matches System Settings semantics), 2.0 in software mode
            // (matches the "boost" framing the user expects).
            Slider(
                value: Binding(
                    get: { Double(inputGain) },
                    set: { inputGain = Float($0) }
                ),
                in: gainRange
            ) {
                Text(L10n.string("common.inputVolume", default: "Input volume"))
            } minimumValueLabel: {
                Text(minLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsTheme.textSecondary)
            } maximumValueLabel: {
                Text(maxLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Whether the currently-bound device supports settable hardware volume.
    /// Resolves against the user's chosen UID OR, if they picked "Default",
    /// against the live system default device. Refreshes when the device
    /// list refreshes via the @StateObject's published changes.
    private var hardwareGainAvailable: Bool {
        if let uid = selectedDeviceUID {
            return AudioInputDeviceManager.canSetHardwareGain(forUID: uid)
        }
        return AudioInputDeviceManager.canSetHardwareGainForSystemDefault()
    }

    private var gainRange: ClosedRange<Double> {
        hardwareGainAvailable ? 0...1 : 1...2
    }

    private var minLabel: String { hardwareGainAvailable ? "Off" : "Off" }
    private var maxLabel: String { hardwareGainAvailable ? "Max" : "2×" }

    private var gainPercentLabel: String {
        // In hardware mode 1.0 reads as 100%; in software mode 1.0 reads as
        // 100% (unchanged) and 2.0 reads as 200%. Same arithmetic either way.
        "\(Int((Double(inputGain) * 100).rounded()))%"
    }

}

/// Tiny `ObservableObject` adapter so the shared
/// `AudioInputDeviceManager.shared` (a `@MainActor` singleton) plugs into
/// SwiftUI's `@StateObject` re-render machinery without making the manager
/// itself a SwiftUI-specific class. Re-publishes the two fields views
/// render against.
///
/// `internal` (not `private`) because the meeting new-sheet has its own
/// dark-themed picker that reuses the same observer.
@MainActor
final class AudioInputDeviceManagerObserver: ObservableObject {
    @Published private(set) var availableDevices: [AudioInputDevice] = []
    @Published private(set) var systemDefaultDeviceName: String?

    private var devicesCancellable: AnyCancellable?
    private var defaultCancellable: AnyCancellable?

    init() {
        let manager = AudioInputDeviceManager.shared
        availableDevices = manager.availableDevices
        systemDefaultDeviceName = manager.systemDefaultDeviceName
        devicesCancellable = manager.$availableDevices
            .receive(on: DispatchQueue.main)
            .assign(to: \.availableDevices, on: self)
        defaultCancellable = manager.$systemDefaultDeviceName
            .receive(on: DispatchQueue.main)
            .assign(to: \.systemDefaultDeviceName, on: self)
    }

    func device(forUID uid: String?) -> AudioInputDevice? {
        guard let uid else { return nil }
        return availableDevices.first { $0.uid == uid }
    }

    func refresh() {
        AudioInputDeviceManager.shared.refresh()
    }
}
