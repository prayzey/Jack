@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import WhisperKit

/// Whisper-backed transcription engine, powered by Argmax's `WhisperKit` Swift
/// library running CoreML-compiled Whisper models on the Apple Neural Engine.
///
/// Models are auto-downloaded from `argmaxinc/whisperkit-coreml` on Hugging Face
/// the first time we instantiate the pipeline, then cached on disk. No
/// self-hosting required.
@MainActor
final class WhisperTranscriptionEngine: MeetingTranscriptionEngineProtocol {
    let engineID: MeetingTranscriptionEngine
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "WhisperEngine")
    private let modelFolder: URL
    private var pipeline: WhisperKit?

    init(engine: MeetingTranscriptionEngine, modelURL: URL) {
        precondition(
            engine == .whisperSmallMultilingual,
            "WhisperTranscriptionEngine only accepts Whisper engine IDs"
        )
        self.engineID = engine
        // We store WhisperKit's auto-downloaded CoreML packages in our per-engine
        // folder so the user-facing model manager can show one consistent
        // "Meetings/models/<engine>/" tree on disk.
        self.modelFolder = modelURL.deletingLastPathComponent()
    }

    var isReady: Bool {
        if pipeline != nil { return true }
        // Cold-launch path: we haven't warmed up yet this process, but the
        // model files may already be cached on disk from a previous session.
        // Without this check, dictation/meetings would falsely report the
        // model as "missing" every fresh launch.
        return Self.modelExistsOnDisk(engine: engineID, modelFolder: modelFolder)
    }

    /// True when WhisperKit's variant folder already contains the CoreML
    /// packages — i.e. we won't trigger a Hugging Face fetch on warm-up.
    ///
    /// WhisperKit's actual on-disk layout is deeper than `downloadBase/variant`:
    /// it writes to `<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>/`.
    /// We probe the known location plus a couple of historical/fallback ones
    /// so users who downloaded under earlier WhisperKit versions still register
    /// as Ready instead of being prompted to re-download.
    static func modelExistsOnDisk(
        engine: MeetingTranscriptionEngine,
        modelFolder: URL
    ) -> Bool {
        let downloadBase = modelFolder.deletingLastPathComponent()
        let variant = whisperKitModelName(for: engine)
        let candidates: [URL] = [
            downloadBase
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(variant, isDirectory: true),
            downloadBase.appendingPathComponent(variant, isDirectory: true),
            modelFolder.appendingPathComponent(variant, isDirectory: true)
        ]
        for folder in candidates {
            guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil else {
                continue
            }
            // Require the full set of core CoreML packages, each non-empty.
            // The old "≥1 .mlmodelc" check let an interrupted download (say,
            // only the encoder landed) register as "ready" and then fail at
            // load time. These three are always present in a complete
            // openai_whisper-small variant.
            let requiredPackages = [
                "AudioEncoder.mlmodelc",
                "TextDecoder.mlmodelc",
                "MelSpectrogram.mlmodelc"
            ]
            if requiredPackages.allSatisfy({ name in
                packageIsPresentAndNonEmpty(at: folder.appendingPathComponent(name))
            }) {
                return true
            }
        }
        return false
    }

    /// True if `url` is a non-empty directory (a populated `.mlmodelc` package).
    private static func packageIsPresentAndNonEmpty(at url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        let entries = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        return !entries.isEmpty
    }

    func warmUp() async throws {
        if pipeline != nil { return }
        try await loadPipeline(progressCallback: nil)
    }

    func prefetch(reportingProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        if pipeline != nil {
            MeetingDownloadLog.log("Whisper \(engineID.rawValue) already loaded")
            await MainActor.run { reportingProgress(1.0) }
            return
        }
        try ensureDiskSpaceForDownload()
        let label = "[whisper-\(engineID.rawValue)]"
        MeetingDownloadLog.log("Whisper prefetch — handing off to WhisperKit (\(engineID.rawValue))")
        MeetingDownloadLog.resetCounter(label)
        try await loadPipeline { progress in
            let fraction = progress.fractionCompleted
            MeetingDownloadLog.progress(label, fraction: fraction)
            Task { @MainActor in reportingProgress(fraction) }
        }
        MeetingDownloadLog.log("Whisper \(engineID.rawValue) ready ✅")
        await MainActor.run { reportingProgress(1.0) }
    }

    /// WhisperKit downloads into `modelFolder`'s parent tree, so we check that
    /// volume's headroom against the model size before handing off.
    private func ensureDiskSpaceForDownload() throws {
        let requiredBytes = Int64(Double(engineID.approximateDownloadSizeBytes) * 1.2)
        if let available = meetingVolumeImportantCapacity(at: modelFolder.deletingLastPathComponent()),
           available < requiredBytes {
            throw MeetingTranscriptionError.insufficientDiskSpace(
                requiredBytes: requiredBytes,
                availableBytes: available
            )
        }
    }

    private func loadPipeline(progressCallback: (@Sendable (Progress) -> Void)?) async throws {
        do {
            try FileManager.default.createDirectory(
                at: modelFolder,
                withIntermediateDirectories: true,
                attributes: nil
            )
            // Two-stage warm-up so we can report download progress:
            //  1. Static `WhisperKit.download(variant:progressCallback:)` —
            //     emits a real Foundation `Progress` as files stream in.
            //  2. Construct `WhisperKit` against the now-local folder with
            //     `download: false` so it doesn't re-fetch.
            let downloadBase = modelFolder.deletingLastPathComponent()
            let modelVariant = Self.whisperKitModelName(for: engineID)
            let downloadedFolder = try await WhisperKit.download(
                variant: modelVariant,
                downloadBase: downloadBase,
                useBackgroundSession: false,
                progressCallback: progressCallback
            )
            let config = WhisperKitConfig(
                model: modelVariant,
                downloadBase: downloadBase,
                modelFolder: downloadedFolder.path,
                verbose: false,
                load: true,
                download: false,
                useBackgroundDownloadSession: false
            )
            self.pipeline = try await WhisperKit(config)
            logger.info("WhisperKit warmed up for \(self.engineID.rawValue)")
        } catch {
            logger.error("WhisperKit warmUp failed: \(error.localizedDescription)")
            throw MeetingTranscriptionError.modelLoadFailed(engine: engineID, underlying: error)
        }
    }

    func transcribeStream(
        from audio: AsyncStream<AVAudioPCMBuffer>,
        meetingStartedAt: Date
    ) -> AsyncThrowingStream<MeetingTranscriptChunk, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                // Accumulate samples and decode every ~5 seconds so the live
                // transcript stays close to real time. The post-meeting pass
                // re-transcribes the whole file for a clean final transcript.
                guard let self else { continuation.finish(); return }
                let windowSeconds: Double = 5.0
                let sampleRate: Double = 16_000
                let windowSamples = Int(windowSeconds * sampleRate)
                var buffer: [Float] = []
                var totalElapsed: Double = 0
                var windowStart: Double = 0

                for await pcmBuffer in audio {
                    let samples = Self.extractMonoSamples(from: pcmBuffer)
                    if samples.isEmpty { continue }
                    buffer.append(contentsOf: samples)
                    totalElapsed += Double(samples.count) / sampleRate

                    while buffer.count >= windowSamples {
                        let slice = Array(buffer.prefix(windowSamples))
                        buffer.removeFirst(windowSamples)
                        let chunkEnd = windowStart + windowSeconds
                        let chunk = await self.decodeWindow(
                            samples: slice,
                            startTime: windowStart,
                            endTime: chunkEnd
                        )
                        if let chunk { continuation.yield(chunk) }
                        windowStart = chunkEnd
                    }
                }
                if !buffer.isEmpty {
                    let endTime = totalElapsed
                    let chunk = await self.decodeWindow(
                        samples: buffer,
                        startTime: windowStart,
                        endTime: endTime
                    )
                    if let chunk { continuation.yield(chunk) }
                }
                continuation.finish()
            }
        }
    }

    /// Direct in-memory one-shot. The protocol's default `transcribeSamples`
    /// writes the floats to a temp CAF and round-trips through `transcribeFile`,
    /// which has been flaky for dictation: WhisperKit's path-based decoder
    /// sometimes throws on CAF-formatted floats. Going straight through
    /// `pipeline.transcribe(audioArray:)` matches what `decodeWindow` already
    /// does for the streaming path and avoids the extra disk round-trip.
    func transcribeSamples(_ samples: [Float]) async throws -> String {
        try await warmUp()
        guard let pipeline else {
            throw MeetingTranscriptionError.modelLoadFailed(engine: engineID, underlying: nil)
        }
        do {
            let results = try await pipeline.transcribe(audioArray: samples)
            return Self.joinedText(from: results)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Whisper one-shot transcribe failed: \(error.localizedDescription)")
            throw MeetingTranscriptionError.audioReadFailed(underlying: error)
        }
    }

    func transcribeFile(at audioURL: URL) async throws -> [MeetingTranscriptChunk] {
        try await warmUp()
        guard let pipeline else {
            throw MeetingTranscriptionError.modelLoadFailed(engine: engineID, underlying: nil)
        }
        do {
            let results = try await pipeline.transcribe(audioPath: audioURL.path)
            return Self.flattenSegments(
                from: results,
                engine: engineID,
                fallbackEndSeconds: Self.audioDuration(at: audioURL)
            )
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
        guard let pipeline else { return nil }
        do {
            let results = try await pipeline.transcribe(audioArray: samples)
            let text = Self.joinedText(from: results)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return MeetingTranscriptChunk(
                startTimeSeconds: startTime,
                endTimeSeconds: endTime,
                text: trimmed,
                engineRaw: engineID.rawValue
            )
        } catch {
            logger.error("Live decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let pointer = channelData[0]
        return Array(UnsafeBufferPointer(start: pointer, count: frames))
    }

    private static func joinedText(from results: [TranscriptionResult]) -> String {
        results.map { $0.text }.joined(separator: " ")
    }

    private static func flattenSegments(
        from results: [TranscriptionResult],
        engine: MeetingTranscriptionEngine,
        fallbackEndSeconds: Double
    ) -> [MeetingTranscriptChunk] {
        var chunks: [MeetingTranscriptChunk] = []
        for result in results {
            for segment in result.segments {
                let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                chunks.append(MeetingTranscriptChunk(
                    startTimeSeconds: Double(segment.start),
                    endTimeSeconds: Double(segment.end),
                    text: trimmed,
                    engineRaw: engine.rawValue
                ))
            }
        }
        if chunks.isEmpty {
            let joined = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                chunks.append(MeetingTranscriptChunk(
                    startTimeSeconds: 0,
                    endTimeSeconds: fallbackEndSeconds,
                    text: joined,
                    engineRaw: engine.rawValue
                ))
            }
        }
        return chunks
    }

    private static func audioDuration(at url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Maps our internal engine IDs to the WhisperKit model name strings.
    /// These match the variants published in `argmaxinc/whisperkit-coreml`.
    static func whisperKitModelName(for engine: MeetingTranscriptionEngine) -> String {
        switch engine {
        case .whisperSmallMultilingual: return "openai_whisper-small"
        case .parakeetFlash, .parakeetV2, .parakeetUnifiedStream: return "openai_whisper-small" // never used; satisfies exhaustiveness
        }
    }
}
