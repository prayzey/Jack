import AppKit
import AVFoundation
import CryptoKit
import SwiftUI
import XCTest
@testable import Gilt

@MainActor
final class DictationUpgradeTests: XCTestCase {
    private final class ModelLifetimeProbe { var stops = 0 }

    func testSuccessfulDeadlineReleasesItsModelBeforeReturning() async throws {
        weak var released: ModelLifetimeProbe?
        func run() async throws {
            let model = ModelLifetimeProbe()
            released = model
            _ = try await GenerationDeadline.run(seconds: 60, onStop: { model.stops += 1 }) { "done" }
        }
        try await run()
        XCTAssertNil(released, "A cancelled timer must not retain a completed model")
    }
    func testDeadlineReturnsWhileUncooperativeOperationKeepsOwnership() async throws {
        var finish: CheckedContinuation<String, Never>?
        var stopped = 0
        var completed = 0
        let started = Date()
        do {
            _ = try await GenerationDeadline.run(
                seconds: 0.03, onStop: { stopped += 1 }, onCompletion: { completed += 1 }
            ) {
                await withCheckedContinuation { finish = $0 }
            }
            XCTFail("A stalled model must time out")
        } catch GenerationDeadline.Failure.timedOut {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(completed, 0, "Timeout must not release the still-running model")
        finish?.resume(returning: "late output must be discarded")
        for _ in 0..<100 where completed == 0 { await Task.yield() }
        XCTAssertEqual(completed, 1)
    }

    func testCancellationReturnsPromptlyAndDoesNotStopTheNextOperation() async throws {
        var finish: CheckedContinuation<String, Never>?
        var stopped = 0
        let task = Task {
            try await GenerationDeadline.run(seconds: 10, onStop: { stopped += 1 }) {
                await withCheckedContinuation { finish = $0 }
            }
        }
        while finish == nil { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        finish?.resume(returning: "old")
        let next = try await GenerationDeadline.run(seconds: 1) { "next" }
        XCTAssertEqual(next, "next")
        XCTAssertEqual(stopped, 1)
    }

    func testTentativeWordsNeverEnterLivePolishAndStayProvisional() async {
        var inputs: [String] = []
        let polisher = LiveDictationPolisher(prepare: { $0 }, polishChunk: { inputs.append($0); return $0 })
        let confirmed = "Send this to my colleague."
        polisher.ingest(committedRaw: confirmed)
        await polisher.finishSession()
        let state = polisher.compose(
            cumulativeRaw: confirmed + " Their name might change completely as recognition catches up.",
            committedRaw: confirmed
        )
        XCTAssertEqual(inputs, [confirmed])
        XCTAssertEqual(state?.stableWordCount, 5)
        XCTAssertTrue(state?.text.contains("catches up") == true)
        XCTAssertEqual(LiveDictationPolisher.polishablePrefix(in: "all six words are confirmed now", lastPrefixWordCount: 0), "all six words are confirmed now")
    }

    func testSubwordBoundaryNeitherAddsSpacesNorPolishesAnIncompleteWord() {
        let update = StreamingTranscriptUpdate(committed: "Turn on the micro", tentative: "phone now")
        XCTAssertEqual(update.text, "Turn on the microphone now")
        XCTAssertEqual(update.confirmedText, "Turn on the ")
        XCTAssertEqual(StreamingTranscriptUpdate(committed: "Hello", tentative: " there").confirmedText, "Hello")
        XCTAssertEqual(StreamingTranscriptUpdate(committed: "Hello", isFinal: true).confirmedText, "Hello")
    }

    func testAudioTapOwnsItsSamplesAndBoundsQueuedWork() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let queue = DispatchQueue(label: "dictation-test-audio")
        let stream = DictationAudioStreamWrapper()
        let sink = DictationAudioTapSink(targetFormat: format, targetSampleRate: 16_000, streamWrapper: stream, queue: queue)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80))
        buffer.frameLength = 80
        buffer.floatChannelData![0].initialize(repeating: 0.25, count: 80)
        queue.suspend()
        sink.handle(rawBuffer: buffer)
        buffer.floatChannelData![0].update(repeating: 0.9, count: 80)
        queue.resume()
        XCTAssertEqual(sink.drainAndSnapshot(), Array(repeating: 0.25, count: 80), "The tap's reused buffer must not change queued audio")
        queue.suspend()
        for _ in 0..<65 { sink.handle(rawBuffer: buffer) }
        queue.resume()
        _ = sink.drainAndSnapshot()
        XCTAssertEqual(sink.failure, .overloaded)
        XCTAssertEqual(sink.sampleCount, 65 * 80, "The overflow buffer must not grow the queue")
        stream.finish()
    }

    func testRewriteRejectsLostNumbersAddressesAndMostOfTheTranscript() {
        let original = "Send the 50 dollar invoice to john.smith@example.com and use https://example.com/pay for payment."
        XCTAssertEqual(DictationStyleEngine.validatedOutput(original.replacingOccurrences(of: "50", with: "150"), original: original), original)
        XCTAssertEqual(DictationStyleEngine.validatedOutput("Send the 50 dollar invoice to John Smith.", original: original), original)
        XCTAssertEqual(DictationStyleEngine.validatedOutput(original + " Thank you.", original: original), original + " Thank you.")
        let long = Array(repeating: "keep these useful words", count: 15).joined(separator: " ")
        XCTAssertEqual(DictationStyleEngine.validatedOutput("Short summary.", original: long), long)
    }

    func testChangedOrMissingDestinationCopiesWithoutPostingPaste() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var posts = 0
        let service = DictationPasteService(pasteboard: board, postPaste: { posts += 1; return true }, targetIsCurrent: { _ in false })
        let target = DictationPasteTarget(pid: 1, element: AXUIElementCreateApplication(1), valueDigest: SHA256.hash(data: Data()), selection: nil)
        let changed = await service.paste(text: "safe draft", target: target)
        let missing = await service.paste(text: "latest draft", target: nil)
        XCTAssertFalse(changed)
        XCTAssertFalse(missing)
        XCTAssertEqual(posts, 0)
        XCTAssertEqual(board.string(forType: .string), "latest draft")
        XCTAssertNil(CapturedClip.fromPasteboard(board), "History opt-out must cover manual-paste fallbacks")
        service.copyOnly("explicitly saved", saveToHistory: true)
        XCTAssertNotNil(CapturedClip.fromPasteboard(board))
    }

    func testHistoryOptOutPreservesOldEntriesAndStoresNoNewText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-history-\(UUID())")
        let suite = "dictation-history-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(defaults: defaults, rootURL: root)
        let old = DictationHistoryEntry(text: "Finished text.", rawTranscript: "original words", style: .conversation, level: .soft, durationSeconds: 3)
        store.appendHistory(old)
        store.settings.saveDictationHistory = false
        store.appendHistory(DictationHistoryEntry(text: "do not retain", rawTranscript: "private", style: .conversation, level: .none, durationSeconds: 1))
        let restored = DictationStore(defaults: defaults, rootURL: root)
        XCTAssertEqual(restored.history, [old])
        XCTAssertFalse(restored.settings.saveDictationHistory)
        let path = root.appendingPathComponent("history.json")
        XCTAssertFalse(try String(contentsOf: path, encoding: .utf8).contains("private"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        restored.deleteHistoryEntry(old.id)
        XCTAssertTrue(DictationStore(defaults: defaults, rootURL: root).history.isEmpty)
    }

    func testModelIntegrityRejectsSameSizeCorruption() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("integrity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("GGUFcomplete-model".utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try bytes.write(to: url)
        XCTAssertTrue(try TranscribeCppStreamingEngine.modelIntegrityMatches(at: url, expectedBytes: Int64(bytes.count), expectedSHA256: hash))
        try Data("GGUFcorrupted-file".utf8).write(to: url)
        XCTAssertEqual(TranscribeCppStreamingEngine.fileSize(at: url), Int64(bytes.count))
        XCTAssertFalse(try TranscribeCppStreamingEngine.modelIntegrityMatches(at: url, expectedBytes: Int64(bytes.count), expectedSHA256: hash))
    }

    func testNativeHelperKeepsTheActualCommittedBoundary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stream-boundary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        try #"""
        #!/bin/sh
        printf '%s\n' 'JT>{"committed":"send","tentative":"to Alice before noon or later"}' 'JT>{"committed":"send to","tentative":"Bob"}' 'JT>{"final":"Send to Bob."}'
        """#.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let engine = TranscribeCppStreamingEngine(modelURL: root, helperURL: helper)
        var updates: [StreamingTranscriptUpdate] = []
        for try await chunk in engine.transcribeStream(from: AsyncStream { $0.finish() }, meetingStartedAt: Date()) {
            updates.append(try XCTUnwrap(chunk.streamingUpdate))
        }
        XCTAssertEqual(updates.map(\.committed), ["send", "send to", "Send to Bob."])
        XCTAssertEqual(updates.map(\.isFinal), [false, false, true])
    }

    func testAppleSpeechStreamsTheSamePacedPublicSample() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = AppleSpeechTranscriptionEngine(locale: Locale(identifier: "en-US"))
        engine.vocabularyHints = ["Americans", "country"]
        await engine.refreshAvailability()
        try XCTSkipUnless(engine.isReady, "Apple speech assets are not installed")
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/transcribe.cpp/samples/jfk.wav")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let input = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let started = Date()
        var ended: Date?
        let writer = Task {
            defer { input.continuation.finish(); ended = Date() }
            while file.framePosition < file.length {
                try await Task.sleep(for: .milliseconds(100))
                input.continuation.yield(try Self.readBuffer(file))
            }
        }
        defer { writer.cancel(); input.continuation.finish() }
        var first: Date?
        var latest: StreamingTranscriptUpdate?
        var count = 0
        for try await chunk in engine.transcribeStream(from: input.stream, meetingStartedAt: started) {
            if !chunk.text.isEmpty, first == nil { first = Date() }
            latest = chunk.streamingUpdate
            count += 1
        }
        try await writer.value
        XCTAssertLessThan(try XCTUnwrap(first), try XCTUnwrap(ended))
        XCTAssertTrue(latest?.isFinal == true)
        XCTAssertTrue(latest?.text.lowercased().contains("ask not what your country can do for you") == true, "\(latest?.text ?? "empty")")
        print("[apple-speech-benchmark] first-partial=\(first!.timeIntervalSince(started))s finalize=\(Date().timeIntervalSince(ended!))s updates=\(count)")
    }

    func testAppleSpeechCancellationDoesNotWaitForMicrophoneEOF() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires macOS 26") }
        let engine = AppleSpeechTranscriptionEngine(locale: Locale(identifier: "en-US"))
        engine.vocabularyHints = ["Americans", "country"]
        await engine.refreshAvailability()
        try XCTSkipUnless(engine.isReady, "Apple speech assets are not installed")
        let task = Task {
            for try await _ in engine.transcribeStream(from: AsyncStream { _ in }, meetingStartedAt: Date()) {}
            try Task.checkCancellation()
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = try await GenerationDeadline.run(seconds: 2) {
            do { try await task.value; return "finished" }
            catch is CancellationError { return "cancelled" }
        }
        XCTAssertEqual(result, "cancelled")
    }

    func testRenderRecoveryAndModelSettingsWhenRequested() async throws {
        guard let output = ProcessInfo.processInfo.environment["JACK_DICTATION_SNAPSHOTS"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-render-\(UUID())")
        let suite = "dictation-render-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(defaults: defaults, rootURL: root)
        store.appendHistory(DictationHistoryEntry(
            text: "Please send the updated proposal to Alex before Friday. Keep the budget at $50,000.",
            rawTranscript: "please send the updated proposal to alex before friday keep the budget at 50,000",
            style: .professional, level: .soft, durationSeconds: 9
        ))
        store.appendHistory(DictationHistoryEntry(
            text: "I need onions, bread, and butter for tonight.",
            rawTranscript: "I need tomatoes. Actually no, I meant onions and also some bread and butter for tonight.",
            style: .conversation, level: .medium, durationSeconds: 6
        ))
        for (name, view, height) in [
            ("recent-dictations", DictationSettingsView(initialTab: .history), CGFloat(760)),
            ("speech-models", DictationSettingsView(initialTab: .advanced), CGFloat(1220))
        ] {
            let host = NSHostingView(rootView: view.environmentObject(store).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(SettingsTheme.background).preferredColorScheme(.light))
            host.appearance = NSAppearance(named: .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 740, height: height)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        }
    }

    nonisolated private static func readBuffer(_ file: AVAudioFile) throws -> sending AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600))
        try file.read(into: buffer)
        return buffer
    }
}
