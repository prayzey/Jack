import XCTest
@testable import Gilt

final class MeetingSummaryPromptTests: XCTestCase {
    private func makeChunk(start: Double, text: String) -> MeetingTranscriptChunk {
        MeetingTranscriptChunk(
            startTimeSeconds: start,
            endTimeSeconds: start + 4,
            text: text,
            engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
        )
    }

    func testSummaryPromptIncludesAllChunksWithTimestamps() {
        let builder = MeetingPromptBuilder(language: .english)
        let chunks = [
            makeChunk(start: 0, text: "Welcome to the launch sync."),
            makeChunk(start: 60, text: "Engineering wants to ship Thursday.")
        ]
        let prompt = builder.summaryPrompt(for: chunks, previousNotes: nil)
        XCTAssertTrue(prompt.contains("[00:00] Welcome to the launch sync."))
        XCTAssertTrue(prompt.contains("[01:00] Engineering wants to ship Thursday."))
    }

    func testSummaryPromptDeclaresJSONShape() {
        let builder = MeetingPromptBuilder(language: .english)
        let prompt = builder.summaryPrompt(for: [], previousNotes: nil)
        for key in ["headline", "bullets", "decisions", "actionItems", "followUpQuestions"] {
            XCTAssertTrue(prompt.contains("\"\(key)\""), "Prompt should request \(key) field")
        }
        XCTAssertTrue(prompt.contains("substantive bullets"))
        XCTAssertTrue(prompt.contains("Never fabricate"))
    }

    func testSummaryPromptInjectsPreviousNotes() {
        let builder = MeetingPromptBuilder(language: .english)
        let prompt = builder.summaryPrompt(
            for: [makeChunk(start: 0, text: "next agenda item.")],
            previousNotes: "Already covered: timelines"
        )
        XCTAssertTrue(prompt.contains("Already covered: timelines"))
    }

    func testAnswerPromptCitesRelevantChunksAndQuestion() {
        let builder = MeetingPromptBuilder(language: .spanish)
        let chunks = [makeChunk(start: 120, text: "Decidimos lanzar el martes.")]
        let prompt = builder.answerPrompt(
            question: "Cuando lanzamos?",
            relevantChunks: chunks,
            rollingNotes: ""
        )
        XCTAssertTrue(prompt.contains("Cuando lanzamos?"))
        XCTAssertTrue(prompt.contains("[02:00] Decidimos lanzar el martes."))
        XCTAssertTrue(prompt.contains("Language: es"))
        XCTAssertTrue(prompt.contains("Lead with the direct answer"))
    }

    func testAnswerPromptSurfacesNoEvidenceCaseGracefully() {
        let builder = MeetingPromptBuilder(language: .english)
        let prompt = builder.answerPrompt(question: "what?", relevantChunks: [], rollingNotes: "")
        XCTAssertTrue(prompt.contains("(none matched"))
    }
}
