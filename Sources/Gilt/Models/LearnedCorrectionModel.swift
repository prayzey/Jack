import Foundation
import SwiftData

/// One thing the dictation pipeline has *learned* by watching the user edit a
/// pasted dictation.
///
/// The learning loop works like this:
/// 1. Jack pastes a dictation into the user's editor.
/// 2. `CorrectionLearner` watches the focused text field via the Accessibility
///    API for up to ~60 seconds.
/// 3. When the user moves on (focus loss, app switch, idle), Qwen is asked
///    whether the user *corrected* the dictation — and if so, to extract the
///    specific word-level substitutions.
/// 4. Each substitution becomes a `LearnedCorrectionModel` row here.
///
/// Future dictation sessions inject the corrected forms into the vocabulary
/// matcher so the same mistake doesn't keep happening. Same data path Willow
/// Voice's "Auto-Dictionary" and Wispr Flow's "learns from corrections"
/// features use, just running locally on Qwen instead of a cloud model.
///
/// Stored fields are deliberately raw strings + scalar types because
/// SwiftData's migration story is happiest with simple shapes. We avoid
/// `Codable` nested structs here for the same reason.
@Model
final class LearnedCorrectionModel {
    /// Stable identifier independent of SwiftData's internal id. Used for
    /// SwiftUI bindings + future export/import.
    var correctionID: UUID

    /// The word or short phrase the dictation produced ("useeffect",
    /// "Adasokan", "api"). Lowercase-compared during dedup, but stored
    /// with original casing so the settings UI can show it faithfully.
    var original: String

    /// The user's corrected form ("useEffect", "Adesokan", "API"). This is
    /// what gets fed into the vocabulary matcher on future dictations.
    var corrected: String

    /// Where this correction was learned — "Cursor", "Slack", "Cluely".
    /// Optional because the AX path doesn't always have a friendly name.
    var sourceAppName: String?
    var sourceAppBundleID: String?

    /// How many separate times Jack has seen the user make this exact
    /// correction. Climbs with each repeat sighting; high counts = high
    /// confidence = first to ship into the vocab matcher.
    var reinforcementCount: Int

    /// 0.0–1.0. Bumped by reinforcement, dampened by age. Eviction sorts on
    /// confidence × recency so a single one-off correction can age out
    /// while a frequently-reinforced one stays.
    var confidence: Double

    /// User can flip off a correction in the settings panel without
    /// deleting it. Inactive rows are kept for audit but not injected into
    /// the Polish vocabulary. Deletes (via the panel) remove the row
    /// entirely.
    var isActive: Bool

    var createdAt: Date
    var lastReinforcedAt: Date

    init(
        correctionID: UUID = UUID(),
        original: String,
        corrected: String,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        reinforcementCount: Int = 1,
        confidence: Double = 0.6,
        isActive: Bool = true,
        createdAt: Date = Date(),
        lastReinforcedAt: Date? = nil
    ) {
        self.correctionID = correctionID
        self.original = original
        self.corrected = corrected
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.reinforcementCount = reinforcementCount
        self.confidence = confidence
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastReinforcedAt = lastReinforcedAt ?? createdAt
    }

    // MARK: - Eviction score

    /// Higher = more worth keeping. Used by `CorrectionStore` when the
    /// store exceeds its global or per-app caps. Combines confidence with
    /// recency (days since last reinforcement) so a high-confidence
    /// correction the user hasn't reinforced in months gradually loses
    /// ground to fresher ones.
    func evictionScore(now: Date = Date()) -> Double {
        let days = max(0, now.timeIntervalSince(lastReinforcedAt)) / 86_400
        // Half-life of ~60 days. After 60 days without reinforcement the
        // score halves; without this, the store would fossilize around
        // whatever the user typed early on.
        let recency = pow(0.5, days / 60)
        return confidence * recency
    }
}
