@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import OSLog

/// Parakeet-backed transcription engine, powered by `FluidAudio` running
/// NVIDIA Parakeet TDT v2 (English) as a CoreML model on the Apple Neural Engine.
///
/// FluidAudio's `AsrModels.downloadAndLoad(version:)` pulls the pre-converted
/// CoreML model from `FluidInference/parakeet-tdt-0.6b-v2-coreml` on Hugging Face
/// on first use. Nothing self-hosted.
@MainActor
final class ParakeetTranscriptionEngine: MeetingTranscriptionEngineProtocol {
    let engineID: MeetingTranscriptionEngine = .parakeetV2
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "ParakeetEngine")
    /// FluidAudio's AsrManager is an actor — we keep a single instance for the
    /// life of the engine and reuse it across meetings.
    private var asrManager: AsrManager?
    private var loadedModels: AsrModels?

    /// Live-streaming window length, in seconds. Default is 3.0 which fits
    /// meetings well (waits for sentence-like chunks before yielding). The
    /// dictation coordinator drops this to ~1.2s for snappier word-by-word
    /// feel — shorter windows are slightly less accurate at boundaries but
    /// for dictation the perceived latency win is worth it.
    var streamingWindowSeconds: Double = 3.0

    init(modelURL: URL) {
        // FluidAudio manages its own model cache under
        // `~/Library/Application Support/`. The `modelURL` parameter we used
        // in the placeholder API is kept in the protocol for compatibility with
        // future engines that want explicit on-disk control.
        _ = modelURL
    }

    var isReady: Bool {
        // "Ready" in our model manager UI sense means "fast to warm up next
        // time" — either we already loaded the model in this process, or the
        // FluidAudio cache on disk has the model files, which means
        // `downloadAndLoad` will skip the network round-trip.
        if asrManager != nil && loadedModels != nil { return true }
        return Self.modelExistsInFluidAudioCache()
    }

    /// The FluidAudio library caches CoreML models under
    /// `~/Library/Application Support/FluidAudio/Models/<model-name>/`. We peek
    /// at that path so the Models panel shows "Ready" on a cold launch instead
    /// of falsely claiming the user needs to download a model they already
    /// have on disk.
    private static func modelExistsInFluidAudioCache() -> Bool {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return false }
        let folder = support
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v2", isDirectory: true)
        // The five known model artifacts FluidAudio downloads. We require all
        // of them AND that each is non-empty — a partial cache (interrupted
        // download leaving a zero-byte file or an empty .mlmodelc dir) would
        // otherwise register as "ready" and then fail at load time.
        let required = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
            "parakeet_vocab.json"
        ]
        return required.allSatisfy { name in
            Self.artifactIsPresentAndNonEmpty(at: folder.appendingPathComponent(name))
        }
    }

    /// True if `url` exists and carries content: a non-empty directory (for
    /// `.mlmodelc` packages) or a nonzero-size regular file.
    private static func artifactIsPresentAndNonEmpty(at url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        if isDir.boolValue {
            let entries = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            return !entries.isEmpty
        }
        let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        return size > 0
    }

    func warmUp() async throws {
        if asrManager != nil && loadedModels != nil { return }
        try await loadModels(progressHandler: nil)
    }

    func prefetch(reportingProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        if asrManager != nil && loadedModels != nil {
            MeetingDownloadLog.log("Parakeet v2 already loaded — skipping prefetch")
            await MainActor.run { reportingProgress(1.0) }
            return
        }
        try ensureDiskSpaceForDownload()
        MeetingDownloadLog.log("Parakeet v2 prefetch — handing off to FluidAudio")
        MeetingDownloadLog.resetCounter("[parakeet]")
        // FluidAudio's progress handler is called from an arbitrary queue, so
        // bounce the fraction back to the main actor for SwiftUI binding.
        try await loadModels { progress in
            let fraction = progress.fractionCompleted
            MeetingDownloadLog.progress("[parakeet]", fraction: fraction)
            Task { @MainActor in reportingProgress(fraction) }
        }
        MeetingDownloadLog.log("Parakeet v2 ready ✅")
        await MainActor.run { reportingProgress(1.0) }
    }

    /// FluidAudio downloads into its own Application Support cache, so we
    /// check that volume's headroom against the model size before handing off.
    private func ensureDiskSpaceForDownload() throws {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let requiredBytes = Int64(Double(engineID.approximateDownloadSizeBytes) * 1.2)
        if let available = meetingVolumeImportantCapacity(at: support), available < requiredBytes {
            throw MeetingTranscriptionError.insufficientDiskSpace(
                requiredBytes: requiredBytes,
                availableBytes: available
            )
        }
    }

    private func loadModels(progressHandler: DownloadUtils.ProgressHandler?) async throws {
        do {
            let models = try await AsrModels.downloadAndLoad(
                version: .v2,
                progressHandler: progressHandler
            )
            let manager = AsrManager(config: .default, models: models)
            self.loadedModels = models
            self.asrManager = manager
            logger.info("FluidAudio Parakeet v2 warmed up")
        } catch {
            logger.error("FluidAudio load failed: \(error.localizedDescription)")
            throw MeetingTranscriptionError.modelLoadFailed(engine: engineID, underlying: error)
        }
    }

    func transcribeStream(
        from audio: AsyncStream<AVAudioPCMBuffer>,
        meetingStartedAt: Date
    ) -> AsyncThrowingStream<MeetingTranscriptChunk, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }

                // Window length is per-engine-instance (configurable). Meetings
                // use the 3s default; dictation shortens it for live feel.
                // Final cleanup pass after stop re-transcribes the whole file
                // from `transcribeFile(at:)`.
                let windowSeconds = self.streamingWindowSeconds
                let sampleRate: Double = 16_000
                let windowSamples = Int(windowSeconds * sampleRate)
                var bufferSamples: [Float] = []
                var totalElapsed: Double = 0
                var windowStart: Double = 0

                for await pcmBuffer in audio {
                    let samples = WhisperTranscriptionEngine.extractMonoSamples(from: pcmBuffer)
                    if samples.isEmpty { continue }
                    bufferSamples.append(contentsOf: samples)
                    totalElapsed += Double(samples.count) / sampleRate

                    while bufferSamples.count >= windowSamples {
                        let slice = Array(bufferSamples.prefix(windowSamples))
                        bufferSamples.removeFirst(windowSamples)
                        let chunkEnd = windowStart + windowSeconds
                        if let chunk = await self.decodeWindow(
                            samples: slice,
                            startTime: windowStart,
                            endTime: chunkEnd
                        ) {
                            continuation.yield(chunk)
                        }
                        windowStart = chunkEnd
                    }
                }
                if !bufferSamples.isEmpty {
                    if let chunk = await self.decodeWindow(
                        samples: bufferSamples,
                        startTime: windowStart,
                        endTime: totalElapsed
                    ) {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// One-shot transcription on a raw f32 sample buffer with a single
    /// continuous TDT decoder state. This is the path dictation uses on
    /// key-release for the canonical transcript. Streaming with fresh state
    /// per chunk is what produces disjointed output — TDT's prediction
    /// network needs continuous context across the whole utterance.
    ///
    /// Padding strategy:
    ///   - **Trailing silence (~400ms)** is always appended. Parakeet's TDT
    ///     decoder commits its final word with help from a few frames of
    ///     following audio; ending the buffer abruptly often produces a
    ///     garbled or truncated last word. A small silence tail gives the
    ///     model a clear "audio finished" cue and lets the decoder finalize.
    ///   - **Sub-1s recordings are padded** to 20k samples (1.25s) because
    ///     Parakeet's mel front-end rejects very short audio.
    func transcribeSamples(_ samples: [Float]) async throws -> String {
        try await warmUp()
        guard let asrManager else {
            throw MeetingTranscriptionError.modelLoadFailed(engine: engineID, underlying: nil)
        }
        var padded = samples
        // Always append silence at the end so the TDT decoder can finalize
        // its last token. 6400 samples = 400ms at 16kHz.
        let trailingSilenceSamples = 6_400
        padded.append(contentsOf: Array(repeating: Float(0), count: trailingSilenceSamples))
        // Short-recording floor: ensure the model sees at least ~1.25s of
        // audio so its mel front-end has enough frames to compute.
        if padded.count < 16_000 {
            padded.append(contentsOf: Array(repeating: Float(0), count: 20_000 - padded.count))
        }
        do {
            var decoderState = try TdtDecoderState()
            let result = try await asrManager.transcribe(
                padded,
                decoderState: &decoderState,
                language: nil
            )
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw MeetingTranscriptionError.audioReadFailed(underlying: error)
        }
    }

    func transcribeFile(at audioURL: URL) async throws -> [MeetingTranscriptChunk] {
        try await warmUp()
        guard let asrManager else {
            throw MeetingTranscriptionError.modelLoadFailed(engine: engineID, underlying: nil)
        }
        do {
            // The disk-backed transcribe path supports large files. We pass a
            // fresh decoder state so re-running on the same file is deterministic.
            var decoderState = try TdtDecoderState()
            let result = try await asrManager.transcribe(audioURL, decoderState: &decoderState, language: nil)
            return makeChunksFromASRResult(result, fileURL: audioURL)
        } catch {
            throw MeetingTranscriptionError.audioReadFailed(underlying: error)
        }
    }

    // MARK: - Private helpers

    private func decodeWindow(
        samples: [Float],
        startTime: Double,
        endTime: Double
    ) async -> MeetingTranscriptChunk? {
        guard let asrManager else { return nil }
        do {
            var decoderState = try TdtDecoderState()
            let result = try await asrManager.transcribe(samples, decoderState: &decoderState, language: nil)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MeetingTranscriptChunk(
                startTimeSeconds: startTime,
                endTimeSeconds: endTime,
                text: text,
                engineRaw: engineID.rawValue
            )
        } catch {
            logger.error("Live decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeChunksFromASRResult(_ result: ASRResult, fileURL: URL) -> [MeetingTranscriptChunk] {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let totalDuration = audioDuration(at: fileURL)
        // FluidAudio v2 returns the whole transcription in one block plus token
        // timings. Token timings are word-granular which is too noisy for our
        // UI — we split on sentence boundaries instead and distribute the time
        // proportionally so the timestamps are still meaningful.
        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else {
            return [MeetingTranscriptChunk(
                startTimeSeconds: 0,
                endTimeSeconds: totalDuration,
                text: text,
                engineRaw: engineID.rawValue
            )]
        }
        let totalCharacters = sentences.reduce(0) { $0 + $1.count }
        guard totalCharacters > 0, totalDuration > 0 else {
            return [MeetingTranscriptChunk(
                startTimeSeconds: 0,
                endTimeSeconds: totalDuration,
                text: text,
                engineRaw: engineID.rawValue
            )]
        }
        var chunks: [MeetingTranscriptChunk] = []
        var elapsed: Double = 0
        for sentence in sentences {
            let portion = Double(sentence.count) / Double(totalCharacters)
            let duration = totalDuration * portion
            chunks.append(MeetingTranscriptChunk(
                startTimeSeconds: elapsed,
                endTimeSeconds: elapsed + duration,
                text: sentence,
                engineRaw: engineID.rawValue
            ))
            elapsed += duration
        }
        return chunks
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[\.\?!])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let range = NSRange(text.startIndex..., in: text)
        var lastIndex = text.startIndex
        var sentences: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let range = Range(match.range, in: text) else { return }
            let sentence = String(text[lastIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            lastIndex = range.upperBound
        }
        let tail = String(text[lastIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private func audioDuration(at url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
