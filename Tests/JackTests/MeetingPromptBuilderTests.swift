import XCTest
@testable import Gilt

/// Targets the prompt-shape changes introduced when we raised answer
/// substance, added follow-up handling, and started generating dynamic
/// suggested questions.
final class MeetingPromptBuilderTests: XCTestCase {
    func testAnswerPromptCapsLengthForRegularQuestion() {
        let builder = MeetingPromptBuilder(language: .english)
        let prompt = builder.answerPrompt(
            question: "What's the main point?",
            relevantChunks: [],
            rollingNotes: "",
            isFollowUp: false
        )
        XCTAssertTrue(prompt.contains("3 to 6 sentences"))
        XCTAssertFalse(prompt.contains("5 to 8 sentences"))
    }

    func testAnswerPromptExpandsForFollowUpQuestion() {
        let builder = MeetingPromptBuilder(language: .english)
        let prompt = builder.answerPrompt(
            question: "Tell me more in detail",
            relevantChunks: [],
            rollingNotes: "",
            isFollowUp: true
        )
        // Follow-ups should explicitly request more depth, not the regular cap.
        XCTAssertTrue(prompt.contains("5 to 8 sentences"))
        XCTAssertTrue(prompt.contains("follow-up"))
    }

    func testSuggestedQuestionsPromptAsksForExactlyFour() {
        let builder = MeetingPromptBuilder(language: .auto)
        let chunk = MeetingTranscriptChunk(
            startTimeSeconds: 0,
            endTimeSeconds: 5,
            text: "Today we are talking about leadership selection.",
            engineRaw: "test"
        )
        let prompt = builder.suggestedQuestionsPrompt(for: [chunk])
        XCTAssertTrue(prompt.contains("exactly 4 strings"))
        XCTAssertTrue(prompt.contains("JSON array"))
        // Must include the transcript so questions can be context-specific.
        XCTAssertTrue(prompt.contains("leadership selection"))
    }

    func testSummaryPromptAsksForFourToSevenBullets() {
        let builder = MeetingPromptBuilder(language: .english)
        let chunk = MeetingTranscriptChunk(
            startTimeSeconds: 0,
            endTimeSeconds: 5,
            text: "Sample line.",
            engineRaw: "test"
        )
        let prompt = builder.summaryPrompt(for: [chunk], previousNotes: nil)
        XCTAssertTrue(prompt.contains("4 to 7 substantive bullets"))
        XCTAssertTrue(prompt.contains("sermons and lectures"))
    }
}
