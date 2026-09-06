import Foundation
import SwiftData

/// One persistent thing Jack knows about the user.
///
/// Designed to scale: the system stores *distilled* facts (one short sentence)
/// rather than logs or raw screen captures. Per-category caps + decay live in
/// the future pruning pass and depend on `reinforcementCount` and
/// `lastReinforcedAt` being kept accurate as new screen contexts arrive.
///
/// Raw strings are used for the category and source so SwiftData migrations
/// stay forgiving — adding a future case won't break decode of older stores.
@Model
final class FactModel {
    /// Stable identifier independent of SwiftData's internal id. Used when
    /// passing references through SwiftUI bindings or future export/import.
    var factID: UUID

    /// Short, plain-English statement of the fact. Examples:
    /// "Uses Xcode and Figma daily", "Builds Mac apps in SwiftUI",
    /// "Prefers terse responses".
    var text: String

    /// Category bucket. Stored raw so unknown future values don't fail decode.
    var categoryRaw: String

    /// Provenance. Stored raw for the same reason as `categoryRaw`.
    var sourceRaw: String

    /// 0.0–1.0. New facts start around 0.5 and rise with reinforcement.
    /// The pruning pass evicts low-confidence facts first.
    var confidence: Double

    var createdAt: Date

    /// Last time this fact was either seen again in screen context or
    /// manually edited. Drives the decay logic in the pruning pass.
    var lastReinforcedAt: Date

    /// How many times this fact has been re-observed. A one-shot fact stays
    /// at 1; something seen across many sessions climbs. This is the main
    /// signal that separates "user actually does this" from "model said it
    /// once."
    var reinforcementCount: Int

    /// User-pinned facts are never auto-pruned, no matter their confidence
    /// or age. Pinning is opt-in from the settings panel.
    var isPinned: Bool

    init(
        factID: UUID = UUID(),
        text: String,
        categoryRaw: String,
        sourceRaw: String,
        confidence: Double = 0.5,
        createdAt: Date = Date(),
        lastReinforcedAt: Date? = nil,
        reinforcementCount: Int = 1,
        isPinned: Bool = false
    ) {
        self.factID = factID
        self.text = text
        self.categoryRaw = categoryRaw
        self.sourceRaw = sourceRaw
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastReinforcedAt = lastReinforcedAt ?? createdAt
        self.reinforcementCount = reinforcementCount
        self.isPinned = isPinned
    }

    // MARK: - Computed Helpers

    var category: FactCategory {
        FactCategory(rawValue: categoryRaw) ?? .misc
    }

    var source: FactSource {
        FactSource(rawValue: sourceRaw) ?? .manual
    }
}
