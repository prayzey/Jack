import Foundation
import OSLog

/// Aqua-style live polish: while the user is still speaking, re-polishes the
/// completed-sentence prefix of the streaming transcript so the overlay text
/// visibly heals ("I need tomatoes. Oops, I mean onions." → "I need onions.").
///
/// Contract with `DictationCoordinator`:
///   - `ingest(_:)` on every cumulative streaming chunk. Schedules a polish
///     pass whenever a new sentence boundary lands in the stable region.
///   - `compose(cumulativeRaw:)` builds the caption state: polished prefix +
///     the raw not-yet-polished suffix (cleaned the same way live captions are).
///   - `finishSession()` drains the in-flight pass before the final pipeline
///     runs — `QwenLocalLLM` must never see two concurrent `respond` calls.
///   - `finalResult(matching:)` hands back the polished text when it already
///     covers the exact final transcript, letting the coordinator skip the
///     end-of-session Qwen pass entirely.
///
/// Each pass re-polishes the WHOLE completed prefix, not just the newest
/// sentence — that's what lets a spoken correction reach back and rewrite the
/// previous sentence. Passes are serialized with drop-intermediate: while one
/// runs, only the newest boundary is remembered.
@MainActor
final class LiveDictationPolisher {
    /// ponytail: whole-prefix re-polish is O(n) per sentence boundary, so cap
    /// live polish at ~900 chars; past that the end-of-session pass (which
    /// runs regardless) covers everything. Suffix-only passes with a locked
    /// prefix are the upgrade path if long dictations need live healing.
    static let maxLiveChars = 900

