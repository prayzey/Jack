import AppKit
import Foundation
import OSLog

/// Watches what the user does to a freshly-pasted dictation and asks Qwen
/// whether they corrected the AI's mistakes. Successful corrections land in
/// `CorrectionStore` for future dictations to benefit from.
///
/// **Architecture sketch**
///   1. `DictationCoordinator` finishes a polish-mode paste.
///   2. It calls `startWatching(...)` with the pasted text + target app pid.
///   3. We spawn one background `Task` per paste — multiple concurrent
///      watches are fine, they each own their own state.
///   4. The task polls `AXFocusedElementReader` every ~1s, keeping the most
///      recent value. It stops on the first of:
///         - The target app stops being frontmost (user switched away).
///         - Jack itself becomes frontmost (the dictation pill returning).
///         - The poll has run for `maxWatchSeconds` total.
///         - The focused element disappears (window closed).
///   5. After the watch ends, if the final field state diverged from the
///      pasted text by a non-trivial amount, hand both strings to Qwen with
///      a strict JSON-output prompt. Qwen replies with either `[]` or an
///      array of `{original, corrected}` pairs.
///   6. Each accepted pair is forwarded to `CorrectionStore`.
///
/// **Why Qwen instead of a hand-written diff**
/// A character-level diff can't tell "user fixed a misspelling" from "user
/// kept typing the next sentence." The Qwen prompt explicitly asks the model
/// to make that distinction, which sidesteps a whole category of false
/// positives that would otherwise pollute the learned vocabulary.
@MainActor
final class CorrectionLearner {
    // Per-paste tuning constants. Inlined — nothing ever constructed a
    // non-default configuration; reintroduce an injectable Tuning struct if
    // a tuning UI or test needs to vary these.
    /// How often the watch task reads the AX value. 1s is a good
    /// balance: snappy enough to catch quick edits, slow enough to
    /// stay invisible to the system load monitor.
    private let pollInterval: TimeInterval = 1.0
    /// Hard ceiling on how long any single watch task lives. After
    /// this the task gives up regardless of whether the user is
    /// still in the field — protects against pathological cases
    /// (user walks away from the computer mid-edit).
    private let maxWatchSeconds: TimeInterval = 60
    /// Minimum edit distance (in characters) below which we don't
    /// bother calling Qwen — saves a model round-trip when the user
    /// didn't actually change anything material.
    private let minEditDistanceForClassify: Int = 1

