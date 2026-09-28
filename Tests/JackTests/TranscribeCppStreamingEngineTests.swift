import AVFoundation
import XCTest

@testable import Gilt

/// End-to-end check of the transcribe.cpp subprocess bridge: real helper
/// binary, real GGUF model, real audio. Skips (rather than fails) on
/// machines that haven't run scripts/build-transcribe-helper.sh or
/// downloaded the unified model.
@MainActor
final class TranscribeCppStreamingEngineTests: XCTestCase {
    func testCorruptModelReportsFailureInsteadOfSuccessfulEmptyTranscript() async throws {
        try XCTSkipUnless(TranscribeCppStreamingEngine.helperURL != nil, "helper not installed")
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID()).gguf")
        try Data("GGUF".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        let engine = TranscribeCppStreamingEngine(modelURL: corrupt)
        do {
            _ = try await engine.transcribeSamples([])
            XCTFail("A helper that exits without a final transcript must throw")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

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

    func testPacedStreamingPublishesWordsBeforeAudioFinishes() async throws {
        let engine = TranscribeCppStreamingEngine(modelURL: modelURL)
        try XCTSkipUnless(engine.isReady, "helper binary or unified model not installed")
        let wavURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/transcribe.cpp/samples/jfk.wav")
        let file = try AVAudioFile(forReading: wavURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        let audio = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let started = Date()
        var audioEndedAt: Date?
        let writer = Task {
            defer { audio.continuation.finish(); audioEndedAt = Date() }
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(100))
                audio.continuation.yield(try Self.readBuffer(from: file))
            }
        }
        defer { writer.cancel(); audio.continuation.finish() }
        var firstPartialAt: Date?
        var latest = ""
        var updateCount = 0
        for try await chunk in engine.transcribeStream(from: audio.stream, meetingStartedAt: started) {
            if !chunk.text.isEmpty, firstPartialAt == nil { firstPartialAt = Date() }
            latest = chunk.text
            updateCount += 1
        }
        try await writer.value
        let first = try XCTUnwrap(firstPartialAt)
        let ended = try XCTUnwrap(audioEndedAt)
        XCTAssertLessThan(first, ended, "Streaming should show words while speech is still arriving")
        XCTAssertGreaterThan(updateCount, 1)
        XCTAssertTrue(latest.lowercased().contains("ask not what your country can do for you"))
        print("[dictation-benchmark] first-partial=\(first.timeIntervalSince(started))s finalize=\(Date().timeIntervalSince(ended))s updates=\(updateCount)")
    }

    nonisolated private static func readBuffer(from file: AVAudioFile) throws -> sending AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600))
        try file.read(into: buffer)
        return buffer
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

    func testModelFileValidityRejectsHeaderOnlyFileAndMissing() throws {
        let good = FileManager.default.temporaryDirectory
            .appendingPathComponent("good-\(UUID().uuidString).gguf")
        // GGUF magic ("GGUF") + a little padding.
        try (Data([0x47, 0x47, 0x55, 0x46]) + Data(repeating: 0, count: 16)).write(to: good)
        defer { try? FileManager.default.removeItem(at: good) }
        XCTAssertFalse(TranscribeCppStreamingEngine.modelFileIsValid(at: good))

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).gguf")
        XCTAssertFalse(TranscribeCppStreamingEngine.modelFileIsValid(at: missing))
    }

    /// When the helper binary isn't installed, the stream must finish with a
    /// thrown error rather than ending empty — otherwise a missing helper
    /// yields a silently blank transcript with no way for the caller to know.
    func testStreamThrowsWhenHelperMissing() async throws {
        let engine = TranscribeCppStreamingEngine(modelURL: modelURL, helperURL: nil)
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

    func testHelperExitMustIncludeSuccessfulFinalization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("helper-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        for (output, exitCode, expected) in [
            (#"JT>{"final":""}"#, 0, Optional("")),
            (#"JT>{"final":"complete"}"#, 0, Optional("complete")),
            (#"JT>{"committed":"partial","tentative":"guess"}"#, 0, nil),
            (#"JT>{"final":"incomplete"}"#, 1, nil)
        ] {
            try "#!/bin/sh\nprintf '%s\\n' '\(output)'\nexit \(exitCode)\n".write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            let engine = TranscribeCppStreamingEngine(modelURL: modelURL, helperURL: helper)
            do {
                let result = try await engine.transcribeSamples([])
                XCTAssertEqual(result, expected, "Non-final or failed output must throw")
            } catch {
                XCTAssertNil(expected, "A successful final result should not throw: \(error)")
            }
        }
    }

    func testCancellingStreamTerminatesHelperWithoutWaitingForAudioEOF() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("helper-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        let pidFile = root.appendingPathComponent("pid")
        try "#!/bin/sh\necho $$ > \"$1\"\nprintf '%s\\n' 'JT>{\"ready\":true}'\nexec /bin/sleep 30\n"
            .write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let engine = TranscribeCppStreamingEngine(modelURL: pidFile, helperURL: helper)
        let task = Task {
            for try await _ in engine.transcribeStream(from: AsyncStream { _ in }, meetingStartedAt: Date()) {}
        }
        defer { task.cancel() }
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        let stoppedBy = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0, Date() < stoppedBy {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(kill(pid, 0), -1, "Cancel must stop the helper even while audio is open")
    }

    func testStreamingAudioWriteAfterHelperClosesInputReportsError() async throws {
        // XCTest may ignore SIGPIPE, so exercise the real stream in a child
        // with the signal's normal fatal disposition.
        if ProcessInfo.processInfo.environment["JACK_TEST_SIGPIPE_CHILD"] != "1" {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = [
                "xctest", "-XCTest",
                "JackTests.TranscribeCppStreamingEngineTests/testStreamingAudioWriteAfterHelperClosesInputReportsError",
                Bundle(for: Self.self).bundlePath
            ]
            child.environment = ProcessInfo.processInfo.environment.merging(["JACK_TEST_SIGPIPE_CHILD": "1"]) { _, new in new }
            try child.run()
            let deadline = Date().addingTimeInterval(10)
            while child.isRunning, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
            XCTAssertEqual(child.terminationReason, .exit, "Stream write killed the test child with signal \(child.terminationStatus)")
            XCTAssertEqual(child.terminationStatus, 0, "Stream write regression failed in isolated test child")
            return
        }
        let previousSignalHandler = signal(SIGPIPE, SIG_DFL)
        defer { _ = signal(SIGPIPE, previousSignalHandler) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("helper-closed-input-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        let readyFile = root.appendingPathComponent("ready")
        try "#!/bin/sh\nexec 0<&-\necho ready > \"$1\"\nprintf '%s\\n' 'JT>{\"ready\":true}'\nexec /bin/sleep 30\n"
            .write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        let engine = TranscribeCppStreamingEngine(modelURL: readyFile, helperURL: helper)
        let audio = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let task = Task {
            for try await _ in engine.transcribeStream(from: audio.stream, meetingStartedAt: Date()) {}
        }
        defer { audio.continuation.finish(); task.cancel() }
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: readyFile.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard FileManager.default.fileExists(atPath: readyFile.path) else {
            return XCTFail("Helper did not close stdin")
        }

        audio.continuation.yield(try Self.silentBuffer())
        do {
            try await task.value
            XCTFail("Writing audio to a helper with closed stdin must report an error")
        } catch {
            XCTAssertFalse(error is CancellationError, "The failed pipe write should surface before cancellation")
        }
    }

    nonisolated private static func silentBuffer() throws -> sending AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        buffer.floatChannelData?[0].update(repeating: 0, count: 1600)
        return buffer
    }
}
