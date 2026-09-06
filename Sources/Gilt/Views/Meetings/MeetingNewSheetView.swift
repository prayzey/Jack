import SwiftUI

/// Modal sheet that creates a new meeting. Pure workspace aesthetic: gold
/// eyebrow + bold title, neutral pill controls, no purple anywhere.
struct MeetingNewSheetView: View {
    @ObservedObject var meetingStore: MeetingStore
    @ObservedObject var modelManager: MeetingModelManager
    let accent: Color
    let onCreated: (MeetingSession) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var language: MeetingLanguage = .auto
    @State private var audioSource: MeetingAudioSource = .microphone
    /// Local mirrors of the persisted mic settings. We sync from the store on
    /// `onAppear` and write back on Start (in the `actions` button handler)
    /// so the user's tweak becomes the new default for next time — same
    /// pattern the language picker uses.
    @State private var preferredMicUID: String?
    @State private var inputGain: Float = 1.0
    @StateObject private var devices = AudioInputDeviceManagerObserver()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            VStack(alignment: .leading, spacing: 18) {
                titleField
                languageRow
                audioSourceRow
                if audioSource.requiresMicrophone {
                    microphoneRow
                    inputGainRow
                }
            }
            modelReadinessNotice
            Spacer(minLength: 0)
            actions
        }
        .padding(28)
        .frame(width: 540)
        .background(Color(white: 0.08))
        .onAppear {
            title = ""
            language = meetingStore.settings.defaultLanguage
            preferredMicUID = meetingStore.settings.preferredMicDeviceUID
            inputGain = meetingStore.settings.inputGain
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.new.meeting.2", default: "NEW MEETING"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(accent.opacity(0.85))
            Text(L10n.string("meeting.dashboard.empty.cta", default: "Start a meeting"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .tracking(-0.3)
            Text(L10n.string("ui.jack.records.locally.audio.and.notes.1d936b", default: "Jack records locally. Audio and notes stay on this Mac."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Title")
            TextField("Optional", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Language")
            HStack(spacing: 6) {
                ForEach(MeetingLanguage.allCases) { option in
                    chip(
                        label: "\(option.flagEmoji)  \(option.displayName)",
                        selected: language == option
                    ) {
                        language = option
                    }
                }
            }
            Text(language.captureSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var audioSourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Audio source")
            HStack(spacing: 8) {
                ForEach(MeetingAudioSource.allCases) { source in
                    qualityChip(
                        title: source.displayName,
                        sub: source.captureSubtitle,
                        selected: audioSource == source
                    ) {
                        audioSource = source
                    }
                }
            }
            Text(L10n.string("ui.system.audio.may.ask.for.screen.reco.302ea7", default: "System audio may ask for Screen Recording permission the first time."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2.0)
            .foregroundStyle(.white.opacity(0.45))
    }

    // MARK: - Microphone + input gain (only shown when source uses the mic)

    private var microphoneRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Microphone")
            HStack(spacing: 8) {
                Menu {
                    Button {
                        preferredMicUID = nil
                    } label: {
                        HStack {
                            Text(defaultMenuLabel)
                            Spacer()
                            if preferredMicUID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    if !devices.availableDevices.isEmpty {
                        Divider()
                    }

                    ForEach(devices.availableDevices) { device in
                        Button {
                            preferredMicUID = device.uid
                        } label: {
                            HStack {
                                Text(device.name)
                                Spacer()
                                if preferredMicUID == device.uid {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(currentMicLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Button {
                    devices.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("Refresh device list")
            }
        }
    }

    private var inputGainRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                label("Input volume")
                Spacer()
                Text(gainModeLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.4))
                Text(gainPercentLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Slider(
                value: Binding(
                    get: { Double(inputGain) },
                    set: { inputGain = Float($0) }
                ),
                in: gainRange
            )
            .tint(accent)
        }
    }

    // MARK: - Mic + gain helpers

    private var currentMicLabel: String {
        if let uid = preferredMicUID, let device = devices.device(forUID: uid) {
            return device.name
        }
        if preferredMicUID != nil {
            return "(not connected), using default"
        }
        return "Default"
    }

    private var defaultMenuLabel: String {
        if let systemDefault = devices.systemDefaultDeviceName {
            return "Default: \(systemDefault)"
        }
        return "Default"
    }

    /// Mirrors the dictation section's mode logic: resolves against the
    /// chosen UID, or the live system default if "Default" is selected.
    private var hardwareGainAvailable: Bool {
        if let uid = preferredMicUID {
            return AudioInputDeviceManager.canSetHardwareGain(forUID: uid)
        }
        return AudioInputDeviceManager.canSetHardwareGainForSystemDefault()
    }

    private var gainRange: ClosedRange<Double> {
        hardwareGainAvailable ? 0...1 : 1...2
    }

    private var gainModeLabel: String {
        hardwareGainAvailable ? "SYSTEM" : "SOFTWARE +"
    }

    private var gainPercentLabel: String {
        "\(Int((Double(inputGain) * 100).rounded()))%"
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .black.opacity(0.85) : .white.opacity(0.78))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? accent : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(
                        selected ? Color.clear : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func qualityChip(
        title: String,
        sub: String,
        selected: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? .black.opacity(0.85) : .white.opacity(disabled ? 0.4 : 0.85))
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? .black.opacity(0.65) : .white.opacity(disabled ? 0.3 : 0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? accent : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selected ? Color.clear : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Engine the chosen language routes to. Drives both the readiness notice
    /// and the Start-recording button's enabled state.
    private var recommendedEngine: MeetingTranscriptionEngine {
        MeetingTranscriptionEngine.recommended(for: language)
    }

    // ponytail: `recommended(for:)` only returns parakeetV2/whisper, whose
    // displayName matches the old hand-written labels exactly.
    private var recommendedEngineLabel: String { recommendedEngine.displayName }

    private var modelReady: Bool {
        modelManager.transcriptionState(for: recommendedEngine).isReady
    }

    @ViewBuilder
    private var modelReadinessNotice: some View {
        let state = modelManager.transcriptionState(for: recommendedEngine)
        if !state.isReady {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: modelNoticeIcon(state))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.9))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(modelNoticeTitle(state))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(modelNoticeBody(state))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if case let .downloading(progress, _) = state {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(accent)
                    } else {
                        modelNoticeActionButton(state)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private func modelNoticeIcon(_ state: MeetingModelDownloadState) -> String {
        switch state {
        case .missing:      return "arrow.down.circle"
        case .downloading:  return "arrow.down.circle.fill"
        case .failed:       return "exclamationmark.triangle"
        case .ready:        return "checkmark.circle"
        }
    }

    private func modelNoticeTitle(_ state: MeetingModelDownloadState) -> String {
        switch state {
        case .missing:
            return "Download the \(recommendedEngineLabel.lowercased()) to record \(languageLabel)"
        case .downloading(let progress, _):
            return "Downloading the \(recommendedEngineLabel.lowercased()): \(Int(progress * 100))%"
        case .failed:
            return "Couldn't download the \(recommendedEngineLabel.lowercased())"
        case .ready:
            return ""
        }
    }

    private func modelNoticeBody(_ state: MeetingModelDownloadState) -> String {
        let size = formattedModelSize(recommendedEngine.approximateDownloadSizeBytes)
        switch state {
        case .missing:
            return "Jack needs the \(recommendedEngine.displayName) model (\(size)) on disk before it can transcribe \(languageLabel). Downloads once and works offline after that."
        case .downloading:
            return "Pulling from Hugging Face. Safe to leave this open. Recording stays disabled until it finishes."
        case .failed:
            return "The download didn't complete. Check your connection and tap Retry."
        case .ready:
            return ""
        }
    }

    @ViewBuilder
    private func modelNoticeActionButton(_ state: MeetingModelDownloadState) -> some View {
        switch state {
        case .missing, .failed:
            Button {
                Task { await modelManager.downloadTranscriptionModel(recommendedEngine) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFailed(state) ? "arrow.clockwise" : "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isFailed(state) ? "Retry download" : "Download \(formattedModelSize(recommendedEngine.approximateDownloadSizeBytes))")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }

    private var languageLabel: String {
        switch language {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .german:  return "German"
        case .mixed:   return "mixed-language speech"
        case .auto:    return "non-English speech"
        }
    }

    private func isFailed(_ state: MeetingModelDownloadState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func formattedModelSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        return "\(Int(mb)) MB"
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button(action: onCancel) {
                Text(L10n.string("settings.alert.cancel", default: "Cancel"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)

            Spacer()

            Button {
                let session = meetingStore.createSession(
                    title: title,
                    language: language,
                    audioSource: audioSource
                )
                var updated = meetingStore.settings
                updated.defaultLanguage = language
                updated.preferredMicDeviceUID = preferredMicUID
                updated.inputGain = inputGain
                meetingStore.settings = updated
                meetingStore.persistSettings()
                onCreated(session)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.string("meeting.new.start", default: "Start recording"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(modelReady ? 0.9 : 0.35))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(accent.opacity(modelReady ? 1.0 : 0.35)))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
            .disabled(!modelReady)
            .help(modelReady ? "" : "Download the speech model first.")
        }
    }
}
