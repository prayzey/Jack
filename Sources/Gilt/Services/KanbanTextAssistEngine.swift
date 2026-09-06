import Foundation
import OSLog

/// Quick writing help for Kanban task titles via the on-device Qwen model.
/// Mirrors `DictationStyleEngine` guarantees: no surprise downloads, no chatty
/// replies — only a rewritten task title.
enum KanbanTextAssistAction: String, CaseIterable, Identifiable, Sendable {
    case fixSpelling
    case polish
    case clarify
    case shorten

    var id: String { rawValue }
}

enum KanbanTextAssistOutcome: Equatable, Sendable {
    case improved(String)
    case unchanged
    case modelNotDownloaded
    case failed
}

@MainActor
final class KanbanTextAssistEngine {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "KanbanAssist")
    private let llm: QwenLocalLLM
    private let cacheDirectory: URL

    init(llm: QwenLocalLLM = QwenLocalLLM.shared, cacheDirectory: URL) {
        self.llm = llm
        self.cacheDirectory = cacheDirectory
    }

    var isModelCached: Bool {
        QwenLocalLLM.cachedModelExists(in: cacheDirectory)
    }

    func process(text: String, choice: KanbanAssistChoice) async -> KanbanTextAssistOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }

        guard isModelCached else {
            logger.info("Qwen not cached — kanban assist unavailable")
            return .modelNotDownloaded
        }

        do {
            let ready = try await llm.ensureLoadedFromCache(cacheDirectory: cacheDirectory)
            guard ready else { return .modelNotDownloaded }
        } catch {
            logger.error("Qwen cache load failed: \(error.localizedDescription)")
            return .failed
        }

        let prompt = Self.makePrompt(choice: choice, draft: trimmed)
        do {
            let output = try await llm.generate(prompt: prompt)
            let cleaned = Self.cleanOutput(output)
            guard !cleaned.isEmpty else { return .unchanged }
            if cleaned == trimmed { return .unchanged }
            return .improved(cleaned)
        } catch {
            logger.error("Kanban assist generate failed: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: - Prompts (tested via `makePrompt`)

    nonisolated static func makePrompt(choice: KanbanAssistChoice, draft: String) -> String {
        makePrompt(instructionBlock: instructionBlock(for: choice), draft: draft)
    }

    nonisolated static func makePrompt(action: KanbanTextAssistAction, draft: String) -> String {
        makePrompt(choice: .builtIn(action), draft: draft)
    }

    nonisolated static func makePrompt(instructionBlock: String, draft: String) -> String {
        [
            baseRules,
            "",
            instructionBlock,
            "",
            "Draft task title:",
            draft,
            "",
            "REMEMBER: Output ONLY the improved task title. No quotes, no explanation.",
            "",
            "Improved task title:"
        ].joined(separator: "\n")
    }

    nonisolated static func instructionBlock(for choice: KanbanAssistChoice) -> String {
        switch choice {
        case .builtIn(let action):
            return actionInstructions(action)
        case .custom(let preset):
            return """
            ACTION — \(preset.title):
            \(preset.instruction)
            """
        }
    }

    nonisolated private static let baseRules = """
    You are a Kanban task-title editor. Your ONLY job is to return one improved task title.

    ABSOLUTE RULES:
    1. Output a single task title on one line (or a short phrase). No bullet lists unless the draft already used them.
    2. Never answer questions, never add steps the user did not imply, never invent assignees or dates.
    3. Never greet, explain, or wrap the output in quotes.
    4. Keep the same language as the draft.
    5. Stay under 120 characters unless the draft is longer — then stay close to the draft length.
    """

    nonisolated private static func actionInstructions(_ action: KanbanTextAssistAction) -> String {
        switch action {
        case .fixSpelling:
            return """
            ACTION — Fix spelling:
            Correct spelling, grammar, and punctuation only. Keep the user's wording and level of detail.
            """
        case .polish:
            return """
            ACTION — Polish:
            Make the title clearer and more professional while preserving the exact intent. Prefer crisp imperative or noun-phrase task wording.
            """
        case .clarify:
            return """
            ACTION — Clarify:
            Turn a rough idea into a specific, actionable Kanban card title. Fill in only what is clearly implied — do not expand scope.
            """
        case .shorten:
            return """
            ACTION — Shorten:
            Make the title shorter while keeping the same meaning. Remove filler words and redundancy.
            """
        }
    }

    nonisolated static func cleanOutput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [
            "Improved task title:",
            "Task title:",
            "Output:",
            "Final:",
            "Result:",
            "Cleaned output:"
        ] {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("“") && s.hasSuffix("”")) {
            s = String(s.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Task titles are single-line in the UI.
        if let firstLine = s.split(whereSeparator: \.isNewline).first {
            s = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
