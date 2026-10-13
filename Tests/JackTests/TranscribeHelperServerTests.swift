import AVFoundation
import XCTest
@testable import Gilt

/// Runs only when `JACK_PARAKEET_MODEL` points at the downloaded GGUF and
/// `JACK_SPEECH_SAMPLE` at a short English recording, because the model is
/// 731 MB and not part of the repo.
@MainActor
final class TranscribeHelperServerTests: XCTestCase {
    func testDictationsReuseTheLoadedModelAndCancelledSessionsStayIsolated() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let modelPath = env["JACK_PARAKEET_MODEL"], let samplePath = env["JACK_SPEECH_SAMPLE"],
              let helper = TranscribeCppStreamingEngine.helperURL else {
            throw XCTSkip("Set JACK_PARAKEET_MODEL and JACK_SPEECH_SAMPLE to run against the real model")
        }
        let engine = TranscribeCppStreamingEngine(modelURL: URL(fileURLWithPath: modelPath), helperURL: helper)
        let samples = try TranscribeCppStreamingEngine.loadSamples16kMono(from: URL(fileURLWithPath: samplePath))

        let coldStart = Date()
        try await engine.warmUp()
        let cold = Date().timeIntervalSince(coldStart)

        let first = try await dictate(samples, with: engine)
        XCTAssertTrue(first.text.lowercased().contains("design review"), first.text)

        // A dictation cancelled midway must not leak its replies into the next one.
        let cancelled = Task { try await dictate(Array(samples.prefix(samples.count / 2)), with: engine, paced: true) }
        try await Task.sleep(for: .milliseconds(300))
        cancelled.cancel()
        _ = try? await cancelled.value

        let second = try await dictate(samples, with: engine)
        XCTAssertEqual(second.text, first.text)
        XCTAssertLessThan(second.seconds, 3, "The second dictation reuses the loaded model (cold load took \(cold)s)")

        let refined = await engine.refinedTranscript(from: samples)
        XCTAssertNotNil(refined)
        XCTAssertTrue(TranscriptCleaner.sameWords(refined ?? "", first.text) || (refined ?? "").lowercased().contains("design review"))

        engine.releaseWarm()
        let refinedAfterRelease = await engine.refinedTranscript(from: samples)
        XCTAssertNil(refinedAfterRelease, "Releasing frees the helper")
    }

    func testFullRecordingPassOnlyReplacesTheLiveTextWhenWordsChange() {
        XCTAssertTrue(TranscriptCleaner.sameWords("Hey Sam, can we meet?", "hey sam can we meet"))
        XCTAssertTrue(TranscriptCleaner.sameWords("I'll ship it.", "I'll ship it"))
        XCTAssertFalse(TranscriptCleaner.sameWords("but churn is high", "but Chen is high"))
        XCTAssertFalse(TranscriptCleaner.sameWords("the new notifications", "the new notification"))
    }

    private func dictate(
        _ samples: [Float], with engine: TranscribeCppStreamingEngine, paced: Bool = false
    ) async throws -> (text: String, seconds: Double) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let audio = AsyncStream<AVAudioPCMBuffer> { continuation in
            Task {
                for offset in stride(from: 0, to: samples.count, by: 1600) {
                    let count = min(1600, samples.count - offset)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                    buffer.frameLength = AVAudioFrameCount(count)
                    samples.withUnsafeBufferPointer {
                        buffer.floatChannelData![0].update(from: $0.baseAddress!.advanced(by: offset), count: count)
                    }
                    continuation.yield(buffer)
                    if paced { try? await Task.sleep(for: .milliseconds(100)) }
                }
                continuation.finish()
            }
        }
        let start = Date()
        var text = ""
        for try await chunk in engine.transcribeStream(from: audio, meetingStartedAt: start) {
            text = chunk.text
        }
        return (text, Date().timeIntervalSince(start))
    }
}
