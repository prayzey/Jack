import SwiftUI

/// The dictate toggle inside the compose window. Tap to start a `.compose`
/// dictation session, tap again to stop. Reflects the shared coordinator's
/// phase so the user can see when Jack is listening vs. transcribing — the
/// finished text lands in the editor at the caret (see `DictationCoordinator`'s
/// compose branch), so there's no separate "paste" step here.
struct ComposeMicButton: View {
    @ObservedObject var coordinator: DictationCoordinator

    private var isListening: Bool {
        if case .listening = coordinator.phase { return true }
        return false
    }

    private var isWorking: Bool {
        switch coordinator.phase {
        case .transcribing, .rewriting, .pasting: return true
        default: return false
        }
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                glyph
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous).fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke, lineWidth: isListening ? 1.5 : 0)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        // Block re-entry while the engine is mid-transcription — tapping then
        // would only restart and drop the in-flight audio.
        .disabled(isWorking)
        .animation(.easeOut(duration: 0.18), value: coordinator.phase)
    }

    @ViewBuilder
    private var glyph: some View {
        if isWorking {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        } else if isListening {
            // The dot scales gently with live mic level so the button feels
            // alive while recording.
            Circle()
                .fill(Color(red: 0.96, green: 0.36, blue: 0.36))
                .frame(width: 11, height: 11)
                .scaleEffect(1 + CGFloat(min(coordinator.level, 1)) * 0.5)
                .animation(.easeOut(duration: 0.12), value: coordinator.level)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var label: String {
        if isWorking { return "Transcribing…" }
        if isListening { return "Listening. Tap to stop" }
        return "Dictate"
    }

    private var fill: Color {
        if isListening { return Color(red: 0.96, green: 0.36, blue: 0.36).opacity(0.22) }
        return Color.white.opacity(0.1)
    }

    private var stroke: Color {
        Color(red: 0.96, green: 0.36, blue: 0.36).opacity(0.6)
    }

    private func toggle() {
        if coordinator.isActive {
            coordinator.stopSession()
        } else {
            coordinator.startSession(mode: .compose)
        }
    }
}
