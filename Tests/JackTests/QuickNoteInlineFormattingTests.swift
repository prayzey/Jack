import AppKit
import XCTest
@testable import Gilt

@MainActor
final class QuickNoteInlineFormattingTests: XCTestCase {
    private let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor.white
    ]

    private func roundTrip(_ markdown: String) -> String {
        let attributed = QuickNoteInlineFormatting.attributedString(from: markdown, baseAttributes: base)
        return QuickNoteInlineFormatting.serialize(attributed)
    }

    // MARK: - Round-trip stability

    func testPlainTextRoundTripsUnchanged() {
        XCTAssertEqual(roundTrip("just some plain text"), "just some plain text")
    }

    func testExistingAsterisksAndUnderscoresAreNotTreatedAsFormatting() {
        // The whole reason for using <b>/<u> tags: real notes carry literal * and _.
        let id = "WHOGOHOST ID : 2292908_hkzh3qsnb1_GO54I and 3 * 4 = 12"
        XCTAssertEqual(roundTrip(id), id)
    }

    func testBoldRoundTrips() {
        XCTAssertEqual(roundTrip("a <b>bold</b> word"), "a <b>bold</b> word")
    }

    func testUnderlineRoundTrips() {
        XCTAssertEqual(roundTrip("an <u>underlined</u> word"), "an <u>underlined</u> word")
    }

    func testNestedBoldItalicRoundTripsInCanonicalOrder() {
        XCTAssertEqual(roundTrip("<b><i>both</i></b>"), "<b><i>both</i></b>")
        // Reversed nesting normalizes to the canonical bold>italic order.
        XCTAssertEqual(roundTrip("<i><b>both</b></i>"), "<b><i>both</i></b>")
    }

    func testFormattingSpanningMultipleWordsAndLines() {
        XCTAssertEqual(roundTrip("<b>line one\nline two</b>"), "<b>line one\nline two</b>")
    }

    // MARK: - Attributes actually applied

    func testParseAppliesBoldTrait() {
        let attributed = QuickNoteInlineFormatting.attributedString(from: "<b>x</b>", baseAttributes: base)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(attributed.string, "x")
    }

    func testParseAppliesUnderlineStyle() {
        let attributed = QuickNoteInlineFormatting.attributedString(from: "<u>x</u>", baseAttributes: base)
        let raw = attributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(raw, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(attributed.string, "x")
    }

    func testTagFreeParseEqualsPlainAttributedRun() {
        let parsed = QuickNoteInlineFormatting.attributedString(from: "hello", baseAttributes: base)
        XCTAssertEqual(parsed.string, "hello")
        XCTAssertFalse(parsed.containsInlineFormatting)
    }

    func testContainsInlineFormattingDetectsStyledRuns() {
        let bold = QuickNoteInlineFormatting.attributedString(from: "<b>x</b>", baseAttributes: base)
        XCTAssertTrue(bold.containsInlineFormatting)
        let plain = QuickNoteInlineFormatting.attributedString(from: "x", baseAttributes: base)
        XCTAssertFalse(plain.containsInlineFormatting)
    }

    // MARK: - Literal tag text typed by the user

    func testLiteralTagsAreEscapedOnSerialize() {
        // Regression: user-typed "<b>" survived until the next render, then
        // silently turned into formatting and the characters disappeared.
        let plain = NSAttributedString(string: "use <b> tags", attributes: base)
        XCTAssertEqual(QuickNoteInlineFormatting.serialize(plain), "use \\<b> tags")
    }

    func testEscapedTagsParseAsLiteralText() {
        let parsed = QuickNoteInlineFormatting.attributedString(from: "use \\<b> tags", baseAttributes: base)
        XCTAssertEqual(parsed.string, "use <b> tags")
        XCTAssertFalse(parsed.containsInlineFormatting)
    }

    func testLiteralTagRoundTripIsStable() {
        let plain = NSAttributedString(string: "literal <b> and </u> here", attributes: base)
        let saved = QuickNoteInlineFormatting.serialize(plain)
        let reloaded = QuickNoteInlineFormatting.attributedString(from: saved, baseAttributes: base)
        XCTAssertEqual(reloaded.string, plain.string)
        XCTAssertEqual(QuickNoteInlineFormatting.serialize(reloaded), saved)
    }

    func testUserTypedBackslashBeforeTagSurvives() {
        let plain = NSAttributedString(string: "\\<b>", attributes: base)
        let saved = QuickNoteInlineFormatting.serialize(plain)
        let reloaded = QuickNoteInlineFormatting.attributedString(from: saved, baseAttributes: base)
        XCTAssertEqual(reloaded.string, "\\<b>")
    }

    func testLiteralCloseTagInsideBoldRunRoundTrips() {
        let boldFont = QuickNoteInlineFormatting.styledFont(
            base: NSFont.systemFont(ofSize: 14),
            bold: true,
            italic: false
        )
        var attrs = base
        attrs[.font] = boldFont
        let source = NSAttributedString(string: "</b>", attributes: attrs)
        let saved = QuickNoteInlineFormatting.serialize(source)
        let reloaded = QuickNoteInlineFormatting.attributedString(from: saved, baseAttributes: base)
        XCTAssertEqual(reloaded.string, "</b>")
        XCTAssertTrue(reloaded.containsInlineFormatting)
    }

    func testEmojiSurvivesTagParsing() {
        // Regression: the parser walked UTF-16 units one at a time and
        // replaced surrogate halves with spaces, so emoji were destroyed in
        // any note that contained formatting tags.
        let parsed = QuickNoteInlineFormatting.attributedString(from: "<b>x</b> \u{1F642} ok", baseAttributes: base)
        XCTAssertEqual(parsed.string, "x \u{1F642} ok")
    }

    // MARK: - Integration through QuickNoteBodyRenderer (the real save/load path)

    private func rendererRoundTrip(_ markdown: String) -> (visible: String, saved: String) {
        let attributed = QuickNoteBodyRenderer.attributedString(
            from: markdown,
            noteID: UUID(),
            attachmentsRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            baseAttributes: base,
            maxImageWidth: 300
        )
        return (attributed.string, QuickNoteBodyRenderer.markdown(from: attributed))
    }

    func testRendererStripsTagsVisuallyAndRestoresThemOnSave() {
        let result = rendererRoundTrip("a <b>bold</b> and <u>underlined</u> note")
        XCTAssertEqual(result.visible, "a bold and underlined note")
        XCTAssertEqual(result.saved, "a <b>bold</b> and <u>underlined</u> note")
    }

    func testRendererLeavesUnformattedNotesByteIdentical() {
        // The critical safety property: existing notes with literal * and _ and
        // angle brackets in code are untouched by the formatting feature.
        let note = "id 2292908_hkzh3qsnb1_GO54I\n3 * 4 = 12\nif a < b { run() }"
        let result = rendererRoundTrip(note)
        XCTAssertEqual(result.visible, note)
        XCTAssertEqual(result.saved, note)
    }

    func testRendererEscapesLiteralTagsOnTheSaveFastPath() {
        // markdown(from:) takes a fast path for unformatted notes; it must
        // still escape literal tag text or the next load eats the characters.
        let typed = NSAttributedString(
            string: "use <b> tags here",
            attributes: base
        )
        let saved = QuickNoteBodyRenderer.markdown(from: typed)
        XCTAssertEqual(saved, "use \\<b> tags here")

        let reloaded = rendererRoundTrip(saved)
        XCTAssertEqual(reloaded.visible, "use <b> tags here")
        XCTAssertEqual(reloaded.saved, saved)
    }
}
