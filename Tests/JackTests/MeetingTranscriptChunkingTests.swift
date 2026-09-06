import XCTest
@testable import Gilt

final class MeetingTranscriptChunkingTests: XCTestCase {
    private func makeChunk(start: Double, text: String) -> MeetingTranscriptChunk {
        MeetingTranscriptChunk(
            startTimeSeconds: start,
            endTimeSeconds: start + 4,
            text: text,
            engineRaw: MeetingTranscriptionEngine.whisperSmallMultilingual.rawValue
        )
    }

    func testEmptyTranscriptProducesNoWindows() {
        let chunker = MeetingTranscriptChunker()
        XCTAssertTrue(chunker.windows(from: []).isEmpty)
    }

    func testSmallTranscriptFitsInSingleWindow() {
        let chunker = MeetingTranscriptChunker(maxWindowCharacters: 1_000, overlapCharacters: 0)
        let chunks = (0..<4).map { makeChunk(start: Double($0) * 4, text: "Short line \($0)") }
        let windows = chunker.windows(from: chunks)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].count, 4)
    }

    func testLargeTranscriptSplitsIntoMultipleWindows() {
        let chunker = MeetingTranscriptChunker(maxWindowCharacters: 200, overlapCharacters: 0)
        let big = String(repeating: "z", count: 80)
        let chunks = (0..<8).map { makeChunk(start: Double($0) * 4, text: big) }
        let windows = chunker.windows(from: chunks)
        XCTAssertGreaterThan(windows.count, 1)
        let totalChunks = windows.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThanOrEqual(totalChunks, chunks.count)
    }

    func testOverlapIncludesPreviousWindowsTail() {
        let chunker = MeetingTranscriptChunker(maxWindowCharacters: 100, overlapCharacters: 60)
        let chunks = (0..<6).map { makeChunk(start: Double($0) * 4, text: String(repeating: "a", count: 40)) }
        let windows = chunker.windows(from: chunks)
        guard windows.count >= 2 else {
            XCTFail("Expected at least two windows for this size")
            return
        }
        XCTAssertFalse(windows[1].isEmpty, "Second window should retain at least one chunk of overlap")
    }

    func testRelevantChunksRankedByOverlap() {
        let chunker = MeetingTranscriptChunker()
        let chunks = [
            makeChunk(start: 0, text: "Discussion about the release timeline and the new pricing tier."),
            makeChunk(start: 4, text: "Coffee was cold."),
            makeChunk(start: 8, text: "We confirmed the pricing tier is launching Thursday."),
            makeChunk(start: 12, text: "Engineering will share the rollout plan tomorrow.")
        ]
        let result = chunker.mostRelevantChunks(for: "What pricing tier did we land on?", in: chunks, maxChunks: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.text.contains("pricing tier is launching Thursday") }))
    }

    func testRelevantChunksFallsBackToTrailingWhenNoOverlap() {
        let chunker = MeetingTranscriptChunker()
        let chunks = (0..<5).map { makeChunk(start: Double($0) * 4, text: "filler \($0)") }
        let result = chunker.mostRelevantChunks(for: "", in: chunks, maxChunks: 3)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map { $0.text }, ["filler 2", "filler 3", "filler 4"])
    }
}
