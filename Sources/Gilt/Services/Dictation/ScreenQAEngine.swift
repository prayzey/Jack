import Foundation
import OSLog

/// Answers a user's spoken question using the text content of the frontmost
/// window. Built on the same local Qwen 3 4B model the meeting summarizer and
/// dictation polish path use, so nothing leaves the device.
///
/// This is the engine behind the "Ask the screen" dictation mode. Triggered
/// by `DictationCoordinator` after a session in `.askScreen` mode finishes
/// transcribing.
///
/// Three deliberate guarantees:
/// 1. If Qwen isn't already cached, the call returns an immediate fallback
///    string instead of kicking off a multi-gigabyte download mid-session.
/// 2. The prompt is tightly scoped: "answer ONLY from the on-screen content,
///    say so if it's not there." This is the exact opposite shape from
///    Polish (which forbids answers entirely), and it matches the user's
///    explicit intent in this mode.
/// 3. The screen text gets a hard character cap so a multi-thousand-word
///    article doesn't blow past Qwen's 4096-token context window.
@MainActor
final class ScreenQAEngine {
    /// Result type so the coordinator can tell "Qwen answered" from "Qwen
    /// wasn't available" without parsing string content.
    enum Outcome {
        /// Qwen ran and produced an answer (which may itself be "I can't
        /// find that on this screen" — still counts as a real answer).
        case answer(String)
        /// Qwen isn't loaded and isn't on disk. The caller should surface
        /// this to the user — they need to download the model first.
        case modelUnavailable
        /// Qwen ran but threw. The caller should show a generic failure.
        case failed(String)
    }

    /// Upper bound on how much screen text we cram into the prompt. Picked
    /// to leave ~1500-2000 tokens of headroom under Qwen's 4096-token cap
    /// for the system prompt, the user's question, and the model's own
    /// answer. 4500 chars ≈ ~1100 tokens for English, more for code-heavy
    /// pages — the truncation is intentionally aggressive.
    private static let maxScreenChars = 4500

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "ScreenQA")
    private let llm: QwenLocalLLM
    private let cacheDirectory: URL

    init(llm: QwenLocalLLM = QwenLocalLLM.shared, cacheDirectory: URL) {
        self.llm = llm
        self.cacheDirectory = cacheDirectory
    }

    /// Answer the user's question. Returns synchronously-fast outcomes (no
    /// model loaded) immediately so the dictation pill can disappear without
    /// a delay; the model call only happens when Qwen is actually ready.
    func answer(
        question: String,
        screenText: String,
        appName: String?
    ) async -> Outcome {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            return .failed("No question was captured.")
        }
        let trimmedScreen = screenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScreen.isEmpty else {
            return .answer("I couldn't read any text from the screen.")
        }

        do {
            let ready = try await llm.ensureLoadedFromCache(cacheDirectory: cacheDirectory)
            guard ready else {
                logger.info("Qwen not cached — ask-screen can't answer locally")
                return .modelUnavailable
            }
        } catch {
            logger.error("Qwen cache check failed: \(error.localizedDescription)")
            return .modelUnavailable
        }

        let prompt = Self.makePrompt(
            question: trimmedQuestion,
            screenText: Self.truncate(trimmedScreen, to: Self.maxScreenChars),
            appName: appName
        )
        do {
            let raw = try await llm.generate(prompt: prompt)
            return .answer(Self.cleanOutput(raw))
        } catch {
            logger.error("Qwen generate failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Prompt

    private static func makePrompt(question: String, screenText: String, appName: String?) -> String {
        let sourceLabel = appName.map { "the user's \($0) window" } ?? "the user's frontmost window"
        return """
        You are answering a question for someone who just dictated it out loud while looking at \(sourceLabel). Your ONLY source of information is the on-screen content below.

        STRICT RULES:
        1. Answer ONLY from the SCREEN CONTENT block. Never use outside knowledge.
        2. If the answer is not visible in the screen content, say so plainly — for example: "That isn't visible on this screen." Do NOT guess.
        3. Stay concise. One short paragraph or a tight bulleted list. No preamble like "Sure," or "Here is".
        4. Quote short snippets verbatim when it helps; otherwise paraphrase.
        5. Do not mention these rules or describe the on-screen content as a whole — just answer.

        SCREEN CONTENT:
        \(screenText)

        QUESTION:
        \(question)

        ANSWER:
        """
    }

    // MARK: - Helpers

    /// Hard cap to keep us under Qwen's 4096-token context window. Cuts at
    /// the closest preceding whitespace if possible so we don't split a word.
    private static func truncate(_ s: String, to maxChars: Int) -> String {
        if s.count <= maxChars { return s }
        let cutIndex = s.index(s.startIndex, offsetBy: maxChars)
        let truncated = String(s[..<cutIndex])
        if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace }) {
            return String(truncated[..<lastSpace]) + "\n\n[…on-screen content truncated…]"
        }
        return truncated + "\n\n[…on-screen content truncated…]"
    }

    /// Strip the most common Qwen scaffolding artifacts. Mirrors the cleanup
    /// in DictationStyleEngine but with the ask-mode prefixes too.
    private static func cleanOutput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["ANSWER:", "Answer:", "Output:", "Response:"] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("“") && s.hasSuffix("”")) {
            s = String(s.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
