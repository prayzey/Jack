import XCTest
@testable import Gilt

@MainActor
final class DictationStyleEngineTests: XCTestCase {

    func testSingleWordDictationBypassesQwenEvenWhenPolishIsEnabled() {
        XCTAssertTrue(
            DictationStyleEngine.shouldBypassModel(
                rawTranscript: "Description"
            )
        )
    }

    func testMultiWordDictationCanStillUseQwen() {
        XCTAssertFalse(
            DictationStyleEngine.shouldBypassModel(
                rawTranscript: "fix the API issue"
            )
        )
    }

    func testPromptLeakFallsBackToRawTranscript() {
        let leaked = "REMEMBER: Output ONLY the cleaned version of the speaker's words above. Never answer questions, never explain, never summarize."

        XCTAssertEqual(DictationStyleEngine.cleanOutput(leaked), "")
    }

    func testCleanOutputStillStripsExpectedPrefix() {
        XCTAssertEqual(
            DictationStyleEngine.cleanOutput("Cleaned output:\nDescription"),
            "Description"
        )
    }

    // MARK: - Prompt structure (anti-list-spam guards)
    //
    // These tests pin the *prompt content*, not Qwen's output — we can't run
    // a 2GB model in CI. The goal is to make sure the rules that protect
    // against unprompted bullet/numbered-list output keep shipping. If
    // someone deletes the plain-prose rule or softens the list block, these
    // tests fail loudly.

    private func prompt(
        style: DictationStyle,
        level: DictationLevel,
        formatLists: Bool = false,
        formatParagraphs: Bool = false
    ) -> String {
        DictationStyleEngine.makePrompt(
            style: style,
            level: level,
            formatLists: formatLists,
            formatParagraphs: formatParagraphs,
            screenContextTerms: [],
            transcript: "we should fix the API endpoint"
        )
    }

    func testBaseRulesContainPlainProseRule() {
        // The single most important guardrail against the "#1 / #2" bullet
        // spam the user reported on Developer + Soft. If this rule ever goes
        // missing, voices like Developer will start emitting markdown again.
        let p = prompt(style: .developer, level: .soft)
        XCTAssertTrue(p.contains("OUTPUT IS PLAIN PROSE"))
        XCTAssertTrue(p.contains("no numbered lists"))
        XCTAssertTrue(p.contains("no markdown"))
    }

    func testDeveloperVoiceDoesNotReferenceDocStyleFormats() {
        // The "PR description / design doc" framing was the source of the
        // user-reported bias toward bullets. Make sure it stays gone.
        let p = prompt(style: .developer, level: .soft)
        XCTAssertFalse(p.contains("PR description"))
        XCTAssertFalse(p.contains("design doc"))
        // But the terminology guidance survives:
        XCTAssertTrue(p.contains("APIs"))
        XCTAssertTrue(p.contains("refactor"))
    }

    func testListFormattingBlockIsAbsentWhenFormatListsOff() {
        // Rule 6 and the paragraph block legitimately *mention* the list
        // block by name; only the block itself (its header line) must be
        // absent when the toggle is off.
        let p = prompt(style: .developer, level: .soft, formatLists: false)
        XCTAssertFalse(p.contains("LIST FORMATTING (conditional override"))
    }

    func testListFormattingBlockRequiresVerbalMarkers() {
        // When list-formatting is on, the prompt still has to demand
        // explicit verbal markers and ban the "#1" shape Qwen invents.
        let p = prompt(style: .developer, level: .soft, formatLists: true)
        XCTAssertTrue(p.contains("LIST FORMATTING"))
        XCTAssertTrue(p.contains("at least TWO verbal list markers"))
        XCTAssertTrue(p.contains("\"#1\""))
        XCTAssertTrue(p.contains("\"1)\""))
    }

    func testNotesVoiceKeepsFragmentsInline() {
        // "Fragments are encouraged" used to read as license to bullet —
        // the prompt now spells out that fragments stay inline.
        let p = prompt(style: .notes, level: .soft)
        XCTAssertTrue(p.contains("remain INLINE"))
    }

    func testParagraphFormattingIsConservativeAndNotAFakeList() {
        let p = prompt(style: .conversation, level: .medium, formatParagraphs: true)
        XCTAssertTrue(p.contains("PARAGRAPH FORMATTING"))
        XCTAssertTrue(p.contains("NOT a substitute for list formatting"))
    }

    func testDeliberationLeakFallsBackToRaw() {
        // Condensed from a real leak: Qwen 3.5 narrating its editing
        // decisions in the answer channel instead of answering.
        let original = "I don't want people to have to scroll on the sign-in page. I'm thinking maybe we can remove the welcome message and just use that space."
        let leaked = """
        I don't want people to have to scroll on the sign-in page. Can you? \
        (the original text does not clearly state "or", it says "and") -> Actually, looking again at: \
        "you can either you can remove..." The speaker says "remove the welcome AND just use that [space]". \
        Let's stick strictly: "I don't want people to have to scroll." Wait, looking at rule 2: \
        "NEVER add information". Final decision: Keep the shorter version.
        """
        XCTAssertEqual(DictationStyleEngine.cleanOutput(leaked, original: original), "")
    }

    func testRunawayLengthFallsBackToRaw() {
        let original = "Please move the button to the left side of the toolbar for me."
        let runaway = String(repeating: "Considering the phrasing again and again. ", count: 30)
        XCTAssertEqual(DictationStyleEngine.cleanOutput(runaway, original: original), "")
    }

    func testNormalPolishPassesTheLeakGate() {
        let original = "um so I think we should uh ship the new settings panel on friday"
        let polished = "I think we should ship the new settings panel on Friday."
        XCTAssertEqual(DictationStyleEngine.cleanOutput(polished, original: original), polished)
    }
}
