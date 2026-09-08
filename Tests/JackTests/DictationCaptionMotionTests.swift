import SwiftUI
import XCTest
@testable import Gilt

@MainActor
final class DictationCaptionMotionTests: XCTestCase {
    func testCaptionWidthStaysUsableAndSurvivesSettingsReload() throws {
        XCTAssertEqual(DictationCaptionLayout.clampedCaptionWidth(.infinity), 360)
        XCTAssertEqual(DictationCaptionLayout.clampedCaptionWidth(-50), 320)
        XCTAssertEqual(DictationCaptionLayout.clampedCaptionWidth(10_000), 900)
        XCTAssertEqual(DictationCaptionLayout.clampedCaptionWidth(900, availableWidth: 700), 652)
        var settings = DictationSettings()
        settings.captionWidth = 640
        XCTAssertEqual(try JSONDecoder().decode(DictationSettings.self, from: JSONEncoder().encode(settings)).captionWidth, 640)
        XCTAssertEqual(try JSONDecoder().decode(DictationSettings.self, from: Data("{}".utf8)).captionWidth, 360)
    }

    func testConfirmationPreservesParagraphsSpacingAndUnicode() throws {
        for text in ["", "Send  $50 to José.\n\nKeep invoice A-42.", "你好 世界 — مرحباً بالعالم", "microphone"] {
            for confirmed in [-1, 0, 1, 3, 100] {
                let styled = DictationWritingCaptionView.styledText(text, stableWordCount: confirmed, color: .white)
                XCTAssertEqual(String(styled.characters), text)
            }
        }
        let styled = DictationWritingCaptionView.styledText("Keep  this\nreadable", stableWordCount: 2, color: .white)
        XCTAssertEqual(styled.runs.count, 2)
        let confirmed = try XCTUnwrap(styled.runs.first)
        XCTAssertEqual(String(styled[confirmed.range].characters), "Keep  this")
    }
}
