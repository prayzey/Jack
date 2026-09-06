import SwiftUI

/// Compact floating progress card for audio-file transcription. Hosted in a
/// borderless panel by `TranscriptionHUDWindowManager` so it shows over any
/// view mode (tray, workspace, or nothing at all).
///
/// Audio is the orange type in Jack's palette, so the accent here matches the
/// audio clip cards for visual continuity.
struct TranscriptionHUDView: View {
    @ObservedObject var coordinator: AudioTranscriptionCoordinator
    var onDismiss: () -> Void

    private static let accent = Color(red: 0.96, green: 0.58, blue: 0.28)

    var body: some View {
        if let job = coordinator.currentJob {
            card(for: job)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func card(for job: TranscriptionJob) -> some View {
        HStack(spacing: 12) {
            icon(for: job.stage)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title(for: job))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if job.total > 1 {
                        Text("\(job.index) of \(job.total)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                subtitle(for: job.stage)
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Self.accent.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .padding(6)
    }

    // MARK: - Icon

    @ViewBuilder
    private func icon(for stage: TranscriptionJob.Stage) -> some View {
        switch stage {
        case .completed:
            roundIcon("checkmark", tint: Color(red: 0.30, green: 0.78, blue: 0.55))
        case .failed:
            roundIcon("exclamationmark.triangle.fill", tint: Color(red: 0.93, green: 0.38, blue: 0.48))
        case .noSpeech:
            roundIcon("waveform.slash", tint: .white.opacity(0.55))
        case .preparingModel:
            roundIcon("arrow.down", tint: Self.accent)
        case .queued, .decoding, .transcribing:
            ZStack {
                Circle().fill(Self.accent.opacity(0.18))
                ProgressView()
                    .controlSize(.small)
                    .tint(Self.accent)
            }
        }
    }

    private func roundIcon(_ symbol: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        }
    }

    // MARK: - Copy

    private func title(for job: TranscriptionJob) -> String {
        switch job.stage {
        case .completed: return "Transcript saved"
        case .failed: return "Couldn't transcribe"
        case .noSpeech: return "No speech found"
        default: return job.fileName
        }
    }

    @ViewBuilder
    private func subtitle(for stage: TranscriptionJob.Stage) -> some View {
        switch stage {
        case .queued:
            label("Preparing…")
        case .decoding:
            label("Reading voice note…")
        case .preparingModel(let progress):
            VStack(alignment: .leading, spacing: 5) {
                label("Downloading speech model… \(Int(progress * 100))%")
                progressBar(progress)
            }
        case .transcribing:
            label("Transcribing…")
        case .completed(let charCount):
            label("\(charCount) characters · saved to your clips")
        case .noSpeech:
            label("The audio was silent or unclear.")
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(Self.accent)
                    .frame(width: max(3, proxy.size.width * max(0, min(1, progress))))
            }
        }
        .frame(height: 4)
    }
}
