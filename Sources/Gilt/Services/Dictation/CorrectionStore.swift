import Foundation
import OSLog
import SwiftData

/// Persistent storage for things the dictation pipeline has learned by
/// watching the user fix Jack's mistakes.
///
/// This is intentionally a small CRUD layer — the *deciding what to learn*
/// part lives in `CorrectionLearner`. Splitting them keeps the store easy to
/// test (no model dependencies, no AX dependencies) and lets the settings
/// panel work against it directly without booting the learner.
///
/// **Scalability rules baked in:**
/// - Per-app cap (`perAppCap`) so one chatty app can't eat the whole budget.
/// - Global cap (`globalCap`) so the SwiftData table never grows unbounded.
/// - Eviction by `LearnedCorrectionModel.evictionScore(now:)` — combines
///   confidence with recency, so a high-confidence correction the user
///   stopped using gradually yields to a fresh one.
/// - Dedup on `(original.lowercased, corrected.lowercased)` so re-seeing
///   the same correction reinforces the existing row instead of duplicating.
@MainActor
final class CorrectionStore: ObservableObject {
    /// All correction rows, freshest-reinforcement first. Mirrors the
    /// SwiftData store and is republished on every mutation so SwiftUI
    /// views can observe without their own fetches.
    @Published private(set) var corrections: [LearnedCorrectionModel] = []

    /// How many corrections any single app is allowed to contribute. Caps
    /// pathological apps (auto-completion text boxes, draft editors)
    /// without punishing apps that are merely popular.
    let perAppCap: Int = 50
    /// Hard upper bound on total stored corrections. Picked generously —
    /// even at 200 rows the matcher pass is microseconds.
    let globalCap: Int = 200

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "CorrectionStore")
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = false
        refresh()
    }

    // MARK: - Reads

    var correctionCount: Int { corrections.count }

    /// Active corrections only — what should be injected into the Polish
    /// vocabulary matcher. Bypasses inactive (user-disabled) rows.
    var activeCorrections: [LearnedCorrectionModel] {
        corrections.filter(\.isActive)
    }

    /// Corrected forms only, in reinforcement order. Used by the
    /// coordinator to merge into the vocabulary list at Polish time.
    func topCorrectedTerms(limit: Int) -> [String] {
        Array(
            activeCorrections
                .sorted { $0.reinforcementCount > $1.reinforcementCount }
                .prefix(limit)
                .map(\.corrected)
        )
    }

    func refresh() {
        // SwiftData's SortDescriptor with `Bool` keypaths requires NSObject
        // conformance, which @Model classes lack. Sort by date in the
        // fetch and apply isActive ordering with an in-memory pass.
        let descriptor = FetchDescriptor<LearnedCorrectionModel>(
            sortBy: [SortDescriptor(\.lastReinforcedAt, order: .reverse)]
        )
        corrections = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Writes

    /// Record one observed correction. Dedup pass first: if the exact
    /// (original, corrected) pair already exists for any app, reinforce
    /// that row instead of inserting a duplicate. This is what makes the
    /// store self-stabilizing across repeated sightings.
    @discardableResult
    func recordCorrection(
        original: String,
        corrected: String,
        sourceAppName: String?,
        sourceAppBundleID: String?
    ) -> LearnedCorrectionModel? {
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOriginal.isEmpty, !cleanCorrected.isEmpty else { return nil }
        // Identity correction — nothing to learn.
        guard cleanOriginal.lowercased() != cleanCorrected.lowercased() else { return nil }

        if let existing = exactMatch(original: cleanOriginal, corrected: cleanCorrected) {
            reinforce(existing)
            return existing
        }

        let row = LearnedCorrectionModel(
            original: cleanOriginal,
            corrected: cleanCorrected,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        modelContext.insert(row)
        enforceCaps(newlyAddedBundleID: sourceAppBundleID)
        persist()
        refresh()
        logger.info("Learned correction: '\(cleanOriginal, privacy: .public)' -> '\(cleanCorrected, privacy: .public)' (app=\(sourceAppName ?? "?", privacy: .public))")
        return row
    }

    func reinforce(_ row: LearnedCorrectionModel) {
        row.reinforcementCount += 1
        row.lastReinforcedAt = Date()
        // Confidence climbs toward 1.0 but never reaches it — leaves room
        // for a future manual-confirm UI to outrank inferred rows.
        row.confidence = min(0.99, row.confidence + 0.08)
        persist()
        refresh()
    }

    func setActive(_ row: LearnedCorrectionModel, isActive: Bool) {
        row.isActive = isActive
        persist()
        refresh()
    }

    func deleteCorrection(_ row: LearnedCorrectionModel) {
        modelContext.delete(row)
        persist()
        refresh()
    }

    func clearAll() {
        for row in corrections {
            modelContext.delete(row)
        }
        persist()
        refresh()
    }

    // MARK: - Internals

    private func exactMatch(original: String, corrected: String) -> LearnedCorrectionModel? {
        let lowO = original.lowercased()
        let lowC = corrected.lowercased()
        return corrections.first { row in
            row.original.lowercased() == lowO && row.corrected.lowercased() == lowC
        }
    }

    /// Cap enforcement after each insert. Runs in two passes:
    /// 1. If the newly-added row's app is over `perAppCap`, evict the
    ///    lowest-eviction-score row within that app (preferring the
    ///    fresh insert means the user's most recent learning wins).
    /// 2. If the table overall is over `globalCap`, evict the
    ///    lowest-eviction-score row globally.
    /// Inactive rows are NOT auto-pruned — the user explicitly disabled
    /// them and might re-enable later. They count against caps though,
    /// to keep the budget honest.
    private func enforceCaps(newlyAddedBundleID: String?) {
        // Re-fetch since we just inserted — the @Published `corrections`
        // is stale until refresh().
        let descriptor = FetchDescriptor<LearnedCorrectionModel>()
        let allRows = (try? modelContext.fetch(descriptor)) ?? []

        if let bundleID = newlyAddedBundleID {
            let appRows = allRows.filter { $0.sourceAppBundleID == bundleID }
            if appRows.count > perAppCap {
                let toRemove = appRows
                    .sorted { $0.evictionScore() < $1.evictionScore() }
                    .prefix(appRows.count - perAppCap)
                for row in toRemove {
                    modelContext.delete(row)
                }
            }
        }

        if allRows.count > globalCap {
            // Reuse the same allRows snapshot — close enough; the per-app
            // pass above only deletes a handful at most.
            let toRemove = allRows
                .sorted { $0.evictionScore() < $1.evictionScore() }
                .prefix(allRows.count - globalCap)
            for row in toRemove {
                modelContext.delete(row)
            }
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            logger.error("CorrectionStore save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
