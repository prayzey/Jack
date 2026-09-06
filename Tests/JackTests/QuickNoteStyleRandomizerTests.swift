import XCTest
@testable import Gilt

/// Deterministic, seedable generator (SplitMix64) so the random-style tests
/// can assert exact picks. `SystemRandomNumberGenerator` can't be seeded.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class QuickNoteStyleRandomizerTests: XCTestCase {
    func testRandomStyleNeverReturnsTheExcludedStyle() {
        // The whole point of Randomize Design: the look must actually change.
        // Exhaustively check every current style across many seeds.
        for current in QuickNoteStyle.allCases {
            for seed in UInt64(0) ..< 200 {
                var generator = SeededGenerator(seed: seed)
                let picked = QuickNoteStyle.randomStyle(excluding: current, using: &generator)
                XCTAssertNotEqual(picked, current, "seed \(seed) returned the excluded style \(current)")
            }
        }
    }

    func testRandomStyleAlwaysReturnsAValidCase() {
        for seed in UInt64(0) ..< 50 {
            var generator = SeededGenerator(seed: seed)
            let picked = QuickNoteStyle.randomStyle(excluding: .paper, using: &generator)
            XCTAssertTrue(QuickNoteStyle.allCases.contains(picked))
        }
    }

    func testExcludingNilCanReturnAnyCase() {
        var generator = SeededGenerator(seed: 7)
        let picked = QuickNoteStyle.randomStyle(excluding: nil, using: &generator)
        XCTAssertTrue(QuickNoteStyle.allCases.contains(picked))
    }

    func testRandomStyleIsDeterministicForAFixedSeed() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        XCTAssertEqual(
            QuickNoteStyle.randomStyle(excluding: .paper, using: &a),
            QuickNoteStyle.randomStyle(excluding: .paper, using: &b)
        )
    }

    func testRandomStyleSpreadsAcrossManyStylesOverManyDraws() {
        // Sanity check that it isn't collapsing to a single style: over a few
        // hundred draws excluding the same style we expect broad coverage.
        var generator = SeededGenerator(seed: 99)
        var seen: Set<QuickNoteStyle> = []
        for _ in 0 ..< 400 {
            seen.insert(QuickNoteStyle.randomStyle(excluding: .paper, using: &generator))
        }
        XCTAssertFalse(seen.contains(.paper))
        // 15 candidates remain after excluding .paper; expect the great
        // majority to show up rather than a degenerate handful.
        XCTAssertGreaterThanOrEqual(seen.count, 12)
    }
}
