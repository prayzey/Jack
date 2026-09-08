import SwiftUI
import XCTest
@testable import Gilt

@MainActor
final class DictationCaptionMotionTests: XCTestCase {
    func testResizeHandleHitTestingUsesTheSuperviewCoordinateSpace() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 408, height: 244))
        let handle = WindowFrameResizeHandleNSView(frame: NSRect(x: 377, y: 24, width: 14, height: 110))
        parent.addSubview(handle)
        XCTAssertTrue(handle.hitTest(NSPoint(x: 380, y: 70)) === handle)
        XCTAssertNil(handle.hitTest(NSPoint(x: 200, y: 70)))
    }
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