    /// Public so other services (e.g. a future "test classifier" debug
    /// button) can reuse the same prompt-and-parse path. The store stays
    /// independent; CorrectionLearner just dispatches into it.
    let store: CorrectionStore

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "CorrectionLearner")
    private let cacheDirectory: URL
    private var activeWatches: [UUID: Task<Void, Never>] = [:]

    init(
        store: CorrectionStore,
        cacheDirectory: URL
    ) {
        self.store = store
        self.cacheDirectory = cacheDirectory
    }

    deinit {
        for task in activeWatches.values {
            task.cancel()
        }
    }

    // MARK: - Public

    /// Begin watching the target app for edits to the just-pasted text.
    /// Fire-and-forget — the coordinator doesn't await this.
    func startWatching(
        pastedText: String,
        targetAppPID: pid_t?,
        targetAppName: String?,
        targetAppBundleID: String?
    ) {
        guard let pid = targetAppPID else {
            logger.debug("Correction watch skipped — no target pid")
            return
        }
        let trimmedPaste = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPaste.isEmpty else { return }

        let watchID = UUID()
        // Explicit return type so the closure stays `Task<Void, Never>` even
        // with the weak-self optional chain — otherwise Swift infers `()?`
        // and the dictionary type mismatches.
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runWatch(
                watchID: watchID,
                pastedText: trimmedPaste,
                targetPID: pid,
                targetAppName: targetAppName,
                targetAppBundleID: targetAppBundleID
            )
        }
        activeWatches[watchID] = task
    }

    /// Cancel every active watch — used when the user disables the
    /// feature or the app is about to quit.
    func cancelAllWatches() {
        for (id, task) in activeWatches {
            task.cancel()
            activeWatches[id] = nil
        }
    }

    // MARK: - Watch loop

    private func runWatch(
        watchID: UUID,
        pastedText: String,
        targetPID: pid_t,
        targetAppName: String?,
        targetAppBundleID: String?
    ) async {
        defer { activeWatches[watchID] = nil }

        let startedAt = Date()
        var lastObservedValue: String?
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""

        // Small delay before the first read so the app actually has the
        // pasted text rendered in its AX tree. Pasting is synchronous-ish
        // but the AX cache lags by a few hundred ms in some apps.
        try? await Task.sleep(nanoseconds: 600_000_000)
        if Task.isCancelled { return }

        while !Task.isCancelled {
            // Stop conditions are checked at the top of each loop.
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed >= maxWatchSeconds { break }

            // If the user has moved on — different app frontmost, or Jack
            // has come back to the front (e.g. they triggered another
            // dictation) — capture once more and break out.
            let frontmost = NSWorkspace.shared.frontmostApplication
            let frontmostPID = frontmost?.processIdentifier
            let frontmostBundle = frontmost?.bundleIdentifier ?? ""
            let weAreFrontmost = frontmostBundle == ownBundleID
            let targetMovedOn = frontmostPID != nil && frontmostPID != targetPID
            if weAreFrontmost || targetMovedOn {
                if let final = readValue(pid: targetPID) {
                    lastObservedValue = final
                }
                break
            }

            if let value = readValue(pid: targetPID) {
                lastObservedValue = value
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        guard let final = lastObservedValue else {
            logger.debug("Correction watch ended — never observed a value")
            return
        }

        await maybeClassifyAndLearn(
            pastedText: pastedText,
            finalText: final,
            targetAppName: targetAppName,
            targetAppBundleID: targetAppBundleID
        )
    }

    /// Bridge from the main actor to the AX read. Returns the string value
    /// or nil for any of the "not text we can use" cases.
    nonisolated private func readValue(pid: pid_t) -> String? {
        switch AXFocusedElementReader.readFocusedTextValue(pid: pid) {
        case .success(let str): return str
        case .noFocusedElement, .unsupportedValueType: return nil
        }
    }

    // MARK: - Classifier

    private func maybeClassifyAndLearn(
        pastedText: String,
        finalText: String,
        targetAppName: String?,
        targetAppBundleID: String?
    ) async {
        let pasteClean = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalClean = finalText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cheap pre-filters: identical strings or empty final → nothing to
        // do, save the Qwen round-trip.
        guard !finalClean.isEmpty else { return }
        if pasteClean.caseInsensitiveCompare(finalClean) == .orderedSame { return }
        let distance = Self.editDistance(pasteClean, finalClean)
        if distance < minEditDistanceForClassify { return }

        // Qwen has to be loaded; we don't kick off a multi-GB download
        // from a side-effect of typing in another app.
        let llm = QwenLocalLLM.shared
        do {
            let ready = try await llm.ensureLoadedFromCache(cacheDirectory: cacheDirectory)
            guard ready else {
                logger.info("Correction classify skipped — Qwen not cached")
                return
            }
        } catch {
            logger.error("Correction classify skipped — Qwen cache check failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let prompt = Self.makePrompt(pasted: pasteClean, final: finalClean)
        let response: String
        do {
            response = try await llm.generate(prompt: prompt)
        } catch {
            logger.error("Correction classify Qwen call failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let pairs = Self.parseCorrections(from: response)
        guard !pairs.isEmpty else {
            logger.debug("Correction classify: no learnable corrections in response")
            return
        }

        for pair in pairs {
            store.recordCorrection(
                original: pair.original,
                corrected: pair.corrected,
                sourceAppName: targetAppName,
                sourceAppBundleID: targetAppBundleID
            )
        }
    }

    // MARK: - Prompt + parse

    /// Bare-bones edit distance, capped at one row of dynamic-programming
    /// allocation so a million-character difference doesn't blow memory.
    /// Used only as a coarse pre-filter — when distance is 0 or 1 we
    /// don't bother asking Qwen.
    nonisolated private static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[bChars.count]
    }

    /// Strict-JSON prompt. Qwen 4B is small and will happily ramble if you
    /// let it — every line of this prompt exists to keep the output
    /// parseable. "Output ONLY the JSON array" is the most important rule
    /// here; the parse step below is forgiving but not magic.
    nonisolated private static func makePrompt(pasted: String, final: String) -> String {
        """
        You are analyzing the difference between text that was dictated for a user and the user's final version of that text in their editor. Your job: decide whether the user CORRECTED the dictation, and if so, extract specific word-level substitutions.

        Count as a CORRECTION:
        - A misspelled word fixed: "useeffect" -> "useEffect"
        - A misheard proper noun fixed: "Adasokan" -> "Adesokan"
        - A capitalization fix on a term: "api" -> "API"
        - A short multi-word name fixed: "praise adesokan" -> "Praise Adesokan"

        Do NOT count as a correction:
        - The user added new sentences after the dictated text.
        - The user rewrote the text in a different style or tone.
        - The user deleted the dictation and wrote something unrelated.
        - Generic style edits ("I will" -> "I'll").
        - Adding or removing punctuation alone.

        DICTATED TEXT:
        \(pasted)

        USER'S FINAL VERSION:
        \(final)

        Output ONLY a JSON array. Each item is a JSON object with exactly two string fields: "original" (the wrong form) and "corrected" (the user's fixed form). If there are no real corrections, output the literal `[]`. No prose, no markdown, no code fences, no commentary — only the JSON.
        """
    }

    /// Forgiving JSON parser. Qwen sometimes wraps its output in markdown
    /// fences or adds a "Here is the JSON:" preamble despite being told
    /// not to. We strip whatever scaffolding we can find and try to
    /// recover the array.
    nonisolated static func parseCorrections(from raw: String) -> [(original: String, corrected: String)] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip the most common preambles.
        for prefix in ["Here is the JSON:", "Here is the array:", "JSON:", "Output:", "Result:"] {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip ``` fences.
        if s.hasPrefix("```") {
            s = String(s.dropFirst(3))
            if s.lowercased().hasPrefix("json") {
                s = String(s.dropFirst(4))
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let end = s.range(of: "```") {
                s = String(s[..<end.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // If there's any prose before the first `[` and after the last `]`,
        // slice down to the array region. Qwen 4B does this often.
        if let openIdx = s.firstIndex(of: "["),
           let closeIdx = s.lastIndex(of: "]"),
           openIdx < closeIdx {
            s = String(s[openIdx...closeIdx])
        }

        guard let data = s.data(using: .utf8) else { return [] }

        struct RawPair: Decodable {
            let original: String
            let corrected: String
        }
        guard let pairs = try? JSONDecoder().decode([RawPair].self, from: data) else {
            return []
        }
        return pairs.map { (original: $0.original, corrected: $0.corrected) }
    }
}
