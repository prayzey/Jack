import XCTest
@testable import Gilt

@MainActor
final class ParakeetTranscriptionEngineTests: XCTestCase {
    func testSmokeTranscribesRealAudioWhenExplicitlyEnabled() async throws {
        guard let path = ProcessInfo.processInfo.environment["GILT_PARAKEET_SMOKE_AUDIO"] else {
            throw XCTSkip("Set GILT_PARAKEET_SMOKE_AUDIO to run the real cached-model transcription smoke test.")
        }

        let audioURL = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        let modelsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("JackParakeetSmoke", isDirectory: true)
        let modelURL = modelsRoot
            .appendingPathComponent(MeetingTranscriptionEngine.parakeetV2.rawValue, isDirectory: true)
            .appendingPathComponent(MeetingTranscriptionEngine.parakeetV2.modelFileName)
        let engine = ParakeetTranscriptionEngine(modelURL: modelURL)

        let chunks = try await engine.transcribeFile(at: audioURL)
        let text = chunks.map(\.text).joined(separator: " ")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
