import XCTest
@testable import Gilt

/// Covers the cadence, parsing, and follow-up detection logic that drives the
/// dynamic "Ask" suggestions and richer Q&A answers.
final class MeetingSuggestedQuestionsTests: XCTestCase {
    // MARK: - Cadence

    func testRegenerateFiresOnFirstCall() {
        XCTAssertTrue(MeetingSessionController.shouldRegenerate(
            lastUpdate: nil,
            now: Date(),
            interval: 300
        ))
    }

    func testRegenerateWaitsUntilIntervalElapses() {
        let now = Date()
        let recent = now.addingTimeInterval(-60) // 1 minute ago
        XCTAssertFalse(MeetingSessionController.shouldRegenerate(
            lastUpdate: recent,
            now: now,
            interval: 300
        ))
    }

    func testRegenerateFiresAfterIntervalElapses() {
        let now = Date()
        let stale = now.addingTimeInterval(-310) // > 5 minutes ago
        XCTAssertTrue(MeetingSessionController.shouldRegenerate(
            lastUpdate: stale,
            now: now,
            interval: 300
        ))
    }

    // MARK: - Parsing

    func testParseSuggestedQuestionsReturnsArrayFromCleanJSON() {
        let raw = """
        [
          "What is the main point?",
          "Who is the speaker?",
          "What was the conclusion?",
          "How does this apply to me?"
        ]
        """
        let result = MeetingQuestionAnsweringService.parseSuggestedQuestions(raw)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.first, "What is the main point?")
    }

    func testParseSuggestedQuestionsCapsAtFour() {
        let raw = "[\"a?\", \"b?\", \"c?\", \"d?\", \"e?\", \"f?\"]"
        let result = MeetingQuestionAnsweringService.parseSuggestedQuestions(raw)
        XCTAssertEqual(result.count, 4)
    }

    func testParseSuggestedQuestionsHandlesProseWrappedJSON() {
        let raw = """
        Here are some good questions to ask:
        ["What did the speaker say?", "Why does it matter?", "What's next?", "Where can I learn more?"]
        Let me know if you want more.
        """
        let result = MeetingQuestionAnsweringService.parseSuggestedQuestions(raw)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.contains("What did the speaker say?"))
    }

    func testParseSuggestedQuestionsFallsBackToLineSplit() {
        let raw = """
        - What is the topic?
        - Who is involved?
        - What is at stake?
        - What happens next?
        """
        let result = MeetingQuestionAnsweringService.parseSuggestedQuestions(raw)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.contains(where: { $0.contains("topic") }))
    }

    // MARK: - Follow-up and overview detection

    func testFollowUpQuestionDetection() {
        XCTAssertTrue(MeetingQuestionAnsweringService.isFollowUpQuestion("Tell me more"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isFollowUpQuestion("Give me more details"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isFollowUpQuestion("Tell me more in detail"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isFollowUpQuestion("Can you elaborate?"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isFollowUpQuestion("Expand on that"))
        XCTAssertFalse(MeetingQuestionAnsweringService.isFollowUpQuestion("What was decided?"))
    }

    func testOverviewQuestionDetectionCoversTenses() {
        // Past tense was previously missed — "What was discussed" fell through
        // to keyword matching which returned shallow answers.
        XCTAssertTrue(MeetingQuestionAnsweringService.isOverviewQuestion("What was discussed"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isOverviewQuestion("What is being discussed"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isOverviewQuestion("What is this about?"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isOverviewQuestion("Catch me up"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isOverviewQuestion("Main points please"))
        XCTAssertTrue(MeetingQuestionAnsweringService.isOverviewQuestion("Give me a recap"))
        XCTAssertFalse(MeetingQuestionAnsweringService.isOverviewQuestion("Who is Barb?"))
    }
}
