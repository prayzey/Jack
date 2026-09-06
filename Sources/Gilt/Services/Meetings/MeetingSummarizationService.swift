import Foundation
import OSLog

/// Generates summaries, decisions, action items, and follow-up questions by
/// prompting a locally-loaded Qwen 3 4B model (via `QwenLocalLLM`). Falls back
/// to a deterministic heuristic extractor if the model fails to load or
/// returns malformed JSON, so the UI still shows something useful.
@MainActor
final class MeetingSummarizationService {
    private let modelsRoot: URL
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingSummary")
    private let chunker = MeetingTranscriptChunker()

    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    var summaryEngineID: MeetingSummarizationEngine { .qwen35_4b_q4 }

    func summarize(
        transcript: [MeetingTranscriptChunk],
        previousSummary: MeetingSummary?,
        meetingID: UUID,
        language: MeetingLanguage
    ) async throws -> MeetingSummary {
        guard !transcript.isEmpty else {
            return previousSummary ?? MeetingSummary(meetingID: meetingID)
        }

        // Prefer Apple's on-device model (macOS 26 + Apple Intelligence) when the user has opted in
        // and it can run. When it's the chosen engine we skip Qwen entirely — that's the whole point,
        // no multi-gigabyte download or load. The deterministic heuristics remain the safety net.
        // Resolved through MeetingSummarizationChoice so this stays in lockstep with the
        // engine picker in MeetingModelSettingsView.
        let useAppleModel = MeetingSummarizationChoice.effective(
            preferApple: AppSettings.currentPersisted().aiMeetingPreferAppleModel,
            appleUsable: OnDeviceAIService.shared.isUsable
        ) == .appleIntelligence

        // Use Qwen when it is loaded or already cached on disk. This makes
        // summary regeneration actually use local AI after an app relaunch,
        // without silently starting the multi-gigabyte first download.
        let bot = useAppleModel ? nil : await cachedQwenIfAvailable()

        let promptBuilder = MeetingPromptBuilder(language: language)
        let windows = chunker.windows(from: transcript)

        var rollingNotes = previousSummary?.rollingNotes ?? ""
        var bullets: [String] = []
        var decisions: [MeetingDecision] = previousSummary?.decisions ?? []
        var actionItems: [MeetingActionItem] = previousSummary?.actionItems ?? []
        var followUps: [MeetingFollowUpQuestion] = previousSummary?.followUpQuestions ?? []
        var headline = previousSummary?.headline ?? ""

        for window in windows {
            var handled = false

            // Try Apple's on-device model first when it's the chosen engine. Guided generation gives
            // us a structured draft directly, so there's no JSON parsing to fail on.
            if useAppleModel, #available(macOS 26.0, *) {
                do {
                    let parsed = try await appleSummaryDraft(for: window, rollingNotes: rollingNotes)
                    mergeParsed(
                        parsed,
                        window: window,
                        headline: &headline,
                        bullets: &bullets,
                        decisions: &decisions,
                        actionItems: &actionItems,
                        followUps: &followUps
                    )
                    handled = true
                } catch {
                    logger.warning("Apple model summarize failed for window, falling back: \(error.localizedDescription)")
                }
            }

            if !handled {
                let prompt = promptBuilder.summaryPrompt(
                    for: window,
                    previousNotes: rollingNotes.isEmpty ? nil : rollingNotes
                )
                if let bot {
                    do {
                        let raw = try await bot.generate(prompt: prompt)
                        if let parsed = MeetingSummaryJSON.parse(raw) {
                            mergeParsed(
                                parsed,
                                window: window,
                                headline: &headline,
                                bullets: &bullets,
                                decisions: &decisions,
                                actionItems: &actionItems,
                                followUps: &followUps
                            )
                        } else {
                            applyHeuristics(
                                to: window,
                                bullets: &bullets,
                                decisions: &decisions,
                                actionItems: &actionItems,
                                followUps: &followUps
                            )
                        }
                    } catch {
                        logger.warning("LLM summarize failed, using heuristics: \(error.localizedDescription)")
                        applyHeuristics(
                            to: window,
                            bullets: &bullets,
                            decisions: &decisions,
                            actionItems: &actionItems,
                            followUps: &followUps
                        )
                    }
                } else {
                    applyHeuristics(
                        to: window,
                        bullets: &bullets,
                        decisions: &decisions,
                        actionItems: &actionItems,
                        followUps: &followUps
                    )
                }
            }

            if let last = window.last {
                let line = "• [\(last.formattedTimestamp)] \(last.text)"
                rollingNotes = (rollingNotes + "\n" + line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if headline.isEmpty {
            if let first = transcript.first?.text.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
                let truncated = String(first.prefix(80))
                headline = first.count > 80 ? truncated + "…" : truncated
            } else {
                headline = L10n.string("meeting.summary.untitled", default: "Meeting summary")
            }
        }

        if bullets.isEmpty {
            bullets = transcript.prefix(5).map(\.text)
        }

        return MeetingSummary(
            meetingID: meetingID,
            headline: headline,
            bullets: bullets,
            decisions: decisions,
            actionItems: actionItems,
            followUpQuestions: followUps,
            rollingNotes: rollingNotes,
            lastUpdatedAt: Date()
        )
    }

    // MARK: - Private helpers

    /// Summarize one transcript window with Apple's on-device model via guided generation.
    @available(macOS 26.0, *)
    private func appleSummaryDraft(
        for window: [MeetingTranscriptChunk],
        rollingNotes: String
    ) async throws -> MeetingSummaryJSON {
        let transcriptText = window
            .map { "[\($0.formattedTimestamp)] \($0.text)" }
            .joined(separator: "\n")
        let instruction = "You summarize meeting transcripts. Be concise and faithful, and only include items the text actually supports. Use the transcript's language."
        let prompt: String
        if rollingNotes.isEmpty {
            prompt = "Summarize this meeting transcript:\n\n\(transcriptText)"
        } else {
            prompt = "Earlier notes:\n\(rollingNotes)\n\nNow summarize this new part of the meeting, building on the earlier notes:\n\n\(transcriptText)"
        }
        let draft = try await OnDeviceAIService.shared.respond(
            instructions: instruction,
            to: prompt,
            generating: AIMeetingSummaryDraft.self
        )
        return MeetingSummaryJSON(
            headline: draft.headline,
            bullets: draft.bullets,
            decisions: draft.decisions,
            actionItems: draft.actionItems,
            followUpQuestions: draft.followUps
        )
    }

    /// Merge one window's parsed summary into the running accumulators. Shared by the Apple and
    /// Qwen paths so both produce identical `MeetingSummary` shapes.
    private func mergeParsed(
        _ parsed: MeetingSummaryJSON,
        window: [MeetingTranscriptChunk],
        headline: inout String,
        bullets: inout [String],
        decisions: inout [MeetingDecision],
        actionItems: inout [MeetingActionItem],
        followUps: inout [MeetingFollowUpQuestion]
    ) {
        if headline.isEmpty, !parsed.headline.isEmpty {
            headline = parsed.headline
        }
        bullets.append(contentsOf: parsed.bullets)
        let sourceIDs = window.map { $0.chunkID }
        for decision in parsed.decisions {
            decisions.appendIfNew(MeetingDecision(text: decision, sourceChunkIDs: sourceIDs))
        }
        for action in parsed.actionItems {
            actionItems.appendIfNew(MeetingActionItem(text: action, sourceChunkIDs: sourceIDs))
        }
        for question in parsed.followUpQuestions {
            followUps.appendIfNew(MeetingFollowUpQuestion(text: question, sourceChunkIDs: sourceIDs))
        }
    }

    private func qwenCacheDirectory() -> URL {
        MeetingAppSupportLocator.summarizationModelFolder(
            engine: summaryEngineID,
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
            logger.warning("Cached Qwen load failed, using heuristics: \(error.localizedDescription)")
            return nil
        }
    }

    private func applyHeuristics(
        to window: [MeetingTranscriptChunk],
        bullets: inout [String],
        decisions: inout [MeetingDecision],
        actionItems: inout [MeetingActionItem],
        followUps: inout [MeetingFollowUpQuestion]
    ) {
        for chunk in window {
            let line = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if MeetingHeuristics.looksLikeDecision(line) {
                decisions.appendIfNew(MeetingDecision(text: line, sourceChunkIDs: [chunk.chunkID]))
            }
            if MeetingHeuristics.looksLikeActionItem(line) {
                actionItems.appendIfNew(MeetingActionItem(text: line, sourceChunkIDs: [chunk.chunkID]))
            }
            if MeetingHeuristics.looksLikeFollowUp(line) {
                followUps.appendIfNew(MeetingFollowUpQuestion(text: line, sourceChunkIDs: [chunk.chunkID]))
            }
        }
    }
}

/// JSON shape that we ask the LLM to emit. Kept tolerant: missing fields
/// default to empty arrays, and we strip ``` fences and prose around the JSON
/// object so the model has some wiggle room.
struct MeetingSummaryJSON: Decodable {
    let headline: String
    let bullets: [String]
    let decisions: [String]
    let actionItems: [String]
    let followUpQuestions: [String]

