@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Speech-to-text engine backed by transcribe.cpp's `parakeet-unified-en-0.6b`
/// GGUF model via the bundled `jack-transcribe-stream` helper binary.
///
/// Unlike the FluidAudio engines (in-process CoreML on the Neural Engine),
/// this engine runs inference in a subprocess: raw 16 kHz mono f32 PCM goes
/// into the helper's stdin, and cumulative transcript updates come back as
/// `JT>{"committed":...,"tentative":...}` JSON lines on stdout. The model is
/// streaming model; partials contain both committed and tentative text.
/// Key release finalizes this stream without a second whole-recording decode.
///
/// The subprocess boundary is deliberate: it keeps ggml/Metal out of the app
/// process (a crash there can't take Jack down) and avoids linking C++ into
/// the SwiftPM build. Each session loads the model in its own helper.
@MainActor
final class TranscribeCppStreamingEngine: MeetingTranscriptionEngineProtocol {
    let engineID: MeetingTranscriptionEngine = .parakeetUnifiedStream

    private let modelURL: URL
    private let helperExecutableURL: URL?
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "TranscribeCppEngine")

    init(modelURL: URL, helperURL: URL? = TranscribeCppStreamingEngine.helperURL) {
        self.modelURL = modelURL
        self.helperExecutableURL = helperURL
    }

    // MARK: - Helper binary location

    /// Search order: Contents/MacOS beside the main executable (shipped
    /// builds — build-app.sh embeds and signs it there), then the shared
    /// Application Support bin (dev installs via scripts/build-transcribe-helper.sh).
    nonisolated static var helperURL: URL? {
        var candidates: [URL] = []
        if let executable = Bundle.main.executableURL {
            candidates.append(
                executable.deletingLastPathComponent().appendingPathComponent("jack-transcribe-stream")
            )
        }
        candidates.append(
            AppSupportLocator.giltDirectory()
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("jack-transcribe-stream")
        )
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isReady: Bool {
        // This is a presence/header check. Successful helper finalization is
        // checked separately; a valid header does not prove a complete model.
        Self.modelFileIsValid(at: modelURL) && helperExecutableURL != nil
    }

    /// A model file we're willing to load: present, nonzero, and starting
    /// with the ASCII GGUF magic (`0x47 0x47 0x55 0x46`). Reads 4 bytes, so
    /// it's cheap enough for the `isReady` main-path check.
    nonisolated static func modelFileIsValid(at url: URL) -> Bool {
        fileSize(at: url) > 0 && ggufMagicIsValid(at: url)
    }

    nonisolated static func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    nonisolated static func ggufMagicIsValid(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 4)) ?? Data()
        return header == Data([0x47, 0x47, 0x55, 0x46])
    }

    func warmUp() async throws {
        guard isReady else {
            throw MeetingTranscriptionError.modelMissing(engine: engineID)
        }
        // The helper loads the GGUF when a session starts.
    }

    // MARK: - Download

    /// Direct single-file download from Hugging Face with real progress and
    /// integrity validation. Mirrors the proven `QwenLocalLLM` download path:
    /// `downloadTask` streams to a temp file (fast, resumable, and it surfaces
    /// a real error on a dropped connection instead of a truncated "success"),
    /// and we only move it into place after the HTTP status, byte count, and
    /// GGUF magic bytes all check out. Any failure deletes the partial so a
    /// retry starts clean.
    func prefetch(reportingProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        if Self.modelFileIsValid(at: modelURL) {
            reportingProgress(1.0)
            return
        }
        guard let remote = engineID.directDownloadURL else {
            throw MeetingTranscriptionError.modelMissing(engine: engineID)
        }
        let parentDir = modelURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // A stale partial (nonzero but invalid) from an earlier failed run
        // would block the move below — clear it before we start.
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try? FileManager.default.removeItem(at: modelURL)
        }

        let expectedSize = engineID.approximateDownloadSizeBytes
        // FIX 5: fail fast if the volume can't hold the model (+20% headroom
        // for the temp copy that lives alongside the final file during the move).
        let requiredBytes = Int64(Double(expectedSize) * 1.2)
        if let available = meetingVolumeImportantCapacity(at: parentDir), available < requiredBytes {
            throw MeetingTranscriptionError.insufficientDiskSpace(
                requiredBytes: requiredBytes,
                availableBytes: available
            )
        }

        var request = URLRequest(url: remote)
        request.setValue("Jack/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 1800

        let destination = modelURL
        let engine = engineID
        let observerHolder = QwenProgressObserverHolder<QwenProgressObserver>()
        let (received, expected): (Int64, Int64) = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
                defer { observerHolder.clear() }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    continuation.resume(throwing: MeetingTranscriptionError.modelDownloadFailed(engine: engine))
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: MeetingTranscriptionError.modelDownloadFailed(engine: engine))
                    return
                }
                let received = Self.fileSize(at: tempURL)
                let expected = response?.expectedContentLength ?? expectedSize
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume(returning: (received, expected))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observerHolder.store(QwenProgressObserver(task: task) { fraction, _ in
                Task { @MainActor in reportingProgress(min(0.999, fraction)) }
            })
            task.resume()
        }

        // Integrity gate: reject a truncated body, then confirm the GGUF magic
        // so a complete-but-corrupt file (hijacked redirect, HTML error page)
        // can't masquerade as the model.
        if expected > 0, Double(received) / Double(expected) < 0.98 {
            try? FileManager.default.removeItem(at: destination)
            throw MeetingTranscriptionError.modelDownloadFailed(engine: engineID)
        }
        guard Self.modelFileIsValid(at: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw MeetingTranscriptionError.modelDownloadFailed(engine: engineID)
        }
        reportingProgress(1.0)
    }

    // MARK: - Streaming

    /// Native streaming: each yielded chunk carries the *cumulative*
    /// transcript so far (committed + tentative), not a time-window slice.
    /// Consumers must replace, not append — see
    /// `DictationCoordinator`'s native-stream handling.
    func transcribeStream(
        from audio: AsyncStream<AVAudioPCMBuffer>,
        meetingStartedAt: Date
    ) -> AsyncThrowingStream<MeetingTranscriptChunk, Error> {
        let modelPath = modelURL.path
        let helperPath = helperExecutableURL?.path
        let engine = engineID
        let engineRaw = engineID.rawValue
        let input = TranscribeAudioStream(buffers: audio)

        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { continuation.finish(); return }
                guard let helperPath else {
                    // No helper on disk — finish with a real error so the
                    // consumer shows "model not downloaded" instead of a
                    // silently blank transcript.
                    continuation.finish(throwing: MeetingTranscriptionError.modelMissing(engine: engine))
                    return
                }
                do {
                    // Throws on x86_64 (unsupported architecture) or a spawn
                    // failure — both now surface to the caller.
                    let session = try TranscribeHelperSession(helperPath: helperPath, modelPath: modelPath)
                    defer { session.terminate() }

                    // Reader and writer run concurrently: the writer pumps
                    // mic buffers into stdin; the reader yields a chunk per
                    // transcript update. stdin EOF (audio stream ended)
                    // triggers finalize inside the helper, which emits the
                    // "final" line and exits. Dictation ignores chunk
                    // timestamps, so they stay zero here.
                    try await withTaskCancellationHandler {
                        let readerTask = Task {
                            do {
                                for try await update in session.updates() {
                                    try Task.checkCancellation()
                                    // An empty final update must replace an earlier guess, too.
                                    continuation.yield(MeetingTranscriptChunk(
                                        startTimeSeconds: 0,
                                        endTimeSeconds: 0,
                                        text: update.trimmingCharacters(in: .whitespacesAndNewlines),
                                        engineRaw: engineRaw
                                    ))
                                }
                            } catch {
                                // Fail while the microphone is still open; don't wait for
                                // another key release to discover a dead helper.
                                continuation.finish(throwing: error)
                                session.terminate()
                                throw error
                            }
                        }
                        defer { readerTask.cancel() }
                        for await buffer in input.buffers {
                            try Task.checkCancellation()
                            let samples = WhisperTranscriptionEngine.extractMonoSamples(from: buffer)
                            guard !samples.isEmpty else { continue }
                            try session.feed(samples)
                        }
                        session.closeInput()
                        try await readerTask.value
                        try Task.checkCancellation()
                    } onCancel: {
                        // Killing the child also releases any blocked pipe read/write.
                        session.terminate()
                    }
                    continuation.finish()
                } catch {
                    Logger(subsystem: AppBrand.logSubsystem, category: "TranscribeCppEngine")
                        .error("Streaming session failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One-shot decode: pipe the whole buffer through a fresh helper session.
    /// The streaming decode IS the high-quality path for this model, so this
    /// is only hit for re-transcription / file imports / non-live fallbacks.
    func transcribeSamples(_ samples: [Float]) async throws -> String {
        guard let helperPath = helperExecutableURL?.path else {
            throw MeetingTranscriptionError.modelMissing(engine: engineID)
        }
        let modelPath = modelURL.path
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let session = try TranscribeHelperSession(helperPath: helperPath, modelPath: modelPath)
            defer { session.terminate() }
            return try await withTaskCancellationHandler {
                let readerTask = Task { () -> String in
                    var latest = ""
                    for try await update in session.updates() {
                        try Task.checkCancellation()
                        latest = update
                    }
                    return latest
                }
                defer { readerTask.cancel() }
                try session.feed(samples)
                session.closeInput()
                let latest = try await readerTask.value
                try Task.checkCancellation()
                return latest.trimmingCharacters(in: .whitespacesAndNewlines)
            } onCancel: {
                session.terminate()
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func transcribeFile(at audioURL: URL) async throws -> [MeetingTranscriptChunk] {
        let samples = try Self.loadSamples16kMono(from: audioURL)
        let text = try await transcribeSamples(samples)
        guard !text.isEmpty else { return [] }
        return [MeetingTranscriptChunk(
            startTimeSeconds: 0,
            endTimeSeconds: Double(samples.count) / 16_000,
            text: text,
            engineRaw: engineID.rawValue
        )]
    }

    // MARK: - Audio file loading

    private static func loadSamples16kMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw MeetingTranscriptionError.audioReadFailed(underlying: nil)
        }

        var samples: [Float] = []
        let inCapacity: AVAudioFrameCount = 32_768
        var reachedEnd = false
        while !reachedEnd {
            let outCapacity = AVAudioFrameCount(
                Double(inCapacity) * targetFormat.sampleRate / file.processingFormat.sampleRate
            ) + 1024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
                break
            }
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { packetCount, outStatus in
                guard let inBuffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: min(packetCount, inCapacity)
                ) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer)
                } catch {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inBuffer
            }
            if let conversionError {
                throw MeetingTranscriptionError.audioReadFailed(underlying: conversionError)
            }
            if outBuffer.frameLength > 0, let data = outBuffer.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(outBuffer.frameLength)))
            }
            if status == .endOfStream || outBuffer.frameLength == 0 {
                reachedEnd = true
            }
        }
        return samples
    }
}

