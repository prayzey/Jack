import Foundation

extension QuickNoteStyle {
    /// Pick a theme at random, never returning `current`, so "Randomize
    /// Design" always produces a visible change. Takes the generator `inout`
    /// so tests can feed a seeded one and assert deterministic picks; the
    /// running app uses the `SystemRandomNumberGenerator` convenience below.
    ///
    /// Falls back to `current` (then `.paper`) only in the degenerate case of
    /// a single enum case — impossible today with 16 styles, but keeps the
    /// function total instead of trapping on an empty candidate set.
    static func randomStyle(
        excluding current: QuickNoteStyle?,
        using generator: inout some RandomNumberGenerator
    ) -> QuickNoteStyle {
        let candidates = allCases.filter { $0 != current }
        return candidates.randomElement(using: &generator) ?? current ?? .paper
    }

    static func randomStyle(excluding current: QuickNoteStyle?) -> QuickNoteStyle {
        var generator = SystemRandomNumberGenerator()
        return randomStyle(excluding: current, using: &generator)
    }
}
