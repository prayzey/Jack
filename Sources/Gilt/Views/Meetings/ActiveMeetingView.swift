import SwiftUI

/// Live capture surface — visible while a meeting is recording.
///
/// Intentionally minimal: a centered timer, a calm waveform, and three
/// workspace-style pill buttons (pause/stop/discard). What was said lives in
/// the Transcript tab, which auto-scrolls while live. Keeping both surfaces
/// here would just duplicate that view in a worse layout.
struct ActiveMeetingView: View {
    let meetingID: UUID
    let accent: Color

    @EnvironmentObject private var controller: MeetingSessionController
    @EnvironmentObject private var meetingStore: MeetingStore
    @EnvironmentObject private var store: ClipboardStore

    private var recordingAccent: Color { MeetingAccent.recording }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            hero
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                recordingBadge
                statusLine
            }
            timer
            MeetingWaveformView(level: controller.liveLevel, accent: recordingAccent)
                .frame(maxWidth: 560)
                .padding(.horizontal, 28)
            controls
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusLine: some View {
        if case .failed(let reason) = controller.phase {
            VStack(spacing: 10) {
                Text(reason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.93, green: 0.38, blue: 0.48).opacity(0.95))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                if let openSettings = permissionSettingsAction(for: reason) {
                    Button(action: openSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11, weight: .semibold))
                            Text(L10n.string("ui.open.privacy.security", default: "Open Privacy & Security"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let session = meetingStore.session(for: meetingID) {
            Text("\(session.audioSource.displayName) · \(session.transcriptionEngine.displayName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    /// Which Privacy & Security pane the failure reason points at, or nil when
    /// the failure isn't permission-shaped. Screen recording is checked first
    /// because its wording is more specific.
    private func permissionSettingsAction(for reason: String) -> (() -> Void)? {
        let lowered = reason.lowercased()
        if lowered.contains("screen recording")
            || lowered.contains("screen & system audio")
            || lowered.contains("system audio capture") {
            return { store.openScreenRecordingSettings() }
        }
        if lowered.contains("microphone access") || lowered.contains("mic access") {
            return { store.openMicrophoneSettings() }
        }
        return nil
    }

    private var recordingBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(recordingAccent)
                .frame(width: 7, height: 7)
                .shadow(color: recordingAccent.opacity(0.5), radius: 5)
            Text(badgeLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var timer: some View {
        Text(MeetingFormatters.timer(controller.elapsedSeconds))
            .font(.system(size: 72, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .tracking(-1.5)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            secondaryButton(
                icon: pauseIcon,
                label: pauseLabel,
                disabled: !canPause,
                action: togglePause
            )

            Button(action: stop) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(L10n.string("ui.stop.save", default: "Stop & save"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(recordingAccent.opacity(canStop ? 1 : 0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!canStop)

            secondaryButton(
                icon: "trash",
                label: "Discard",
                disabled: false,
                action: discard
            )
        }
    }

    private func secondaryButton(
        icon: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(disabled ? 0.35 : 0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var canPause: Bool {
        switch controller.phase {
        case .recording, .paused: return true
        default: return false
        }
    }

    private var canStop: Bool {
        switch controller.phase {
        case .recording, .paused, .preparing:
            return true
        default:
            return false
        }
    }

    private var pauseIcon: String {
        if case .paused = controller.phase { return "play.fill" }
        return "pause.fill"
    }

    private var pauseLabel: String {
        if case .paused = controller.phase { return "Resume" }
        return "Pause"
    }

    private var badgeLabel: String {
        switch controller.phase {
        case .recording: return "RECORDING"
        case .paused: return "PAUSED"
        case .preparing: return "PREPARING"
        case .finishing: return "WRAPPING UP"
        case .failed: return "PROBLEM"
        case .ready, .idle: return "READY"
        }
    }

    private func togglePause() {
        switch controller.phase {
        case .recording: controller.pause()
        case .paused: controller.resume()
        default: break
        }
    }

    private func stop() {
        Task { await controller.stopAndProcess() }
    }

    private func discard() {
        Task {
            await controller.stopAndProcess()
            meetingStore.deleteSession(meetingID)
            controller.clearSelection()
        }
    }
}
