import XCTest
@testable import Gilt

/// Verifies that JSON shipped by older builds — which stored
/// `customVocabulary` as a flat `[String]` — still decodes cleanly after the
/// schema move to `[CustomVocabularyTerm]`. Without this guard, the next
/// upgrade would silently drop every user's saved term list.
final class CustomVocabularyMigrationTests: XCTestCase {

    func testLegacyStringArrayDecodesToWeightedTerms() throws {
        let json = #"""
        {
            "customVocabulary": ["claude", "barrie", "novor"]
        }
        """#
        let data = Data(json.utf8)
        let settings = try JSONDecoder().decode(DictationSettings.self, from: data)

        XCTAssertEqual(settings.customVocabulary.count, 3)
        XCTAssertEqual(settings.customVocabulary.map(\.text), ["claude", "barrie", "novor"])
        // Legacy terms lift to .strong so users immediately get the
        // mishearing-fix behavior the new field is meant to unlock.
        XCTAssertTrue(settings.customVocabulary.allSatisfy { $0.strength == .strong })
    }

    func testWeightedShapeRoundTrips() throws {
        var settings = DictationSettings()
        settings.customVocabulary = [
            CustomVocabularyTerm(text: "claude", strength: .strong),
            CustomVocabularyTerm(text: "barrie", strength: .normal),
            CustomVocabularyTerm(text: "novor", strength: .off)
        ]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: data)
        XCTAssertEqual(decoded.customVocabulary, settings.customVocabulary)
    }

    func testOffTermsAreExcludedFromActiveLists() {
        var settings = DictationSettings()
        settings.customVocabulary = [
            CustomVocabularyTerm(text: "claude", strength: .strong),
            CustomVocabularyTerm(text: "barrie", strength: .off)
        ]
        XCTAssertEqual(settings.allActiveVocabularyTerms(), ["claude"])
        XCTAssertEqual(settings.weightedCustomVocabulary().map(\.text), ["claude"])
    }
}
