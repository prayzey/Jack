import Foundation
@preconcurrency import LLM
import OSLog

/// Singleton wrapper around `LLM.swift` for the locally-hosted Qwen 3.5 4B model.
/// Shared by `MeetingSummarizationService` and `MeetingQuestionAnsweringService`
/// so we don't load the model twice.
///
/// The model is downloaded from `unsloth/Qwen3.5-4B-GGUF` on Hugging Face (Q4_K_M
/// quantization). We bypass `LLM.swift`'s `HuggingFaceModel.download(...)` path
/// because its HTML-scraping regex fails against the modern Hugging Face page
/// — the `.gguf?download=true` regex greedy-matches across the whole HTML
/// document instead of one link per file. We download the file ourselves and
/// hand `LLM` the on-disk URL, which is the supported "bundled" init path.
@MainActor
final class QwenLocalLLM {
    static let shared = QwenLocalLLM()

    /// Public Hugging Face repo. Alibaba's own `Qwen/Qwen3.5-*-GGUF` repos are
    /// gated behind HF auth and would 401 on download; unsloth mirrors are
    /// public.
    nonisolated static let huggingFaceModelID = "unsloth/Qwen3.5-4B-GGUF"
    /// Q4_K_M quantization filename within the repo. Hugging Face exposes a
    /// stable `resolve/main/<filename>` URL that streams the raw bytes after a
    /// signed-redirect, so we can fetch it with plain URLSession.
    nonisolated static let modelFileName = "Qwen3.5-4B-Q4_K_M.gguf"
    nonisolated private static let expectedMinimumBytes: Int64 = 2_000_000_000 // ~2 GB sanity floor

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "QwenLLM")
    private var bot: LLM?
    private var loadingTask: Task<Void, Error>?
    /// True while the GGUF is actively being fetched over the network.
    /// Used by `ensureLoadedFromCache` to fail fast instead of awaiting a
    /// multi-gigabyte download — dictation must never block its paste on a
    /// download it didn't ask for. Stays true across the download phase
    /// only; the disk → llama.cpp load phase clears it before warming the
    /// model into memory.
    private var isDownloadingFile = false
    /// True while a `generate` call is mid-`respond` — see the guard there.
    private var isGenerating = false

    private init() {}

    var isLoaded: Bool { bot != nil }

    nonisolated static func cachedModelURL(in cacheDirectory: URL) -> URL {
        cacheDirectory.appendingPathComponent(modelFileName)
    }

    nonisolated static func cachedModelExists(in cacheDirectory: URL) -> Bool {
        let destination = cachedModelURL(in: cacheDirectory)
        return fileSize(at: destination) >= expectedMinimumBytes && ggufMagicIsValid(at: destination)
    }

    /// Ensure the Qwen model is downloaded and loaded into memory. Progress is
    /// reported in 0...1 across the download phase; the load phase is treated
    /// as the trailing few percent.
    func ensureLoaded(
        cacheDirectory: URL,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        if bot != nil {
            MeetingDownloadLog.log("Qwen already loaded — skipping ensureLoaded")
            return
        }
        if let loadingTask {
            MeetingDownloadLog.log("Qwen load already in flight — awaiting existing task")
            try await loadingTask.value
            return
        }
        MeetingDownloadLog.log("Qwen ensureLoaded() — cacheDir=\(cacheDirectory.path)")
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            let destination = Self.cachedModelURL(in: cacheDirectory)
            let sourceURL = URL(
                string: "https://huggingface.co/\(Self.huggingFaceModelID)/resolve/main/\(Self.modelFileName)"
            )!

            // 1. Download (if needed) with real byte-level progress. We
            // explicitly validate file integrity here because a previous
            // partial download (CDN connection dropped, sleep, etc.) leaves
            // a small file on disk that `llama_model_load_from_file` will
            // reject as malformed — yielding a useless "Couldn't load from
            // disk" error with no way to recover.
            let onDiskSize = Self.fileSize(at: destination)
            if Self.cachedModelExists(in: cacheDirectory) {
                self.logger.info("Qwen GGUF already on disk at \(destination.path) (\(onDiskSize) bytes)")
                await MainActor.run { onProgress(0.95) }
            } else {
                if onDiskSize > 0 {
                    self.logger.warning("Removing partial Qwen GGUF (\(onDiskSize) bytes, expected ~2.4 GB)")
                    try? FileManager.default.removeItem(at: destination)
                }
                self.isDownloadingFile = true
                do {
                    try await self.downloadFile(
                        from: sourceURL,
                        to: destination,
                        onProgress: onProgress
                    )
                    self.isDownloadingFile = false
                } catch {
                    self.isDownloadingFile = false
                    throw error
                }
            }

            // 2. Load the model from disk.
            try await self.loadModel(from: destination, onProgress: onProgress)
        }
        loadingTask = task
        defer { loadingTask = nil }
        try await task.value
    }

    /// Load the local model only if the GGUF is already cached. This is used by
    /// meeting summary/Q&A so asking a question can use AI after app relaunch
    /// without silently starting a multi-gigabyte download.
    @discardableResult
    func ensureLoadedFromCache(
        cacheDirectory: URL,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> Bool {
        if bot != nil { return true }
        // Never block on an in-flight download. Callers like the dictation
        // post-processor must paste raw text immediately if Qwen isn't ready
        // — waiting for a 2.4 GB transfer would freeze paste for the user.
        // The next call after the download finishes will see the cache and
        // succeed.
        if isDownloadingFile { return false }
        if let loadingTask {
            // Only the disk → llama.cpp load phase can land here (download
            // phase short-circuits above). That phase is ~1-2s, so awaiting
            // it is fine.
            try await loadingTask.value
            return bot != nil
        }
        guard Self.cachedModelExists(in: cacheDirectory) else { return false }
        try await loadModel(from: Self.cachedModelURL(in: cacheDirectory), onProgress: onProgress)
        return true
    }

    /// Run a single non-streaming completion. Resets per-call so prior calls
    /// don't bleed context — meeting prompts are self-contained.
    ///
    /// `maxOutputCharacters` hard-stops generation once the output exceeds
    /// the cap. Qwen 3.5 is a reasoning model and occasionally deliberates
    /// in its answer channel despite the suppressed-thinking prefill —
    /// unbounded, that produces multi-thousand-token runaways that pin the
    /// GPU for minutes (audible as coil whine) and stall the caller. Callers
    /// that expect output proportional to their input (dictation polish)
    /// must pass a cap; open-ended callers (meeting summaries) may omit it.
    /// `onPartial` (optional) receives the cumulative raw output every poll
    /// tick while generation runs — the dictation overlay uses it to show the
    /// polish "writing itself". Same poll mechanism as the cap watchdog: the
    /// stream API's closure variant is not Sendable-clean, but `bot.output`
    /// grows incrementally during respond(), so a main-actor poll is safe.
    func generate(
        prompt: String,
        maxOutputCharacters: Int? = nil,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        // llama.cpp shares one context per LLM instance — two concurrent
        // respond() calls interleave tokens and can crash the backend. The
        // live dictation polisher and the final polish pass (or the meeting
        // summarizer) can overlap, so serialize here, at the choke point.
        // ponytail: poll-wait, not a queue — callers are rare and short.
        while isGenerating {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let bot else { throw QwenLLMError.notLoaded }
        isGenerating = true
        defer { isGenerating = false }
        bot.history = []

        var watchdog: Task<Void, Never>?
        if maxOutputCharacters != nil || onPartial != nil {
            let cap = maxOutputCharacters
            watchdog = Task { @MainActor [weak bot] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard let bot, !Task.isCancelled else { return }
                    let output = bot.output
                    onPartial?(output)
                    if let cap, output.count > cap {
                        bot.stop()
                        return
                    }
                }
            }
        }
        await bot.respond(to: prompt, thinking: .suppressed)
        watchdog?.cancel()
        return bot.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Eagerly tear down the model — frees memory when the user deletes it
    /// from the Models panel.
    func unload() {
        bot = nil
        LLM.shutdownBackend()
    }

    // MARK: - Download

    private func loadModel(
        from destination: URL,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws {
        MeetingDownloadLog.log("Loading Qwen GGUF into llama.cpp…")
        let loadStart = Date()
        // Greedy, seeded decoding — NOT the library defaults (random seed,
        // temp 0.8). Every consumer of this model transforms user text
        // (dictation polish, meeting summaries, screen Q&A); sampled decoding
        // made outputs vary run-to-run and occasionally drop content
        // outright (e.g. rewriting "john.smith@gmail.com" to "John Smith").
        // Determinism here is a correctness feature, not a style choice.
        guard let loaded = LLM(
            from: destination,
            seed: 42,
            topK: 1,
            topP: 1.0,
            temp: 0,
            maxTokenCount: 4096
        ) else {
            let elapsed = Date().timeIntervalSince(loadStart)
            MeetingDownloadLog.log("LLM.init returned nil after \(String(format: "%.1f", elapsed))s — wiping file")
            try? FileManager.default.removeItem(at: destination)
            throw QwenLLMError.loadFailed
        }
        let loadElapsed = Date().timeIntervalSince(loadStart)
        MeetingDownloadLog.log("Qwen model loaded in \(String(format: "%.1f", loadElapsed))s")
        loaded.useResolvedTemplate(
            systemPrompt: "You are Jack, a precise meeting note-taker. Stay concise, never invent facts, and respect the requested output format.",
            modelName: Self.huggingFaceModelID
        )
        loaded.postprocess = { _ in }
        bot = loaded
        await MainActor.run { onProgress(1.0) }
        MeetingDownloadLog.log("Qwen ready ✅")
    }

    /// Streams a file from `source` to `destination`, validating the final
    /// size against the response's `expectedContentLength` so a silently
    /// truncated stream (CDN dropped, idle timeout, etc.) doesn't leave a
    /// useless partial file masquerading as a finished download.
    ///
    /// We use `URLSession.download(for:)` rather than `bytes(for:)` because
    /// the download API:
    ///   - Streams to a temp file with built-in resume semantics
    ///   - Reports byte-level progress via the URLSessionTask's
    ///     `progress.fractionCompleted` (Foundation `Progress`, KVO-driven)
    ///   - Surfaces a real error when the connection drops instead of
    ///     returning a successful "done" with a truncated body
    /// Downloads a file using `URLSession.shared.downloadTask` (the
    /// chunk-streaming HTTP downloader, same one curl uses internally) with
    /// KVO progress observation on `task.progress`. We tried two simpler
    /// approaches first, both broken for our use case:
    ///   1. `URLSession.download(for:)` with a custom delegate-session — hung
    ///      before opening a socket. Never reached the network.
    ///   2. `URLSession.shared.bytes(for:)` with `for try await byte in …` —
    ///      opened cleanly and streamed bytes, but at ~0.1 MB/s (70× slower
    ///      than curl on the same URL). The async byte-by-byte iterator pays
    ///      a continuation hop per byte, which dominates for a 2.4 GB file.
    /// Plain downloadTask with KVO is the right tool for multi-GB transfers.
    private func downloadFile(
        from source: URL,
        to destination: URL,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws {
        // Fail fast if the volume can't hold the ~2.4 GB model (+20% headroom
        // for the temp copy that lives beside the final file during the move).
        let requiredBytes = Int64(Double(MeetingSummarizationEngine.qwen35_4b_q4.approximateDownloadSizeBytes) * 1.2)
        if let available = meetingVolumeImportantCapacity(at: destination.deletingLastPathComponent()),
           available < requiredBytes {
            MeetingDownloadLog.log("Qwen download aborted — need \(requiredBytes) bytes, \(available) free")
            throw QwenLLMError.insufficientDiskSpace(requiredBytes: requiredBytes, availableBytes: available)
        }

        var request = URLRequest(url: source)
        request.setValue("Jack/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 1800

        MeetingDownloadLog.log("Starting Qwen download")
        MeetingDownloadLog.log("  source: \(source.absoluteString)")
        MeetingDownloadLog.log("  destination: \(destination.path)")
        MeetingDownloadLog.resetCounter("[qwen]")

        let downloadStart = Date()
        let expectedFallback = MeetingSummarizationEngine.qwen35_4b_q4.approximateDownloadSizeBytes

        // Run the download under URLSession.shared with a completion handler;
        // observe `task.progress.fractionCompleted` via KVO to drive our UI
        // and stdout logs. The temp file is only valid inside the completion
        // block, so the atomic move happens there before we resume.
        let progressObserver = QwenProgressObserverHolder<QwenProgressObserver>()
        let (movedDestination, received, expected): (URL, Int64, Int64) = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
                defer { progressObserver.clear() }
                if let error {
                    MeetingDownloadLog.log("Qwen task error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    MeetingDownloadLog.log("Qwen HTTP error: status=\(code)")
                    continuation.resume(throwing: QwenLLMError.downloadFailed(statusCode: code))
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: QwenLLMError.loadFailed)
                    return
                }
                let received = Self.fileSize(at: tempURL)
                let expected = response?.expectedContentLength ?? expectedFallback
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume(returning: (destination, received, expected))
                } catch {
                    MeetingDownloadLog.log("Qwen file move failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }

            // Keep the KVO observer alive until URLSession calls the completion
            // handler. A local-only observer deinitializes right after resume,
            // which leaves the download working but the UI stuck at 0%.
            progressObserver.store(QwenProgressObserver(task: task) { fraction, mbPerSec in
                let scaled = min(0.95, fraction * 0.95)
                MeetingDownloadLog.progress(
                    "[qwen] \(String(format: "%.2f", mbPerSec)) MB/s",
                    fraction: fraction,
                    totalBytes: task.countOfBytesExpectedToReceive > 0
                        ? task.countOfBytesExpectedToReceive
                        : expectedFallback
                )
                Task { @MainActor in onProgress(scaled) }
            })

            task.resume()
            MeetingDownloadLog.log("Qwen downloadTask resumed")
        }

        let elapsed = Date().timeIntervalSince(downloadStart)
        let avgMBPerSec = Double(received) / 1_000_000.0 / max(elapsed, 0.001)
        MeetingDownloadLog.log(
            "Qwen download complete: received=\(received) expected=\(expected) "
                + "elapsed=\(String(format: "%.1f", elapsed))s avg=\(String(format: "%.2f", avgMBPerSec)) MB/s"
        )

        // Size sanity-check now that the file is in its final location.
        let sanityFloor: Int64 = 2_000_000_000
        if expected > 0 {
            let tolerance = Double(received) / Double(expected)
            if tolerance < 0.98 {
                try? FileManager.default.removeItem(at: movedDestination)
                MeetingDownloadLog.log("Qwen TRUNCATED: \(received) / \(expected) bytes (\(Int(tolerance * 100))%)")
                throw QwenLLMError.truncated(received: received, expected: expected)
            }
        } else if received < sanityFloor {
            try? FileManager.default.removeItem(at: movedDestination)
            MeetingDownloadLog.log("Qwen too small: \(received) bytes, no content-length")
            throw QwenLLMError.truncated(received: received, expected: sanityFloor)
        }

        guard Self.ggufMagicIsValid(at: movedDestination) else {
            try? FileManager.default.removeItem(at: movedDestination)
            MeetingDownloadLog.log("Qwen GGUF magic byte check FAILED — file deleted")
            throw QwenLLMError.loadFailed
        }
        MeetingDownloadLog.log("Qwen GGUF magic bytes OK — proceeding to load")
        await MainActor.run { onProgress(0.95) }
    }

    // MARK: - File helpers

    nonisolated private static func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    /// GGUF files start with the ASCII magic `GGUF` (0x47 0x47 0x55 0x46).
    /// Catches the case where we got a complete-but-corrupt file from a
    /// hijacked redirect, an HTML error body, etc.
    nonisolated private static func ggufMagicIsValid(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 4)) ?? Data()
        return header == Data([0x47, 0x47, 0x55, 0x46])
    }
}


final class QwenProgressObserverHolder<Observer: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private var observer: Observer?

    func store(_ observer: Observer) {
        lock.lock()
        self.observer = observer
        lock.unlock()
    }

    func clear() {
        lock.lock()
        observer = nil
        lock.unlock()
    }
}

/// KVO observer that watches `URLSessionTask.progress.fractionCompleted` and
/// emits human-friendly progress lines + speed measurements. The holder above
/// keeps this object alive for the duration of the download. Also reused by
/// `TranscribeCppStreamingEngine` for the Parakeet GGUF download.
final class QwenProgressObserver: NSObject, @unchecked Sendable {
    private var observation: NSKeyValueObservation?
    private let started = Date()
    private weak var task: URLSessionTask?

    init(task: URLSessionTask, callback: @escaping @Sendable (Double, Double) -> Void) {
        self.task = task
        super.init()
        let started = self.started
        self.observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            guard self != nil else { return }
            let fraction = progress.fractionCompleted
            let elapsed = Date().timeIntervalSince(started)
            let bytes = Double(progress.completedUnitCount)
            let mbPerSec = bytes / 1_000_000.0 / max(elapsed, 0.001)
            callback(fraction, mbPerSec)
        }
    }

    deinit {
        observation?.invalidate()
    }
}

enum QwenLLMError: LocalizedError {
    case notLoaded
    case loadFailed
    case downloadFailed(statusCode: Int)
    case truncated(received: Int64, expected: Int64)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "The Qwen summary model isn't loaded yet."
        case .loadFailed:
            return "Couldn't load the Qwen summary model from disk."
        case .downloadFailed(let code):
            return "Couldn't download the Qwen model (HTTP \(code))."
        case .truncated(let received, let expected):
            let receivedMB = received / 1_000_000
            let expectedMB = expected / 1_000_000
            return "Download interrupted at \(receivedMB) MB of \(expectedMB) MB. Please try again."
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            let neededMB = requiredBytes / 1_000_000
            let freeMB = availableBytes / 1_000_000
            return "Not enough free disk space to download the model (need \(neededMB) MB, \(freeMB) MB free)."
        }
    }
}