    init(
        headline: String = "",
        bullets: [String] = [],
        decisions: [String] = [],
        actionItems: [String] = [],
        followUpQuestions: [String] = []
    ) {
        self.headline = headline
        self.bullets = bullets
        self.decisions = decisions
        self.actionItems = actionItems
        self.followUpQuestions = followUpQuestions
    }

    enum CodingKeys: String, CodingKey {
        case headline, bullets, decisions, actionItems, followUpQuestions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.headline = (try? container.decodeIfPresent(String.self, forKey: .headline)) ?? ""
        self.bullets = (try? container.decodeIfPresent([String].self, forKey: .bullets)) ?? []
        self.decisions = (try? container.decodeIfPresent([String].self, forKey: .decisions)) ?? []
        self.actionItems = (try? container.decodeIfPresent([String].self, forKey: .actionItems)) ?? []
        self.followUpQuestions = (try? container.decodeIfPresent([String].self, forKey: .followUpQuestions)) ?? []
    }

    static func parse(_ raw: String) -> MeetingSummaryJSON? {
        // Locate the outermost JSON object inside the model's response.
        guard let start = raw.firstIndex(of: "{") else { return nil }
        guard let end = raw.lastIndex(of: "}") else { return nil }
        let jsonString = String(raw[start...end])
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeetingSummaryJSON.self, from: data)
    }
}

enum MeetingHeuristics {
    static func looksLikeDecision(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "we decided", "we'll go with", "we will go with",
            "let's go with", "decision is", "agreed to", "the call is"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }

    static func looksLikeActionItem(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "action item", "todo", "to-do", "follow up with",
            "send the", "draft the", "share the", "will own", "owns the"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }

    static func looksLikeFollowUp(_ text: String) -> Bool {
        let lower = text.lowercased()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["open question", "question:", "what about", "how do we", "we still need"]
        if trimmed.hasSuffix("?") { return true }
        return prefixes.contains(where: { lower.contains($0) })
    }
}

extension Array where Element == MeetingDecision {
    mutating func appendIfNew(_ item: MeetingDecision) {
        if !contains(where: { $0.text == item.text }) { append(item) }
    }
}

extension Array where Element == MeetingActionItem {
    mutating func appendIfNew(_ item: MeetingActionItem) {
        if !contains(where: { $0.text == item.text }) { append(item) }
    }
}

extension Array where Element == MeetingFollowUpQuestion {
    mutating func appendIfNew(_ item: MeetingFollowUpQuestion) {
        if !contains(where: { $0.text == item.text }) { append(item) }
    }
}
