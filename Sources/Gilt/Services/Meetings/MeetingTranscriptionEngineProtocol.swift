import AVFoundation
import Foundation

/// Shared protocol for any speech-to-text engine in Jack. Swapping engines
/// (Parakeet, Whisper small, Whisper medium) is just a matter of returning a
/// different conformer from `MeetingTranscriptionService`.
@MainActor
protocol MeetingTranscriptionEngineProtocol: AnyObject {
    /// Stable identifier — matches `MeetingTranscriptionEngine.rawValue`.
    var engineID: MeetingTranscriptionEngine { get }

    /// Whether the underlying model file is present on disk and usable.
    var isReady: Bool { get }

    /// Loads the model into memory. Idempotent — safe to call before each
    /// session start so we get a warm model after a cold launch.
    func warmUp() async throws

    /// Explicit prefetch path used by the Models panel so we can show a
    /// real progress bar during the first-time download. Engines override
    /// this to surface their library's progress callback; the default
    /// implementation just forwards to `warmUp()` and reports 100% at the end.
    func prefetch(reportingProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws

    /// Streams transcript chunks as audio buffers arrive. Each yielded chunk
    /// should be wall-clock-accurate (relative to the start of the meeting)
    /// and ready to persist via `MeetingStore.appendTranscriptChunk`.
    ///
    /// Throwing so a session that can't start (missing model/helper, spawn
    /// failure, unsupported architecture) surfaces a real error instead of
    /// finishing empty and leaving the caller with a silently blank transcript.
    func transcribeStream(
        from audio: AsyncStream<AVAudioPCMBuffer>,
        meetingStartedAt: Date
    ) -> AsyncThrowingStream<MeetingTranscriptChunk, Error>

    /// Transcribes an already-recorded audio file end-to-end. Used for
    /// re-transcription, file imports, and post-meeting cleanup passes.
    func transcribeFile(at audioURL: URL) async throws -> [MeetingTranscriptChunk]

    /// One-shot transcription of an in-memory 16kHz mono float buffer.
    ///
    /// This is the high-quality path: dictation collects raw samples during
    /// recording and calls this on key release, so Parakeet's TDT decoder
    /// runs once over the whole utterance with a single continuous state.
    /// Streaming with fresh state-per-window erases the prediction network's
    /// context and produces visibly disjointed output.
    func transcribeSamples(_ samples: [Float]) async throws -> String
}

extension MeetingTranscriptionEngineProtocol {
    /// Default implementation: no granular progress, just warm up + flip to 100%.
    func prefetch(reportingProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        try await warmUp()
        reportingProgress(1.0)
    }
}

enum MeetingTranscriptionError: LocalizedError {
    case modelMissing(engine: MeetingTranscriptionEngine)
    case modelLoadFailed(engine: MeetingTranscriptionEngine, underlying: Error?)
    case modelDownloadFailed(engine: MeetingTranscriptionEngine)
    case unsupportedArchitecture(engine: MeetingTranscriptionEngine)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case audioReadFailed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let engine):
            return L10n.string(
                "meeting.transcription.error.modelMissing",
                default: "The \(engine.displayName) model isn't downloaded yet."
            )
        case .modelLoadFailed(let engine, _):
            return L10n.string(
                "meeting.transcription.error.modelLoad",
                default: "Couldn't load the \(engine.displayName) model."
            )
        case .modelDownloadFailed:
            return L10n.string(
                "meeting.transcription.error.modelDownload",
                default: "The model download failed or was incomplete. Please try again."
            )
        case .unsupportedArchitecture:
            return L10n.string(
                "meeting.transcription.error.unsupportedArchitecture",
                default: "Live dictation requires an Apple Silicon Mac."
            )
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            let neededMB = requiredBytes / 1_000_000
            let freeMB = availableBytes / 1_000_000
            return L10n.string(
                "meeting.transcription.error.diskSpace",
                default: "Not enough free disk space to download the model (need \(neededMB) MB, \(freeMB) MB free)."
            )
        case .audioReadFailed:
            return L10n.string(
                "meeting.transcription.error.audioRead",
                default: "Couldn't read the recorded audio."
            )
        }
    }
}

/// Available "important usage" capacity (bytes) on the volume backing `url`,
/// or nil if it can't be determined. `volumeAvailableCapacityForImportantUsage`
/// is Apple's recommended key for "can I write a large user-initiated file" —
/// it accounts for purgeable space the system will free on demand.
func meetingVolumeImportantCapacity(at url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage
}
