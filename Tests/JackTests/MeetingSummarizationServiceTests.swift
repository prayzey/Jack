import XCTest
@testable import Gilt

@MainActor
final class MeetingSummarizationServiceTests: XCTestCase {
    private func makeChunk(start: Double, text: String) -> MeetingTranscriptChunk {
        MeetingTranscriptChunk(
            startTimeSeconds: start,
            endTimeSeconds: start + 6,
            text: text,
            engineRaw: MeetingTranscriptionEngine.parakeetV2.rawValue
        )
    }

    func testFallbackBulletsDoNotIncludePresentationBullets() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let service = MeetingSummarizationService(modelsRoot: tempRoot)
        let summary = try await service.summarize(
            transcript: [
                makeChunk(start: 0, text: "We discussed the launch timeline."),
                makeChunk(start: 6, text: "Marketing will write the post.")
            ],
            previousSummary: nil,
            meetingID: UUID(),
            language: .english
        )

        XCTAssertFalse(summary.bullets.contains { $0.hasPrefix("•") })
    }

    func testSmokeSummarizesWithCachedQwenWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["GILT_QWEN_SMOKE"] == "1" else {
            throw XCTSkip("Set GILT_QWEN_SMOKE=1 to load the cached Qwen model and verify real AI summarization.")
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
        let service = MeetingSummarizationService(modelsRoot: modelsRoot)
        let chunks = [
            makeChunk(start: 0, text: "We agreed to price the launch tier at nineteen dollars."),
            makeChunk(start: 6, text: "Engineering will finish the migration before Thursday."),
            makeChunk(start: 12, text: "Marketing needs to draft the announcement post tomorrow morning.")
        ]
        let summary = try await service.summarize(
            transcript: chunks,
            previousSummary: nil,
            meetingID: UUID(),
            language: .english
        )

        XCTAssertFalse(summary.headline.isEmpty)
        XCTAssertFalse(summary.bullets.isEmpty)
        XCTAssertNotEqual(summary.bullets, chunks.map(\.text))
    }
}
