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

    func testPillHugsItsWordsAndStopsAtItsMaxWidth() {
        typealias L = DictationCaptionLayout
        XCTAssertEqual(L.pillWidth(.empty, maxWidth: 360, showsControls: false), L.pillHeight, "Waiting is a circle")
        XCTAssertEqual(L.pillWidth(.text(100.2), maxWidth: 360, showsControls: false), L.textLeading + 101 + L.textTrailing)
        XCTAssertEqual(L.pillWidth(.text(1_000), maxWidth: 360, showsControls: false), 360)
        // A full pill keeps its width when the buttons appear; the words make room instead.
        XCTAssertEqual(L.pillWidth(.text(1_000), maxWidth: 360, showsControls: true), 360)
        XCTAssertEqual(L.textViewport(pillWidth: 360, showsControls: true), 360 - L.textLeading - L.controlsTrailing)
        XCTAssertGreaterThan(L.pillWidth(.empty, maxWidth: 360, showsControls: true), L.pillHeight)
        // Every visible word fits: the viewport is never narrower than short text.
        let short = L.pillWidth(.text(80.4), maxWidth: 360, showsControls: false)
        XCTAssertGreaterThanOrEqual(L.textViewport(pillWidth: short, showsControls: false), 80.4)
    }

    func testDotGridIsRoundAndDrawsACheckWhenDone() {
        XCTAssertEqual(DotGridEngine.cells.count, 37)
        XCTAssertEqual(DotGridEngine.checkPath.count, 5)
        XCTAssertEqual(Set(DotGridEngine.checkPath).count, 5)
        let done = DotGridEngine.cells.indices.map {
            DotGridEngine.target(mode: .done, cell: $0, time: 0, since: 2, loudness: 0, reduceMotion: false)
        }
        XCTAssertEqual(done.filter { $0 == 1 }.count, 5, "Only the check is lit once it has drawn")
        XCTAssertEqual(done.reduce(0, +), 5)

        let center = DotGridEngine.cells.firstIndex { $0.row == 3 && $0.column == 3 }!
        let loud = DotGridEngine.target(mode: .speaking, cell: center, time: 0, since: 0, loudness: 1, reduceMotion: true)
        let quiet = DotGridEngine.target(mode: .speaking, cell: center, time: 0, since: 0, loudness: 0, reduceMotion: true)
        XCTAssertEqual(loud, 1)
        XCTAssertEqual(quiet, 0)
    }

    func testWordsFlowInAtASteadyPaceInsteadOfInBursts() {
        let motion = DictationPillMotion()
        var now = Date()
        let frame = 1.0 / 60
        motion.advance(to: now, revealTarget: 0, hurry: false, reduceMotion: false) { _ in 44 }
        // A three-word burst lands at once; it should spread over several frames, not appear in one.
        var steps: [CGFloat] = []
        var last = motion.revealed
        for _ in 0..<90 {
            now += frame
            motion.advance(to: now, revealTarget: 140, hurry: false, reduceMotion: false) { 46 + $0 + 16 }
            steps.append(motion.revealed - last)
            last = motion.revealed
        }
        XCTAssertLessThan(steps.max() ?? 0, 10, "No single frame jumps more than a few letters")
        XCTAssertGreaterThan(steps.filter { $0 > 0 }.count, 20, "The burst is spread across many frames")
        XCTAssertEqual(motion.revealed, 140, "It catches up within a second and a half")

        // Once speech stops it finishes faster.
        let hurried = DictationPillMotion()
        var t2 = Date()
        hurried.advance(to: t2, revealTarget: 0, hurry: true, reduceMotion: false) { _ in 44 }
        var frames = 0
        while hurried.revealed < 140, frames < 200 {
            t2 += frame
            frames += 1
            hurried.advance(to: t2, revealTarget: 140, hurry: true, reduceMotion: false) { _ in 44 }
        }
        XCTAssertLessThan(frames, 45)

        // A fresh session after a pause starts settled, with nothing left over.
        motion.advance(to: now + 5, revealTarget: 0, hurry: false, reduceMotion: false) { _ in 44 }
        XCTAssertEqual(motion.revealed, 0)
        XCTAssertEqual(motion.width, 44)
    }
}
