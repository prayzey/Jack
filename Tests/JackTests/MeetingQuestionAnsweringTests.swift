import XCTest
@testable import Gilt

@MainActor
final class MeetingQuestionAnsweringTests: XCTestCase {
    private func makeChunks() -> [MeetingTranscriptChunk] {
        [
            MeetingTranscriptChunk(
                startTimeSeconds: 0,
                endTimeSeconds: 6,
                text: "We aligned on a pricing tier of nineteen dollars for the launch.",
                engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
            ),
            MeetingTranscriptChunk(
                startTimeSeconds: 6,
                endTimeSeconds: 14,
                text: "Marketing will draft the announcement post tomorrow morning.",
                engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
            ),
            MeetingTranscriptChunk(
                startTimeSeconds: 14,
                endTimeSeconds: 22,
                text: "Engineering will ship the migration before Thursday.",
                engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
            )
        ]
    }

    func testAnswerPullsTheMostRelevantChunkAndCitesIt() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = MeetingQuestionAnsweringService(modelsRoot: tempRoot)
        let meetingID = UUID()
        let answer = try await service.answer(
            question: "What pricing did we settle on?",
            in: makeChunks(),
            rollingNotes: "",
            meetingID: meetingID,
            language: .english
        )

        XCTAssertEqual(answer.meetingID, meetingID)
        XCTAssertTrue(answer.answer.contains("pricing tier"),
                      "Answer should surface the chunk that talks about pricing")
        XCTAssertFalse(answer.citations.isEmpty, "Citations should be present")
        XCTAssertEqual(answer.citations.first?.startTimeSeconds, 0)
    }

    func testNoRelevantContentReturnsHonestNoEvidenceAnswer() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = MeetingQuestionAnsweringService(modelsRoot: tempRoot)
        let answer = try await service.answer(
            question: "What did the dog say?",
            in: makeChunks(),
            rollingNotes: "",
            meetingID: UUID(),
            language: .english
        )
        XCTAssertTrue(
            answer.citations.isEmpty,
            "Citations must be empty when no chunks share tokens with the question"
        )
        XCTAssertTrue(
            answer.answer.lowercased().contains("couldn't") || answer.answer.lowercased().contains("not"),
            "Answer should indicate the question wasn't covered"
        )
    }

    func testOverviewQuestionFallsBackToRecentTranscriptContext() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = MeetingQuestionAnsweringService(modelsRoot: tempRoot)
        let answer = try await service.answer(
            question: "What are they talking about?",
            in: makeChunks(),
            rollingNotes: "",
            meetingID: UUID(),
            language: .english
        )

        XCTAssertFalse(answer.citations.isEmpty)
        XCTAssertTrue(answer.answer.contains("discussion has covered"))
        XCTAssertTrue(answer.answer.contains("pricing") || answer.answer.contains("Marketing"))
    }

    func testGreetingDoesNotPretendTranscriptEvidenceExists() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = MeetingQuestionAnsweringService(modelsRoot: tempRoot)
        let answer = try await service.answer(
            question: "hi",
            in: makeChunks(),
            rollingNotes: "",
            meetingID: UUID(),
            language: .english
        )

        XCTAssertTrue(answer.citations.isEmpty)
        XCTAssertTrue(answer.answer.lowercased().contains("ask me"))
    }

    func testSmokeAnswersWithCachedQwenWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["GILT_QWEN_SMOKE"] == "1" else {
            throw XCTSkip("Set GILT_QWEN_SMOKE=1 to load the cached Qwen model and verify real AI Q&A.")
        }

        let meetingsRoot = MeetingAppSupportLocator.meetingsRoot()
        let modelsRoot = MeetingAppSupportLocator.modelsRoot(in: meetingsRoot)
        let qwenCache = MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: modelsRoot
        )
        guard QwenLocalLLM.cachedModelExists(in: qwenCache) else {
            throw XCTSkip("Cached Qwen model is not available at \(qwenCache.path).")
        }

        defer { QwenLocalLLM.shared.unload() }
        let service = MeetingQuestionAnsweringService(modelsRoot: modelsRoot)
        let answer = try await service.answer(
            question: "What did we decide about pricing and the timeline?",
            in: makeChunks(),
            rollingNotes: "",
            meetingID: UUID(),
            language: .english
        )

        XCTAssertFalse(answer.answer.contains("Based on what was said at"))
        XCTAssertFalse(answer.answer.contains("The recent discussion covers:"))
        XCTAssertTrue(answer.answer.lowercased().contains("pricing"))
    }
}
