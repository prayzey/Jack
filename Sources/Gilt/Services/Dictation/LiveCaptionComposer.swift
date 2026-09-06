import Foundation

/// Builds the listening-phase caption: merges streaming ASR chunks, tracks which
/// words are stable vs still provisional, and applies cheap Fluid-style cleanup
/// (fillers + vocab) without running SmartFormatter or Qwen live.
enum LiveCaptionComposer {
    struct State: Equatable {
        var text: String
        /// Words at the start of `text` that are treated as confirmed for display.
        var stableWordCount: Int
    }

    // MARK: - Merge

    /// Windowed Parakeet v2 preview — sequential time slices with overlap dedupe.
    static func mergeWindowed(
        accumulated: String,
        previousWindow: String,
        currentWindow: String
    ) -> State {
        guard !currentWindow.isEmpty else {
            return State(text: accumulated, stableWordCount: wordCount(accumulated))
        }
        if accumulated.isEmpty {
            return State(text: currentWindow, stableWordCount: 0)
        }

        let prevWords = previousWindow.split(separator: " ").map(String.init)
        let currWords = currentWindow.split(separator: " ").map(String.init)
        guard !currWords.isEmpty else {
            return State(text: accumulated, stableWordCount: wordCount(accumulated))
        }

        let stableBefore = wordCount(accumulated)

        if previousWindow.isEmpty {
            return State(
                text: accumulated + " " + currentWindow,
                stableWordCount: stableBefore
            )
        }

        var overlap = 0
        for i in 0..<min(prevWords.count, currWords.count) {
            let a = prevWords[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let b = currWords[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if a == b {
                overlap = i + 1
            } else {
                break
            }
        }

        if overlap > prevWords.count / 2, overlap < currWords.count {
            let delta = currWords[overlap...].joined(separator: " ")
            return State(
                text: accumulated + " " + delta,
                stableWordCount: stableBefore
            )
        }

        return State(
            text: accumulated + " " + currentWindow,
            stableWordCount: stableBefore
        )
    }

    // MARK: - Live cleanup

    @MainActor
    static func buildWeightedTerms(
        settings: DictationSettings,
        correctionStore: CorrectionStore?,
        screenTerms: [String]
    ) -> [VocabularyMatcher.WeightedTerm] {
        let packTerms = settings.enabledVocabPacks.flatMap { settings.effectiveTerms(for: $0) }
        let learnedTerms = correctionStore?.topCorrectedTerms(limit: 30) ?? []

        var weightedTerms: [VocabularyMatcher.WeightedTerm] = settings
            .weightedCustomVocabulary()
            .map {
                VocabularyMatcher.WeightedTerm(
                    canonical: $0.text,
                    strength: $0.strength == .strong ? .strong : .normal
                )
            }
        weightedTerms.append(contentsOf: learnedTerms.map {
            VocabularyMatcher.WeightedTerm(canonical: $0, strength: .normal)
        })
        weightedTerms.append(contentsOf: packTerms.map {
            VocabularyMatcher.WeightedTerm(canonical: $0, strength: .normal)
        })
        weightedTerms.append(contentsOf: screenTerms.map {
            VocabularyMatcher.WeightedTerm(canonical: $0, strength: .normal)
        })
        return weightedTerms
    }

    /// Live caption — filler cleanup only. Vocab substitution runs once on the
    /// finalized transcript so partials stay faithful to Flash output (FluidVoice-style).
    static func publishableLiveState(from raw: State) -> State {
        let trimmed = raw.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return State(text: raw.text, stableWordCount: raw.stableWordCount)
        }
        let cleaned = TranscriptCleaner.clean(trimmed)
        let cleanedWords = wordCount(cleaned)
        let stable = min(raw.stableWordCount, cleanedWords)
        return State(text: cleaned, stableWordCount: stable)
    }

    // MARK: - Display split

    static func splitStableProvisional(
        _ text: String,
        stableWordCount: Int
    ) -> (stable: String, provisional: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return ("", "") }

        let clampedStable = min(max(stableWordCount, 0), words.count)
        if clampedStable <= 0 {
            return ("", words.joined(separator: " "))
        }
        if clampedStable >= words.count {
            return (trimmed, "")
        }

        let stable = words.prefix(clampedStable).joined(separator: " ")
        let provisional = words.dropFirst(clampedStable).joined(separator: " ")
        return (stable, provisional)
    }

    // MARK: - Helpers

    static func wordCount(_ text: String) -> Int {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .count
    }
}