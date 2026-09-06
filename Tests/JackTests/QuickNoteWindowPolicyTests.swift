import AppKit
import XCTest
@testable import Gilt

@MainActor
private final class FakeQuickNoteActivatingWindow: QuickNoteActivatingWindow {
    var canBecomeKey = true
    var isKeyWindow = false
    var steps: [String] = []

    func orderFrontRegardless() {
        steps.append("orderFrontRegardless")
    }

    func makeKey() {
        steps.append("makeKey")
        isKeyWindow = true
    }
}

@MainActor
final class QuickNoteWindowPolicyTests: XCTestCase {
    func testCleanCanvasIsTheFirstQuickNoteStyleChoice() {
        XCTAssertEqual(QuickNoteStyle.allCases.first, .cleanCanvas)
    }

    func testConfigureQuickNoteWindowKeepsSurfaceBorderlessAndClear() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        configureQuickNoteWindow(window)

        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertFalse(window.hasShadow)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertEqual(window.minSize, quickNoteMinimumWindowSize)
        XCTAssertEqual(window.title, "Quick Note")
    }

    func testQuickNoteWindowLevelSitsAboveSettingsPreviewLevel() {
        let dockPlusTwoSettingsPreviewLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

        XCTAssertGreaterThan(
            quickNoteWindowLevel().rawValue,
            dockPlusTwoSettingsPreviewLevel.rawValue
        )
    }

    func testDragHeaderLeavesComfortableTopGrabAreaForEachStyle() {
        for style in QuickNoteStyle.allCases {
            XCTAssertGreaterThanOrEqual(
                quickNoteDragHeaderHeight(for: style),
                46,
                "Expected \(style.rawValue) to keep enough room for a reliable drag grab area."
            )
        }
    }

    func testActivateQuickNoteWindowActivatesAppBeforeOrderingAndMakesKey() {
        let window = FakeQuickNoteActivatingWindow()

        activateQuickNoteWindow(window, appIsActive: false) {
            window.steps.append("activateApp")
        }

        XCTAssertEqual(
            window.steps,
            ["activateApp", "orderFrontRegardless", "makeKey"]
        )
        XCTAssertTrue(window.isKeyWindow)
    }

    func testActivateQuickNoteWindowSkipsExtraAppActivationWhenAlreadyFocused() {
        let window = FakeQuickNoteActivatingWindow()
        window.isKeyWindow = true

        activateQuickNoteWindow(window, appIsActive: true) {
            window.steps.append("activateApp")
        }

        XCTAssertEqual(window.steps, ["orderFrontRegardless"])
    }

    func testQuickNoteEditorLookupFindsNestedEditorView() {
        let root = NSView(frame: .zero)
        let wrapper = NSView(frame: .zero)
        let innerWrapper = NSView(frame: .zero)
        let editor = QuickNoteEditorTextView(frame: .zero, textContainer: nil)

        innerWrapper.addSubview(editor)
        wrapper.addSubview(innerWrapper)
        root.addSubview(wrapper)

        XCTAssertTrue(quickNoteEditor(in: root) === editor)
    }

    func testQuickNoteEditorFactoryBuildsARealTextSystem() {
        let editor = makeQuickNoteEditorTextView()

        XCTAssertNotNil(editor.textStorage)
        XCTAssertNotNil(editor.layoutManager)
        XCTAssertNotNil(editor.textContainer)
        XCTAssertTrue(editor.textContainer?.widthTracksTextView == true)
        XCTAssertEqual(Double(editor.textContainer?.lineFragmentPadding ?? 1), 0, accuracy: 0.001)
    }

    // MARK: - Resume-where-you-left-off (reopening the Quick Note)

    func testShowResumesTheActiveNoteInsteadOfJumpingToNewest() {
        // Reproduces the bug: on the 5th of 10 notes, closing and reopening must
        // land back on the 5th, not snap to the newest (10th).
        let notes = makeQuickNotes(10)
        let fifth = notes[4].noteID

        let resolved = resolveQuickNoteToShow(activeID: fifth, quickNotes: notes)

        XCTAssertEqual(resolved, fifth)
        XCTAssertNotEqual(resolved, notes.last?.noteID)
    }

    func testShowFallsBackToNewestWhenNoActiveNote() {
        let notes = makeQuickNotes(3)
        XCTAssertEqual(resolveQuickNoteToShow(activeID: nil, quickNotes: notes), notes.last?.noteID)
    }

    func testShowFallsBackToNewestWhenActiveNoteNoLongerExists() {
        // e.g. the previously-active note was empty and got swept on hide.
        let notes = makeQuickNotes(3)
        XCTAssertEqual(resolveQuickNoteToShow(activeID: UUID(), quickNotes: notes), notes.last?.noteID)
    }

    func testShowReturnsNilWhenThereAreNoQuickNotes() {
        XCTAssertNil(resolveQuickNoteToShow(activeID: nil, quickNotes: []))
        XCTAssertNil(resolveQuickNoteToShow(activeID: UUID(), quickNotes: []))
    }

    private func makeQuickNotes(_ count: Int) -> [NoteItem] {
        (0..<count).map { index in
            NoteItem(
                folderID: NoteFolder.scratchpadsID,
                bodyMarkdown: "Note \(index)",
                origin: .quickNote
            )
        }
    }
}
