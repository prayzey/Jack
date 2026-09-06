import Foundation
import OSLog

/// Generates the long-form essay-style recap that backs the Story tab.
///
/// Two entry points:
///   - `extend(...)` appends a single new paragraph drawn from the latest
///     slice of transcript. The existing essay is sent as locked context so
///     user edits are preserved by construction.
///   - `regenerate(...)` redrafts the whole essay from the full transcript.
///     Called from the explicit Regenerate button only.
///
/// Both paths route through `QwenLocalLLM`. We never download the model on
/// demand — if it isn't already cached, we no-op and let the user kick off
/// the download from the existing Models settings sheet.
@MainActor
final class MeetingStoryService {
    private let modelsRoot: URL
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingStory")

    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    /// Sentinel the model is told to emit when nothing substantive happened
    /// in the last window. We check for this case-insensitively because
    /// quantized LLMs are unreliable about exact-string echo.
    private static let noExtensionSentinel = "NO_EXTENSION"

    /// Extends `existingStory` with one new paragraph drawn from `newChunks`.
    /// Returns `nil` when the model decides nothing substantive was said, or
    /// when Qwen isn't loadable from cache (in which case auto-extend is a
    /// no-op until the user downloads the model).
    func extend(
        existingStory: String,
        newChunks: [MeetingTranscriptChunk],
        language: MeetingLanguage
    ) async -> String? {
        guard !newChunks.isEmpty else { return nil }
        guard let bot = await cachedQwen() else { return nil }

        let prompt = MeetingPromptBuilder(language: language)
            .storyExtensionPrompt(existingStory: existingStory, newChunks: newChunks)

        do {
            let raw = try await bot.generate(prompt: prompt)
            let cleaned = sanitize(raw)
            if cleaned.isEmpty { return nil }
            if cleaned.uppercased().contains(Self.noExtensionSentinel) { return nil }
            return cleaned
        } catch {
            logger.warning("Story extend failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Redrafts the full essay from the entire transcript. Returns `nil` when
    /// Qwen isn't loadable or the transcript is empty.
    func regenerate(
        transcript: [MeetingTranscriptChunk],
        meetingTitle: String,
        language: MeetingLanguage
    ) async -> String? {
        guard !transcript.isEmpty else { return nil }
        guard let bot = await cachedQwen() else { return nil }

        let prompt = MeetingPromptBuilder(language: language)
            .storyRegeneratePrompt(transcript: transcript, meetingTitle: meetingTitle)

        do {
            let raw = try await bot.generate(prompt: prompt)
            let cleaned = sanitize(raw)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            logger.warning("Story regenerate failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private

    private func qwenCacheDirectory() -> URL {
        MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: modelsRoot
        )
    }

    private func cachedQwen() async -> QwenLocalLLM? {
        do {
            let loaded = try await QwenLocalLLM.shared.ensureLoadedFromCache(
                cacheDirectory: qwenCacheDirectory()
            )
            return loaded ? QwenLocalLLM.shared : nil
        } catch {
            logger.warning("Story cached load failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Trim model preamble, strip code fences, replace any em/en-dashes the
    /// model snuck past the system prompt with a period plus space. Belt and
    /// suspenders — the prompt forbids them but quantized models drift.
    private func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ``` fences if Qwen wrapped the output.
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let closing = s.range(of: "```", options: .backwards) {
                s = String(s[..<closing.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip common preambles like "Here is the next paragraph:".
        let preamblePatterns = [
            "Here is the next paragraph:",
            "Here's the next paragraph:",
            "Here is the paragraph:",
            "Here's the paragraph:",
            "Next paragraph:",
            "Paragraph:"
        ]
        for pattern in preamblePatterns {
            if s.lowercased().hasPrefix(pattern.lowercased()) {
                s = String(s.dropFirst(pattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Drop surrounding quotation marks.
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("\u{201C}") && s.hasSuffix("\u{201D}")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Enforce the no-em-dash rule even if the model slipped one in.
        s = s.replacingOccurrences(of: " — ", with: ". ")
        s = s.replacingOccurrences(of: " – ", with: ". ")
        s = s.replacingOccurrences(of: "—", with: ", ")
        s = s.replacingOccurrences(of: "–", with: ", ")

        return s
    }
}
