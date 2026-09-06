import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Gilt

final class QuickNoteNavigationTests: XCTestCase {
    func testQuickNoteNavigationStateOnlyAllowsBackwardWhenHistoryExists() {
        let older = NoteItem(
            folderID: NoteFolder.scratchpadsID,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            lastOpenedAt: Date(timeIntervalSince1970: 10),
            origin: .quickNote
        )
        let newer = NoteItem(
            folderID: NoteFolder.scratchpadsID,
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 20),
            lastOpenedAt: Date(timeIntervalSince1970: 20),
            origin: .quickNote
        )
        let notes = [older, newer]

        XCTAssertEqual(
            quickNoteNavigationState(currentNoteID: older.noteID, quickNotes: notes),
            QuickNoteNavigationState(canNavigateBackward: false, canNavigateForward: true)
        )
        XCTAssertEqual(
            quickNoteNavigationState(currentNoteID: newer.noteID, quickNotes: notes),
            QuickNoteNavigationState(canNavigateBackward: true, canNavigateForward: true)
        )
    }

    func testQuickNoteCommandNavigationSupportsBracketsAndArrowKeys() {
        XCTAssertEqual(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: "[",
                keyCode: 0,
                modifierFlags: [.command]
            ),
            -1
        )
        XCTAssertEqual(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: "]",
                keyCode: 0,
                modifierFlags: [.command]
            ),
            1
        )
        XCTAssertEqual(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_LeftArrow),
                modifierFlags: [.command]
            ),
            -1
        )
        XCTAssertEqual(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_RightArrow),
                modifierFlags: [.command]
            ),
            1
        )
        XCTAssertNil(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_RightArrow),
                modifierFlags: []
            )
        )
    }

    func testQuickNoteNavigationRequiresCommandWithoutOtherModifiers() {
        // Regression: the modifier check only asked "is Command held", so
        // Cmd+Shift+Arrow (the standard select-to-line-start/end shortcut)
        // switched notes and threw away the user's selection.
        XCTAssertNil(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_LeftArrow),
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertNil(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_RightArrow),
                modifierFlags: [.command, .option]
            )
        )
        XCTAssertNil(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: "[",
                keyCode: 0,
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertNil(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: "]",
                keyCode: 0,
                modifierFlags: [.command, .control]
            )
        )
    }

    func testQuickNoteNavigationToleratesIntrinsicArrowKeyFlags() {
        // Real arrow-key NSEvents always carry .function and .numericPad;
        // requiring an exact Command-only match must not break plain
        // Cmd+Left/Right on physical keyboards.
        XCTAssertEqual(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_LeftArrow),
                modifierFlags: [.command, .function, .numericPad]
            ),
            -1
        )
        XCTAssertEqual(
            quickNoteCommandNavigationStep(
                charactersIgnoringModifiers: nil,
                keyCode: UInt16(kVK_RightArrow),
                modifierFlags: [.command, .function, .numericPad]
            ),
            1
        )
    }

    func testQuickNoteSlideShowEndsAtTargetAndStartsOffset() {
        let target = NSRect(x: 100, y: 120, width: 560, height: 420)
        let motion = QuickNoteWindowMotion.make(style: .slide, phase: .show, anchorFrame: target)

        XCTAssertEqual(motion.toFrame, target)
        XCTAssertNotEqual(motion.fromFrame.origin.y, target.origin.y)
        XCTAssertEqual(motion.fromFrame.width, target.width)
        XCTAssertEqual(motion.startAlpha, 0)
        XCTAssertEqual(motion.endAlpha, 1)
    }

    func testQuickNoteSlideHideFadesOutFromStartFrame() {
        let start = NSRect(x: 100, y: 120, width: 560, height: 420)
        let motion = QuickNoteWindowMotion.make(style: .slide, phase: .hide, anchorFrame: start)

        XCTAssertEqual(motion.fromFrame, start)
        XCTAssertEqual(motion.startAlpha, 1)
        XCTAssertEqual(motion.endAlpha, 0)
    }

    func testQuickNoteWindowMotionInterpolatesAlphaAcrossProgress() {
        let target = NSRect(x: 0, y: 0, width: 560, height: 420)
        let show = QuickNoteWindowMotion.make(style: .slide, phase: .show, anchorFrame: target)
        XCTAssertEqual(show.interpolatedAlpha(for: 0), 0, accuracy: 0.001)
        XCTAssertGreaterThan(show.interpolatedAlpha(for: 0.5), 0)
        XCTAssertEqual(show.interpolatedAlpha(for: 1), 1, accuracy: 0.001)

        let hide = QuickNoteWindowMotion.make(style: .slide, phase: .hide, anchorFrame: target)
        XCTAssertEqual(hide.interpolatedAlpha(for: 0), 1, accuracy: 0.001)
        XCTAssertLessThan(hide.interpolatedAlpha(for: 0.5), 1)
        XCTAssertEqual(hide.interpolatedAlpha(for: 1), 0, accuracy: 0.001)
    }

    func testQuickNoteAnimationStylesUseDistinctStartFrames() {
        let target = NSRect(x: 100, y: 120, width: 560, height: 420)

        let fadeShow = QuickNoteWindowMotion.make(style: .fade, phase: .show, anchorFrame: target)
        XCTAssertEqual(fadeShow.fromFrame, target) // fade = alpha-only

        let riseShow = QuickNoteWindowMotion.make(style: .riseFromBelow, phase: .show, anchorFrame: target)
        XCTAssertLessThan(riseShow.fromFrame.minY, target.minY)

        let dropShow = QuickNoteWindowMotion.make(style: .dropFromTop, phase: .show, anchorFrame: target)
        XCTAssertGreaterThan(dropShow.fromFrame.minY, target.minY)

        let leftShow = QuickNoteWindowMotion.make(style: .slideFromLeft, phase: .show, anchorFrame: target)
        XCTAssertLessThan(leftShow.fromFrame.minX, target.minX)

        let rightShow = QuickNoteWindowMotion.make(style: .slideFromRight, phase: .show, anchorFrame: target)
        XCTAssertGreaterThan(rightShow.fromFrame.minX, target.minX)

        let popShow = QuickNoteWindowMotion.make(style: .pop, phase: .show, anchorFrame: target)
        XCTAssertLessThan(popShow.fromFrame.width, target.width)
        XCTAssertEqual(popShow.fromFrame.midX, target.midX, accuracy: 0.5)
        XCTAssertEqual(popShow.fromFrame.midY, target.midY, accuracy: 0.5)

        let zoomShow = QuickNoteWindowMotion.make(style: .zoomIn, phase: .show, anchorFrame: target)
        XCTAssertGreaterThan(zoomShow.fromFrame.width, target.width)
    }

    func testQuickNoteWindowMotionInterpolatesFrameDimensionsForPop() {
        let resting = NSRect(x: 100, y: 100, width: 200, height: 160)
        let motion = QuickNoteWindowMotion.make(style: .pop, phase: .show, anchorFrame: resting)
        let mid = motion.interpolatedFrame(for: 0.5)

        XCTAssertGreaterThan(mid.width, resting.width)
        XCTAssertGreaterThan(mid.width, motion.fromFrame.width)
        XCTAssertEqual(mid.midX, resting.midX, accuracy: 0.5)
        XCTAssertEqual(mid.midY, resting.midY, accuracy: 0.5)
    }

    func testAppSettingsDecodesQuickNoteAnimationStyles() throws {
        let json = #"{"quickNoteOpenAnimation":"pop","quickNoteCloseAnimation":"fade"}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.quickNoteOpenAnimation, .pop)
        XCTAssertEqual(decoded.quickNoteCloseAnimation, .fade)
    }
}
