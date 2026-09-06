import XCTest
@testable import Gilt

/// The engine picker in MeetingModelSettingsView and the summarization pipeline
/// both resolve the active engine through MeetingSummarizationChoice.effective.
/// These tests pin down that resolution: the user's preference only wins when
/// Apple Intelligence can actually run; otherwise Qwen is the engine in use.
final class MeetingSummarizationChoiceTests: XCTestCase {
    func testPrefersAppleWhenAppleIsUsable() {
        XCTAssertEqual(
            MeetingSummarizationChoice.effective(preferApple: true, appleUsable: true),
            .appleIntelligence
        )
    }

    func testFallsBackToQwenWhenAppleIsPreferredButUnusable() {
        XCTAssertEqual(
            MeetingSummarizationChoice.effective(preferApple: true, appleUsable: false),
            .localQwen,
            "Preferring Apple must not select an engine that cannot run; the picker would lie about which model writes the recap"
        )
    }

    func testUsesQwenWhenUserChoseQwenEvenIfAppleIsUsable() {
        XCTAssertEqual(
            MeetingSummarizationChoice.effective(preferApple: false, appleUsable: true),
            .localQwen
        )
    }

    func testUsesQwenWhenNeitherPreferredNorUsable() {
        XCTAssertEqual(
            MeetingSummarizationChoice.effective(preferApple: false, appleUsable: false),
            .localQwen
        )
    }
}