// MARK: - Helper subprocess

/// AVAudioPCMBuffer predates Sendable. Capture publishes independent copies;
/// this stream has one consumer, which only reads them on the worker task.
private struct TranscribeAudioStream: @unchecked Sendable {
    let buffers: AsyncStream<AVAudioPCMBuffer>
}

/// Wraps one `jack-transcribe-stream` process: PCM in via stdin, transcript
/// lines out via stdout. Not tied to any actor — created and used inside a
/// single detached task per session.
private final class TranscribeHelperSession: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()

    init(helperPath: String, modelPath: String) throws {
        // FIX 3: the helper is built arm64-only (scripts/build-transcribe-helper.sh).
        // An x86_64 process can't exec it — posix_spawn would fail with a
        // generic error. Fail early and clearly instead. This one guard covers
        // both the streaming and one-shot paths since both spawn through here.
        #if arch(x86_64)
        throw MeetingTranscriptionError.unsupportedArchitecture(engine: .parakeetUnifiedStream)
        #else
        process.executableURL = URL(fileURLWithPath: helperPath)
        // Current product setting: 320ms of audio lookahead. This excludes
        // microphone startup, inference, caption publication, and polishing.
        process.arguments = [modelPath, "160", "160"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        #endif
    }

    /// Cumulative transcript per protocol line. "committed tentative" joined
    /// for partials; the bare final text for the terminal line.
    func updates() -> AsyncThrowingStream<String, Error> {
        let handle = stdoutPipe.fileHandleForReading
        return AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                do {
                    var receivedFinal = false
                    for try await line in handle.bytes.lines {
                        try Task.checkCancellation()
                        // ggml/Metal may print diagnostics to stdout; only
                        // lines with the JT> prefix are protocol lines.
                        guard line.hasPrefix("JT>"),
                              let data = line.dropFirst(3).data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let final = obj["final"] as? String {
                            receivedFinal = true
                            continuation.yield(final)
                        } else if obj["ready"] == nil {
                            let committed = obj["committed"] as? String ?? ""
                            let tentative = obj["tentative"] as? String ?? ""
                            let joined = tentative.isEmpty ? committed : committed + " " + tentative
                            continuation.yield(joined)
                        }
                    }
                    process.waitUntilExit()
                    try Task.checkCancellation()
                    guard receivedFinal, process.terminationStatus == 0 else {
                        throw MeetingTranscriptionError.transcriptionFailed
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func feed(_ samples: [Float]) throws {
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        // Pipe writes only block if the helper stops draining; it reads
        // continuously, and live audio is just 64 KB/s, so this stays cheap.
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func closeInput() {
        try? stdinPipe.fileHandleForWriting.close()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}
