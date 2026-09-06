import XCTest
@testable import Gilt

final class VocabularyMatcherTests: XCTestCase {

    // MARK: - Legacy (flat-string) API still works

    func testFlatApplyKeepsExistingExactMatchBehavior() {
        let out = VocabularyMatcher.apply(
            "I love chatgpt and useeffect",
            terms: ["ChatGPT", "useEffect"]
        )
        XCTAssertEqual(out, "I love ChatGPT and useEffect")
    }

    func testFlatApplyDoesNotDoPhoneticSubstitution() {
        // "clawed" sounds like "claude" but the flat-string matcher must
        // not rewrite it — only the weighted .strong path does that.
        let out = VocabularyMatcher.apply(
            "I asked clawed for help",
            terms: ["claude"]
        )
        XCTAssertEqual(out, "I asked clawed for help")
    }

    // MARK: - Weighted API — normal strength matches legacy

    func testWeightedNormalMatchesFlatBehavior() {
        let out = VocabularyMatcher.apply(
            "spin up chat g p t and use effect",
            weighted: [
                .init(canonical: "ChatGPT",   strength: .normal),
                .init(canonical: "useEffect", strength: .normal)
            ]
        )
        XCTAssertEqual(out, "spin up ChatGPT and useEffect")
    }

    func testWeightedNormalDoesNotRewriteMishearing() {
        let out = VocabularyMatcher.apply(
            "I asked clawed for help",
            weighted: [.init(canonical: "claude", strength: .normal)]
        )
        XCTAssertEqual(out, "I asked clawed for help")
    }

    // MARK: - Weighted API — strong strength fixes mishearings

    func testStrongRewritesPhoneticMishearing() {
        let out = VocabularyMatcher.apply(
            "I asked clawed for help",
            weighted: [.init(canonical: "claude", strength: .strong)]
        )
        XCTAssertEqual(out, "I asked claude for help")
    }

    func testStrongNormalizesCanonicalCasing() {
        let out = VocabularyMatcher.apply(
            "I asked Claude for help",
            weighted: [.init(canonical: "claude", strength: .strong)]
        )
        XCTAssertEqual(out, "I asked claude for help")
    }

    func testStrongLeavesPunctuationAndCasingAroundReplacementAlone() {
        let out = VocabularyMatcher.apply(
            "Hey, clawed — got a sec?",
            weighted: [.init(canonical: "claude", strength: .strong)]
        )
        XCTAssertEqual(out, "Hey, claude — got a sec?")
    }

    func testStrongSkipsVeryShortTokens() {
        // Soundex on 3-letter tokens has way too many collisions; the
        // matcher should refuse to rewrite anything under 4 letters.
        let out = VocabularyMatcher.apply(
            "is it ok",
            weighted: [.init(canonical: "claude", strength: .strong)]
        )
        XCTAssertEqual(out, "is it ok")
    }

    // MARK: - Soundex sanity

    func testSoundexMatchesClaudeAndClawed() {
        XCTAssertEqual(VocabularyMatcher.soundex("claude"), VocabularyMatcher.soundex("clawed"))
    }

    func testSoundexDifferentForDifferentSounds() {
        XCTAssertNotEqual(VocabularyMatcher.soundex("claude"), VocabularyMatcher.soundex("rabbit"))
    }
}
