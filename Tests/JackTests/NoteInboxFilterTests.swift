import XCTest
@testable import Gilt

final class NoteInboxFilterTests: XCTestCase {

    func testPlainProseIsInbox() {
        XCTAssertTrue(NoteInboxFilter.isInbox("Just a quick thought."))
    }

    func testEmptyBodyIsInbox() {
        XCTAssertTrue(NoteInboxFilter.isInbox(""))
    }

    func testWikilinkRemovesFromInbox() {
        XCTAssertFalse(NoteInboxFilter.isInbox("see [[Project Apollo]]"))
    }

    func testFrontmatterTypeRemovesFromInbox() {
        let body = """
        ---
        type: project
        ---

        no links yet
        """
        XCTAssertFalse(NoteInboxFilter.isInbox(body))
    }

    func testEmptyTypeStringStillCountsAsInbox() {
        // `type:` with no value is the same as no type at all.
        let body = """
        ---
        type:
        ---

        body
        """
        XCTAssertTrue(NoteInboxFilter.isInbox(body))
    }

    func testWikilinkInsideFrontmatterDoesNotClassify() {
        // A `[[…]]` accidentally typed inside the YAML block shouldn't kick
        // the note out of the inbox — it isn't a "real" outgoing link.
        let body = """
        ---
        rough_note: [[ignored]]
        ---

        plain body
        """
        XCTAssertTrue(NoteInboxFilter.isInbox(body))
    }

    func testWikilinkInsideCodeFenceDoesNotClassify() {
        let body = """
        ```
        example [[ignored]]
        ```
        """
        XCTAssertTrue(NoteInboxFilter.isInbox(body))
    }

    func testTypeAndWikilinkTogetherStillRemovesFromInbox() {
        let body = """
        ---
        type: person
        ---

        meeting with [[Sam]]
        """
        XCTAssertFalse(NoteInboxFilter.isInbox(body))
    }
}
