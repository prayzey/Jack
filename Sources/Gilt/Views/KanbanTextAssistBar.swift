import SwiftUI

/// Quick-pick chips that run on-device Qwen over Kanban task draft text.
struct KanbanTextAssistBar: View {
    @Binding var text: String
    let cacheDirectory: URL
    let customPresets: [KanbanCustomAssistPreset]

    @State private var isRunning = false
    @State private var runningChoice: KanbanAssistChoice?
    @State private var statusMessage: String?

    private var choices: [KanbanAssistChoice] {
        KanbanAssistCatalog.choices(customPresets: customPresets)
    }

    private var engine: KanbanTextAssistEngine {
        KanbanTextAssistEngine(cacheDirectory: cacheDirectory)
    }

    private var canRun: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            assistChipGrid

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var assistChipGrid: some View {
        let rows = chipRows
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 6) {
                    ForEach(row) { choice in
                        assistChip(choice)
                    }
                    if isRunning, rowIndex == rows.count - 1 {
                        assistSpinner
                    }
                }
            }
        }
    }

    /// Two chips per row so labels fit on 260pt Kanban cards.
    private var chipRows: [[KanbanAssistChoice]] {
        stride(from: 0, to: choices.count, by: 2).map { start in
            Array(choices[start..<min(start + 2, choices.count)])
        }
    }

    private var assistSpinner: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.75)
    }

    @ViewBuilder
    private func assistChip(_ choice: KanbanAssistChoice) -> some View {
        let isActive = runningChoice == choice
        Button {
            Task { await runAssist(choice) }
        } label: {
            Text(choice.menuTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.78))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isActive ? 0.18 : 0.10))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
        .opacity(canRun ? 1 : 0.45)
        .help(choice.helpText ?? "")
    }

    @MainActor
    private func runAssist(_ choice: KanbanAssistChoice) async {
        guard canRun else { return }
        isRunning = true
        runningChoice = choice
        statusMessage = nil
        defer {
            isRunning = false
            runningChoice = nil
        }

        let outcome = await engine.process(text: text, choice: choice)
        switch outcome {
        case .improved(let improved):
            text = improved
        case .unchanged:
            break
        case .modelNotDownloaded:
            statusMessage = L10n.string(
                "workspace.kanban.assist.modelMissing",
                default: "Download the on-device Qwen model in Settings (Dictation or Meetings) to use writing help."
            )
        case .failed:
            statusMessage = L10n.string(
                "workspace.kanban.assist.failed",
                default: "Couldn't improve the text. Try again."
            )
        }
    }
}
