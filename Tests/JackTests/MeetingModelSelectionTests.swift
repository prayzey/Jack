import XCTest
@testable import Gilt

final class MeetingModelSelectionTests: XCTestCase {
    func testEnglishRoutesToParakeet() {
        let engine = MeetingTranscriptionEngine.recommended(for: .english)
        XCTAssertEqual(engine, .parakeetV2)
    }

    func testSpanishUsesWhisperSmall() {
        XCTAssertEqual(
            MeetingTranscriptionEngine.recommended(for: .spanish),
            .whisperSmallMultilingual
        )
    }

    func testGermanUsesWhisperSmall() {
        XCTAssertEqual(
            MeetingTranscriptionEngine.recommended(for: .german),
            .whisperSmallMultilingual
        )
    }

    func testMixedFallsBackToWhisperSmall() {
        XCTAssertEqual(
            MeetingTranscriptionEngine.recommended(for: .mixed),
            .whisperSmallMultilingual
        )
    }

    func testAutoLanguageRoutesToWhisperSmall() {
        // Auto must NOT pick Parakeet — Parakeet is English-only, so an
        // unknown-language recording would come back as garbage. Whisper
        // small handles every language correctly.
        XCTAssertEqual(
            MeetingTranscriptionEngine.recommended(for: .auto),
            .whisperSmallMultilingual
        )
    }
}
