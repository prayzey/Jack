import Foundation
import OSLog

/// Answers user questions about a meeting using transcript chunks + the rolling
/// summary as context. Backed by the locally-loaded Qwen 3 4B model via
/// `QwenLocalLLM`. Falls back to direct chunk quoting if the model isn't
/// loaded, so citations always work.
@MainActor
final class MeetingQuestionAnsweringService {
    private let modelsRoot: URL
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingQA")
    private let chunker = MeetingTranscriptChunker()

    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    func answer(
        question: String,
        in transcript: [MeetingTranscriptChunk],
        rollingNotes: String,
        meetingID: UUID,
        language: MeetingLanguage,
        previousQuestion: MeetingQuestion? = nil
    ) async throws -> MeetingQuestion {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isGreeting(trimmedQuestion) {
            return MeetingQuestion(
                meetingID: meetingID,
                question: question,
                answer: "Hi. Ask me anything about what has been said in this recording.",
                citations: [],
                askedAt: Date(),
                answeredAt: Date()
            )
        }

        let isOverviewQuestion = Self.isOverviewQuestion(trimmedQuestion)
        let isFollowUp = Self.isFollowUpQuestion(trimmedQuestion)
        let relevant = relevantChunks(
            for: trimmedQuestion,
            in: transcript,
            isOverviewQuestion: isOverviewQuestion,
            isFollowUp: isFollowUp,
            previousQuestion: previousQuestion
        )
        let citations = relevant.map { chunk in
            MeetingAnswerCitation(
                chunkID: chunk.chunkID,
                startTimeSeconds: chunk.startTimeSeconds,
                endTimeSeconds: chunk.endTimeSeconds,
                snippet: chunk.text
            )
        }

        let promptBuilder = MeetingPromptBuilder(language: language)
        let prompt = promptBuilder.answerPrompt(
            question: question,
            relevantChunks: relevant,
            rollingNotes: rollingNotes,
            isFollowUp: isFollowUp
        )

        // Use Qwen when it is loaded or already cached on disk. We deliberately
        // do not auto-trigger the 2.5 GB first download from this path — that
        // runs in the Models panel under explicit user action.
        var answerText: String
        if let bot = await cachedQwenIfAvailable() {
            do {
                answerText = try await bot.generate(prompt: prompt)
                if answerText.isEmpty {
                    answerText = fallbackAnswer(
                        for: trimmedQuestion,
                        using: relevant,
                        isOverviewQuestion: isOverviewQuestion
                    )
                }
            } catch {
                logger.warning("LLM Q&A failed, using fallback: \(error.localizedDescription)")
                answerText = fallbackAnswer(
                    for: trimmedQuestion,
                    using: relevant,
                    isOverviewQuestion: isOverviewQuestion
                )
            }
        } else {
            answerText = fallbackAnswer(
                for: trimmedQuestion,
                using: relevant,
                isOverviewQuestion: isOverviewQuestion
            )
        }

        return MeetingQuestion(
            meetingID: meetingID,
            question: question,
            answer: answerText,
            citations: citations,
            askedAt: Date(),
            answeredAt: Date()
        )
    }

    /// Generates 4 contextual click-to-ask suggestions based on what's been
    /// said so far. Returns the heuristic fallback if Qwen isn't loaded —
    /// callers can still show something useful.
    func generateSuggestedQuestions(
        from transcript: [MeetingTranscriptChunk],
        language: MeetingLanguage
    ) async -> [String] {
        // Only generate once there's enough transcript to anchor real questions.
        // Less than ~30 seconds of speech yields generic suggestions, so we
        // wait for substance.
        guard transcript.count >= 4 else {
            return Self.defaultStarterQuestions
        }

        let window = Array(transcript.suffix(40))

        if let bot = await cachedQwenIfAvailable() {
            let prompt = MeetingPromptBuilder(language: language)
                .suggestedQuestionsPrompt(for: window)
            do {
                let raw = try await bot.generate(prompt: prompt)
                let parsed = Self.parseSuggestedQuestions(raw)
                if !parsed.isEmpty {
                    return parsed
                }
            } catch {
                logger.warning("Suggested questions generation failed: \(error.localizedDescription)")
            }
        }

        return Self.defaultStarterQuestions
    }

    /// Generic prompts shown before the AI has had a chance to read enough
    /// transcript. Broadened beyond business-meeting vocabulary so sermons,
    /// lectures, podcasts, and conversations land on something useful too.
    nonisolated static let defaultStarterQuestions: [String] = [
        "What is this about?",
        "What were the main points?",
        "Is there anything I should follow up on?",
        "What stood out the most?"
    ]

    // MARK: - Private

