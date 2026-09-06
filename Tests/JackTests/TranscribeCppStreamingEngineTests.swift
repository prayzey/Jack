import AVFoundation
import XCTest

@testable import Gilt

/// End-to-end check of the transcribe.cpp subprocess bridge: real helper
/// binary, real GGUF model, real audio. Skips (rather than fails) on
/// machines that haven't run scripts/build-transcribe-helper.sh or
/// downloaded the unified model.
@MainActor
final class TranscribeCppStreamingEngineTests: XCTestCase {
    private var modelURL: URL {
        MeetingAppSupportLocator.transcriptionModelFolder(
            engine: .parakeetUnifiedStream,
            in: MeetingAppSupportLocator.modelsRoot(in: MeetingAppSupportLocator.meetingsRoot())
        ).appendingPathComponent(MeetingTranscriptionEngine.parakeetUnifiedStream.modelFileName)
    }

    func testOneShotTranscribesJFKSample() async throws {
        let engine = TranscribeCppStreamingEngine(modelURL: modelURL)
        try XCTSkipUnless(engine.isReady, "helper binary or unified model not installed")

        let wavURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // JackTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Vendor/transcribe.cpp/samples/jfk.wav")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: wavURL.path), "jfk.wav sample not present")

        let chunks = try await engine.transcribeFile(at: wavURL)
        let text = chunks.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("ask not what your country can do for you"), "got: \(text)")
    }

    // MARK: - Download integrity guards

    /// A garbage file (404 HTML body, truncated download) must never pass the
    /// GGUF magic check, so `isReady` reports false and dictation prompts a
    /// re-download instead of producing silence forever.
    func testIsReadyRejectsGarbageModelFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("garbage-\(UUID().uuidString).gguf")
        try Data("<!DOCTYPE html><html>not a model</html>".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let engine = TranscribeCppStreamingEngine(modelURL: tmp)
        XCTAssertFalse(engine.isReady, "a non-GGUF file must not register as Ready")
        XCTAssertFalse(TranscribeCppStreamingEngine.modelFileIsValid(at: tmp))
    }

    func testModelFileValidityAcceptsGGUFMagicAndRejectsMissing() throws {
        let good = FileManager.default.temporaryDirectory
            .appendingPathComponent("good-\(UUID().uuidString).gguf")
        // GGUF magic ("GGUF") + a little padding.
        try (Data([0x47, 0x47, 0x55, 0x46]) + Data(repeating: 0, count: 16)).write(to: good)
        defer { try? FileManager.default.removeItem(at: good) }
        XCTAssertTrue(TranscribeCppStreamingEngine.modelFileIsValid(at: good))

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).gguf")
        XCTAssertFalse(TranscribeCppStreamingEngine.modelFileIsValid(at: missing))
    }

    /// When the helper binary isn't installed, the stream must finish with a
    /// thrown error rather than ending empty — otherwise a missing helper
    /// yields a silently blank transcript with no way for the caller to know.
    func testStreamThrowsWhenHelperMissing() async throws {
        try XCTSkipUnless(
            TranscribeCppStreamingEngine.helperURL == nil,
            "helper binary is installed; can't exercise the missing-helper path"
        )
        let engine = TranscribeCppStreamingEngine(modelURL: modelURL)
        let emptyAudio = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let stream = engine.transcribeStream(from: emptyAudio, meetingStartedAt: Date())

        do {
            for try await _ in stream {}
            XCTFail("expected the stream to throw when the helper is missing")
        } catch let error as MeetingTranscriptionError {
            guard case .modelMissing = error else {
                return XCTFail("expected .modelMissing, got \(error)")
            }
        }
    }
}
