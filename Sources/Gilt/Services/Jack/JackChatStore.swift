import Foundation
import OSLog

/// Owns the running chat thread with Jack. Wraps `QwenLocalLLM.shared` and
/// exposes a SwiftUI-friendly `@Published` surface for `JackChatView`.
///
/// The store is in-memory only — messages don't persist across app
/// relaunches by design. Phase 4 ships with ephemeral chat; persistence can
/// land later if users miss it.
@MainActor
final class JackChatStore: ObservableObject {
    /// High-level state of the chat. Drives what the UI shows.
    enum Status: Equatable {
        /// Idle / ready to accept the next message.
        case idle
        /// Model file is being fetched from Hugging Face (first run only).
        /// Progress 0…1. We only emit this when the GGUF is genuinely
        /// missing from disk — a cached-but-not-yet-loaded model uses
        /// `.loadingModel` instead, so returning users never see the
        /// misleading "first-time setup" copy.
        case downloadingModel(progress: Double)
        /// Model is on disk and being read into memory (~1–2s on warm
        /// cache). Distinct from `.downloadingModel` so the UI can show a
        /// quiet "waking up" indicator instead of a progress bar.
        case loadingModel
        /// Model is loaded but generation is in flight.
        case thinking
        /// Something went wrong on the last turn. The user can retry.
        case error(String)
    }

    @Published private(set) var messages: [JackChatMessage] = []
    @Published private(set) var status: Status = .idle

    /// Where the GGUF file lives on disk. Shared with the meeting summary
    /// pipeline so we don't keep two copies of the same multi-GB model.
    private let cacheDirectory: URL
    private let llm: QwenLocalLLM
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "JackChat")

    init(
        cacheDirectory: URL,
        llm: QwenLocalLLM = QwenLocalLLM.shared
    ) {
        self.cacheDirectory = cacheDirectory
        self.llm = llm
    }

    /// True iff the model is already cached on disk (so the first chat
    /// message won't trigger a multi-GB download).
    var isModelCached: Bool {
        QwenLocalLLM.cachedModelExists(in: cacheDirectory)
    }

    /// Erase the chat thread. Doesn't touch the loaded model.
    func clear() {
        messages = []
        status = .idle
    }

    /// Send a user message. Synchronously appends the user bubble, kicks off
    /// model load + generation, then appends Jack's reply when ready. Errors
    /// surface as `Status.error` and a system message bubble.
    func send(_ rawText: String) async {
        let userText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        let userMessage = JackChatMessage(role: .user, text: userText)
        let history = messages
        messages.append(userMessage)

        do {
            try await ensureModelReady()
            status = .thinking
            let prompt = JackChatPromptBuilder.makePrompt(
                history: history,
                userMessage: userText
            )
            let raw = try await llm.generate(prompt: prompt)
            let clean = JackChatPromptBuilder.cleanResponse(raw)
            let reply = clean.isEmpty
                ? "I'm here, but I didn't catch a clear answer. Try rephrasing?"
                : clean
            messages.append(JackChatMessage(role: .jack, text: reply))
            status = .idle
        } catch {
            logger.error("Jack chat turn failed: \(error.localizedDescription)")
            status = .error(friendlyMessage(for: error))
        }
    }

    /// Retry the last failed turn. Removes the orphaned user message before
    /// re-sending so we don't end up with two copies in the thread.
    func retryLastTurn() async {
        guard case .error = status else { return }
        guard let last = messages.last, last.role == .user else {
            status = .idle
            return
        }
        let textToResend = last.text
        messages.removeLast()
        await send(textToResend)
    }

    // MARK: - Internals

    /// Load (or download) the model if not ready. Picks the right initial
    /// status based on whether the GGUF is already cached on disk so the
    /// UI never shows "first-time setup — fetching" for a returning user
    /// whose model is already there. The progress callback can still bump
    /// us up to `.downloadingModel(progress:)` if the file turns out to
    /// be missing or fails the integrity check.
    private func ensureModelReady() async throws {
        if llm.isLoaded { return }
        let cached = isModelCached
        status = cached ? .loadingModel : .downloadingModel(progress: 0)
        try await llm.ensureLoaded(cacheDirectory: cacheDirectory) { [weak self] fraction in
            guard let self else { return }
            // If we believed the file was cached but `ensureLoaded` ended
            // up downloading (e.g. integrity check rejected it), flip to
            // the real progress UI so the user isn't staring at a static
            // "loading" pill while a 2 GB transfer runs in the background.
            switch self.status {
            case .loadingModel:
                if fraction < 0.95 {
                    self.status = .downloadingModel(progress: fraction)
                }
            case .downloadingModel(let current):
                guard abs(fraction - current) >= 0.005 else { return }
                self.status = .downloadingModel(progress: fraction)
            default:
                break
            }
        }
    }

    /// Convert any error into a one-line, user-readable string. We never
    /// dump raw `Error` descriptions into the chat bubble — too technical
    /// and often unhelpful.
    private func friendlyMessage(for error: Error) -> String {
        if let qwen = error as? QwenLLMError, let message = qwen.errorDescription {
            return message
        }
        let raw = error.localizedDescription
        if raw.isEmpty { return "Something went wrong. Try again in a moment." }
        return raw
    }
}
