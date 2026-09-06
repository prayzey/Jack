import AVFoundation
import Foundation
import OSLog

/// Speech-to-text engine backed by transcribe.cpp's `parakeet-unified-en-0.6b`
/// GGUF model via the bundled `jack-transcribe-stream` helper binary.
///
/// Unlike the FluidAudio engines (in-process CoreML on the Neural Engine),
/// this engine runs inference in a subprocess: raw 16 kHz mono f32 PCM goes
/// into the helper's stdin, and cumulative transcript updates come back as
/// `JT>{"committed":...,"tentative":...}` JSON lines on stdout. The model is
/// a *native* streaming model, so partials are committed text — no windowed
/// re-decode, no second full decode on key release.
///
/// The subprocess boundary is deliberate: it keeps ggml/Metal out of the app
/// process (a crash there can't take Jack down) and avoids linking C++ into
/// the SwiftPM build. Model load is ~0.2s, so spawn-per-session is fine.
@MainActor
final class TranscribeCppStreamingEngine: MeetingTranscriptionEngineProtocol {
    let engineID: MeetingTranscriptionEngine = .parakeetUnifiedStream

    private let modelURL: URL
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "TranscribeCppEngine")

    init(modelURL: URL) {
        self.modelURL = modelURL
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
        // Cheap but real: a nonzero file that starts with the GGUF magic.
        // A truncated download or a 404 HTML body would otherwise register
        // as "ready" and then produce silence forever.
        Self.modelFileIsValid(at: modelURL) && Self.helperURL != nil
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
        // Nothing to preload — the helper loads the GGUF in ~0.2s per session.
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
    /// `DictationCoordinator`'s `yieldsCumulativeLiveText` handling.
    func transcribeStream(
        from audio: AsyncStream<AVAudioPCMBuffer>,
        meetingStartedAt: Date
    ) -> AsyncThrowingStream<MeetingTranscriptChunk, Error> {
        let modelPath = modelURL.path
        let helperPath = Self.helperURL?.path
        let engine = engineID
        let engineRaw = engineID.rawValue

        return AsyncThrowingStream { continuation in
            Task(priority: .userInitiated) {
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

                    // Reader and writer run concurrently: the writer pumps
                    // mic buffers into stdin; the reader yields a chunk per
                    // transcript update. stdin EOF (audio stream ended)
                    // triggers finalize inside the helper, which emits the
                    // "final" line and exits. Dictation ignores chunk
                    // timestamps, so they stay zero here.
                    let readerTask = Task {
                        for try await update in session.updates() {
                            let text = update.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }
                            continuation.yield(MeetingTranscriptChunk(
                                startTimeSeconds: 0,
                                endTimeSeconds: 0,
                                text: text,
                                engineRaw: engineRaw
                            ))
                        }
                    }

                    for await buffer in audio {
                        let samples = WhisperTranscriptionEngine.extractMonoSamples(from: buffer)
                        guard !samples.isEmpty else { continue }
                        session.feed(samples)
                    }
                    session.closeInput()
                    try await readerTask.value
                    session.terminate()
                    continuation.finish()
                } catch {
                    Logger(subsystem: AppBrand.logSubsystem, category: "TranscribeCppEngine")
                        .error("Streaming session failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// One-shot decode: pipe the whole buffer through a fresh helper session.
    /// The streaming decode IS the high-quality path for this model, so this
    /// is only hit for re-transcription / file imports / non-live fallbacks.
    func transcribeSamples(_ samples: [Float]) async throws -> String {
        guard let helperPath = Self.helperURL?.path else {
            throw MeetingTranscriptionError.modelMissing(engine: engineID)
        }
        let modelPath = modelURL.path
        return try await Task.detached(priority: .userInitiated) {
            let session = try TranscribeHelperSession(helperPath: helperPath, modelPath: modelPath)
            let readerTask = Task { () -> String in
                var latest = ""
                for try await update in session.updates() {
                    latest = update
                }
                return latest
            }
            session.feed(samples)
            session.closeInput()
            let latest = try await readerTask.value
            session.terminate()
            return latest.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
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
        // 160ms chunk / 160ms right context = 320ms lookahead — the
        // low-latency entry in the model's training menu (WER 1.64%).
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
            Task {
                do {
                    for try await line in handle.bytes.lines {
                        // ggml/Metal may print diagnostics to stdout; only
                        // lines with the JT> prefix are protocol lines.
                        guard line.hasPrefix("JT>"),
                              let data = line.dropFirst(3).data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let final = obj["final"] as? String {
                            continuation.yield(final)
                        } else if obj["ready"] == nil {
                            let committed = obj["committed"] as? String ?? ""
                            let tentative = obj["tentative"] as? String ?? ""
                            let joined = tentative.isEmpty ? committed : committed + " " + tentative
                            continuation.yield(joined)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func feed(_ samples: [Float]) {
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        // Pipe writes only block if the helper stops draining; it reads
        // continuously, and live audio is just 64 KB/s, so this stays cheap.
        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
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
