import XCTest
@testable import Gilt

final class LiveCaptionComposerTests: XCTestCase {
    func testMergeWindowedFirstChunkIsFullyProvisional() {
        let state = LiveCaptionComposer.mergeWindowed(
            accumulated: "",
            previousWindow: "",
            currentWindow: "hello world"
        )
        XCTAssertEqual(state.text, "hello world")
        XCTAssertEqual(state.stableWordCount, 0)
    }

    func testMergeWindowedAppendsDeltaWithStablePrefix() {
        let state = LiveCaptionComposer.mergeWindowed(
            accumulated: "hello",
            previousWindow: "hello",
            currentWindow: "hello world"
        )
        XCTAssertEqual(state.text, "hello world")
        XCTAssertEqual(state.stableWordCount, 1)
    }

    func testPublishableLiveStateSkipsVocabMatcher() {
        let raw = LiveCaptionComposer.State(text: "um chat g p t", stableWordCount: 0)
        let published = LiveCaptionComposer.publishableLiveState(from: raw)
        XCTAssertEqual(published.text, "chat g p t")
    }

    func testSplitStableProvisional() {
        let parts = LiveCaptionComposer.splitStableProvisional("one two three", stableWordCount: 2)
        XCTAssertEqual(parts.stable, "one two")
        XCTAssertEqual(parts.provisional, "three")
    }
}