    /// Mirrors steps 5–7 of the coordinator's final pipeline (vocab →
    /// pre-clean → filler cleanup) so a live-polished prefix is byte-equal
    /// to what the final pass would have fed the model for the same raw text.
    private let prepare: @MainActor (String) -> String
    /// The model pass for one prefix — Qwen on machines with headroom, the
    /// Apple Intelligence system model on 8 GB Macs. Must return its input
    /// unchanged on failure (both engines already do).
    private let polishChunk: @MainActor (String) async -> String
    /// Fired after a pass lands so the coordinator can re-publish the caption.
    var onUpdate: (@MainActor () -> Void)?

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "LiveDictationPolish")

    private(set) var polishedRawPrefix = ""
    private(set) var polishedText = ""
    private var lastPolishedInput = ""
    private var scheduledRawPrefix = ""
    private var polishTask: Task<Void, Never>?
    private var pendingRawPrefix: String?

    init(
        prepare: @escaping @MainActor (String) -> String,
        polishChunk: @escaping @MainActor (String) async -> String
    ) {
        self.prepare = prepare
        self.polishChunk = polishChunk
    }

    // MARK: - Streaming input

    func ingest(_ cumulativeRaw: String) {
        let scheduledWords = LiveCaptionComposer.wordCount(scheduledRawPrefix)
        guard let prefix = Self.polishablePrefix(
            in: Self.normalizeWhitespace(cumulativeRaw),
            lastPrefixWordCount: scheduledWords
        ) else { return }
        guard prefix.count <= Self.maxLiveChars else { return }
        // Committed text only grows, so a same-or-shorter prefix means no new
        // boundary since the last scheduled pass.
        guard prefix.count > scheduledRawPrefix.count else { return }
        scheduledRawPrefix = prefix
        schedule(prefix)
    }

    private func schedule(_ rawPrefix: String) {
        if polishTask != nil {
            pendingRawPrefix = rawPrefix
            return
        }
        polishTask = Task { [weak self] in
            await self?.runPolish(rawPrefix)
            guard let self else { return }
            self.polishTask = nil
            if let pending = self.pendingRawPrefix {
                self.pendingRawPrefix = nil
                self.schedule(pending)
            }
        }
    }

    private func runPolish(_ rawPrefix: String) async {
        let input = prepare(rawPrefix)
        guard !input.isEmpty else { return }
        let started = Date()
        MeetingDownloadLog.log("[live-polish] pass start — \(LiveCaptionComposer.wordCount(input)) words")
        let output = await polishChunk(input)
        guard !Task.isCancelled else { return }
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        MeetingDownloadLog.log("[live-polish] pass landed in \(elapsed)s — changed=\(output != input)")
        polishedRawPrefix = rawPrefix
        polishedText = output
        lastPolishedInput = input
        onUpdate?()
    }

    // MARK: - Caption composition

    /// Polished prefix + cleaned raw suffix, or nil when there's nothing
    /// polished yet (caller falls back to the plain live caption).
    func compose(cumulativeRaw: String) -> LiveCaptionComposer.State? {
        guard !polishedText.isEmpty else { return nil }
        // Normalize before the prefix check — the ASR helper joins committed
        // and tentative segments with raw token spacing, so the cumulative
        // text can carry double spaces that would silently break hasPrefix
        // against the space-joined prefix and hide every live heal.
        let trimmed = Self.normalizeWhitespace(cumulativeRaw)
        // Committed ASR text never changes, so the polished raw prefix should
        // always still lead the cumulative text. If it somehow doesn't,
        // showing the plain raw caption is the safe fallback.
        guard trimmed.hasPrefix(polishedRawPrefix) else {
            MeetingDownloadLog.log("[live-polish] compose prefix mismatch — heal not shown")
            return nil
        }
        let suffixRaw = String(trimmed.dropFirst(polishedRawPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = suffixRaw.isEmpty ? "" : TranscriptCleaner.clean(suffixRaw)
        let text = suffix.isEmpty ? polishedText : polishedText + " " + suffix
        // Everything renders sharp — the tentative-tail distinction is an
        // internal safety line for the polisher, not a visual treatment.
        return LiveCaptionComposer.State(
            text: text,
            stableWordCount: LiveCaptionComposer.wordCount(text)
        )
    }

    // MARK: - Session end

    /// Await the in-flight pass (dropping any queued one). Must run before
    /// the coordinator's final Qwen pass — the shared `QwenLocalLLM` cannot
    /// serve two `respond` calls at once.
    func finishSession() async {
        pendingRawPrefix = nil
        if let task = polishTask {
            await task.value
        }
    }

    /// The polished text, but only when the live pass already covered the
    /// exact prepared final transcript (the user paused before releasing the
    /// key). The coordinator then skips the final Qwen pass — that's the
    /// paste-latency win.
    func finalResult(matching preparedFinalInput: String) -> String? {
        guard !polishedText.isEmpty, preparedFinalInput == lastPolishedInput else { return nil }
        return polishedText
    }

    func cancel() {
        pendingRawPrefix = nil
        polishTask?.cancel()
        polishTask = nil
    }

    /// Collapse runs of whitespace to single spaces. Both the boundary
    /// prefixes and the compose-time prefix check operate on this normalized
    /// form so token-level spacing quirks from the ASR can never desync them.
    static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Boundary detection

    /// New stable words required to trigger a pass when the ASR emits no
    /// punctuation (the unified Parakeet stream mostly doesn't mid-stream).
    /// 6 words ≈ a pass every ~2.5s of speech; each warm pass costs ~1s, so
    /// the polisher keeps up. 12 was too coarse — a short dictation ended
    /// before the correction ever entered a pass.
    static let fallbackBoundaryWords = 6

    /// Correction chatter entering the stable region schedules a pass
    /// immediately, without waiting for the word-count boundary — healing the
    /// caption right after "actually, I meant…" is the whole feature. False
    /// positives (a plain "actually") just cost one cheap no-op pass.
    private static let correctionMarkers = [
        "wait no", "no sorry", "i meant", "i mean", "actually",
        "scratch that", "didn't mean", "no wait"
    ]

    /// The prefix of `cumulative` that's safe to polish, bounded to the
    /// stable region (everything except the last two words, which the
    /// streaming model still treats as tentative).
    ///
    /// Preferred boundary: the last sentence terminator in the stable region.
    /// Fallback: the whole stable region, once it has grown at least
    /// `fallbackBoundaryWords` past the previously scheduled prefix — the
    /// streaming ASR emits little punctuation, so waiting for a period means
    /// never polishing at all. Mid-sentence cuts are safe because every pass
    /// re-polishes the whole prefix; a later pass heals the seam.
    static func polishablePrefix(in cumulative: String, lastPrefixWordCount: Int) -> String? {
        let trimmed = cumulative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count > 2 else { return nil }
        let stable = words.dropLast(2).joined(separator: " ")

        if let idx = stable.lastIndex(where: { ".!?".contains($0) }) {
            let prefix = String(stable[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            // One- or two-word "sentences" are usually mis-punctuated
            // fragments — polishing them buys nothing and burns a pass.
            if LiveCaptionComposer.wordCount(prefix) >= 3 {
                // Only prefer the terminator boundary while it still moves
                // the prefix forward; otherwise fall through to the
                // word-count rule so one early period doesn't stall passes
                // for the rest of an unpunctuated dictation.
                if LiveCaptionComposer.wordCount(prefix) > lastPrefixWordCount {
                    return prefix
                }
            }
        }

        let stableWords = words.count - 2
        guard stableWords > lastPrefixWordCount else { return nil }
        if stableWords - lastPrefixWordCount >= fallbackBoundaryWords {
            return stable
        }
        // Look a few words back across the boundary so a marker that
        // straddles it ("…tomatoes wait | no I meant…") still matches.
        let tail = words.dropLast(2)
            .dropFirst(max(0, lastPrefixWordCount - 3))
            .joined(separator: " ")
            .lowercased()
        if correctionMarkers.contains(where: { tail.contains($0) }) {
            return stable
        }
        return nil
    }
}
