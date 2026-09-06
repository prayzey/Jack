import SwiftUI

/// Tiny looping demo used in Settings to *show* what a voice feature does
/// instead of explaining it in prose: a spoken command types itself into a
/// mock dictation pill, then the feature's result springs in underneath.
/// Pure SwiftUI animation, no video assets.
struct DictationFeatureDemoView: View {
    /// The spoken command that types itself out, e.g. "Remind me to call mom at 5".
    let command: String
    let resultIcon: String
    let resultTitle: String
    let resultSubtitle: String
    /// Accent for the result icon chip (e.g. Reminders orange, Ask cyan).
    let accent: Color

    @State private var typedCharacters = 0
    @State private var showResult = false
    @State private var loopTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            commandPill
            resultRow
                .opacity(showResult ? 1 : 0)
                .offset(y: showResult ? 0 : 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.11))
        )
        .onAppear(perform: startLoop)
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: say \(command), and you get \(resultTitle), \(resultSubtitle)")
    }

    // MARK: - Pieces

    private var commandPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)

            Text(typedCommand)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)

            // Blinking caret while "speaking".
            if !showResult {
                Capsule()
                    .fill(accent.opacity(0.9))
                    .frame(width: 2, height: 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
    }

    private var typedCommand: String {
        String(command.prefix(typedCharacters))
    }

    private var resultRow: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent.opacity(0.22))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: resultIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(resultTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(resultSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(accent.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Loop

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                typedCharacters = 0
                showResult = false

                // Type the command character by character.
                for index in 1...command.count {
                    try? await Task.sleep(nanoseconds: 45_000_000)
                    if Task.isCancelled { return }
                    typedCharacters = index
                }

                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showResult = true
                }

                // Hold the finished state so it can be read, then restart.
                try? await Task.sleep(nanoseconds: 2_600_000_000)
            }
        }
    }
}