    private func qwenCacheDirectory() -> URL {
        MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: modelsRoot
        )
    }

    private func cachedQwenIfAvailable() async -> QwenLocalLLM? {
        do {
            let loaded = try await QwenLocalLLM.shared.ensureLoadedFromCache(
                cacheDirectory: qwenCacheDirectory()
            )
            return loaded ? QwenLocalLLM.shared : nil
        } catch {
            logger.warning("Cached Qwen Q&A load failed, using fallback: \(error.localizedDescription)")
            return nil
        }
    }

    private func relevantChunks(
        for question: String,
        in transcript: [MeetingTranscriptChunk],
        isOverviewQuestion: Bool,
        isFollowUp: Bool,
        previousQuestion: MeetingQuestion?
    ) -> [MeetingTranscriptChunk] {
        // Overview questions and follow-ups both need more breadth than
        // keyword-matched chunks alone provide. For overviews we pull a wider
        // tail of the transcript; for follow-ups we combine the previous
        // question's citations with the recent tail so the model can expand
        // on what was just discussed without losing the thread.
        if isOverviewQuestion {
            return Array(transcript.suffix(14))
        }
        if isFollowUp {
            let previousChunkIDs = Set((previousQuestion?.citations ?? []).map(\.chunkID))
            let previousChunks = transcript.filter { previousChunkIDs.contains($0.chunkID) }
            let recentTail = Array(transcript.suffix(10))
            var combined: [MeetingTranscriptChunk] = []
            var seen: Set<UUID> = []
            for chunk in previousChunks + recentTail {
                if seen.insert(chunk.chunkID).inserted {
                    combined.append(chunk)
                }
            }
            return combined
        }
        return chunker.mostRelevantChunks(
            for: question,
            in: transcript,
            maxChunks: 8
        )
    }

    private func fallbackAnswer(
        for question: String,
        using relevant: [MeetingTranscriptChunk],
        isOverviewQuestion: Bool
    ) -> String {
        guard let best = relevant.first else {
            return L10n.string(
                "meeting.qa.answer.noEvidence",
                default: "I couldn't find that in the transcript. Try asking about something the speaker has already said."
            )
        }
        if isOverviewQuestion {
            let snippets = relevant
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(4)
                .joined(separator: " ")
            return "Recently the discussion has covered: \(snippets)"
        }
        return "Based on what was said at \(best.formattedTimestamp): \(best.text)"
    }

    nonisolated static func isGreeting(_ question: String) -> Bool {
        let normalized = question
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["hi", "hello", "hey", "yo"].contains(normalized)
    }

    nonisolated static func isOverviewQuestion(_ question: String) -> Bool {
        let normalized = question.lowercased()
        let overviewPhrases = [
            "what is being discussed",
            "whats being discussed",
            "what's being discussed",
            "what was discussed",
            "what's discussed",
            "what was being discussed",
            "what are they discussing",
            "what are they talking about",
            "what is this meeting about",
            "what's this meeting about",
            "what is this about",
            "what's this about",
            "what is going on",
            "what's going on",
            "summarize",
            "summary so far",
            "catch me up",
            "main points",
            "key points",
            "what stood out",
            "tldr",
            "tl;dr",
            "recap"
        ]
        return overviewPhrases.contains { normalized.contains($0) }
    }

    /// Detects questions that should be treated as "expand on the previous
    /// answer" — phrases like "more details", "tell me more", "explain that".
    /// These need the previous question's citations re-injected into context,
    /// not a fresh keyword search.
    nonisolated static func isFollowUpQuestion(_ question: String) -> Bool {
        let normalized = question.lowercased()
        let followUpPhrases = [
            "more detail",
            "more details",
            "more detials", // common typo
            "tell me more",
            "in more detail",
            "in detail",
            "in detial", // common typo
            "expand",
            "explain that",
            "explain more",
            "elaborate",
            "go deeper",
            "say more",
            "what else"
        ]
        return followUpPhrases.contains { normalized.contains($0) }
    }

    nonisolated static func parseSuggestedQuestions(_ raw: String) -> [String] {
        // The model is asked to return a JSON array of strings. Be forgiving:
        // pull the first `[...]` block and decode that. If decoding fails we
        // try a line-based fallback so prose responses still yield questions.
        if let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]") {
            let jsonSlice = String(raw[start...end])
            if let data = jsonSlice.data(using: .utf8),
               let array = try? JSONDecoder().decode([String].self, from: data) {
                let cleaned = array
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !cleaned.isEmpty {
                    return Array(cleaned.prefix(4))
                }
            }
        }
        // Fallback: split on newlines, strip leading bullets/numbers, keep
        // anything that looks like a question.
        let lines = raw.split(whereSeparator: { $0.isNewline })
        let candidates = lines.compactMap { line -> String? in
            let trimmed = line
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*•0123456789.)"))
                .trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 4 else { return nil }
            return trimmed
        }
        return Array(candidates.prefix(4))
    }
}
