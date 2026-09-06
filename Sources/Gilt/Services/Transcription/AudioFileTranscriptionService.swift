import AVFoundation
import Foundation
import OSLog

/// Turns an audio file on disk into transcript text using Jack's existing
/// on-device engines (WhisperKit / FluidAudio Parakeet).
///
/// This is the pure-logic core of the file-transcription feature: given a URL it
/// (1) pre-decodes Ogg-Opus voice notes to `.m4a`, (2) picks an engine, (3)
/// downloads the model on first use, and (4) runs the engine's `transcribeFile`.
/// It owns no UI — progress is reported through the `onStage` callback so the
/// coordinator can drive whatever HUD it likes.
///
/// It deliberately spins up its own `MeetingTranscriptionService` rather than
/// reaching into `MeetingHub`'s. Engines are lazily built and the on-disk model
/// cache is shared (same models root), so this never triggers a duplicate
/// download — the only cost is a second model held in memory if the user runs a
/// live meeting and a file import at the same moment, which is rare and bounded.
@MainActor
final class AudioFileTranscriptionService {

    /// Coarse progress milestones surfaced to the UI.
    enum Stage: Equatable, Sendable {
        case decodingAudio
        case preparingModel(progress: Double)
        case transcribing
    }

    struct Outcome: Equatable, Sendable {
        let text: String
        let durationSeconds: Double
        let engine: MeetingTranscriptionEngine
    }

    enum Failure: LocalizedError {
        case unsupportedFile(name: String)
        case decodeFailed(underlying: Error)
        case transcriptionFailed(underlying: Error)
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .unsupportedFile(let name):
                return "\(name) isn't an audio file Jack can transcribe."
            case .decodeFailed:
                return "Couldn't read that voice note."
            case .transcriptionFailed:
                return "Transcription failed. Please try again."
            case .emptyTranscript:
                return "No speech was detected in that audio."
            }
        }
    }

    /// Extensions AVFoundation decodes natively, so they skip the Opus hop and
    /// go straight to the engine's file path. `nonisolated` so the pure
    /// detection helpers can read it off the main actor (and from tests).
    nonisolated static let nativeAudioExtensions: Set<String> = [
        "m4a", "m4b", "mp3", "wav", "wave", "aiff", "aif", "aifc",
        "caf", "aac", "mp4", "mov"
    ]

    /// Every extension this feature accepts (native + Ogg-Opus).
    nonisolated static func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return nativeAudioExtensions.contains(ext) || OpusAudioDecoder.oggOpusExtensions.contains(ext)
    }

    private let transcriptionService: MeetingTranscriptionService
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "AudioFileTranscription")

    init(modelsRoot: URL? = nil) {
        let root = modelsRoot ?? MeetingAppSupportLocator.modelsRoot(
            in: MeetingAppSupportLocator.meetingsRoot()
        )
        self.transcriptionService = MeetingTranscriptionService(modelsRoot: root)
    }

    /// Transcribes `fileURL`, reporting milestones through `onStage`. Throws a
    /// `Failure` for any unsupported / empty / failed case.
    func transcribe(
        fileURL: URL,
        preferredLanguage: MeetingLanguage,
        onStage: @escaping @MainActor @Sendable (Stage) -> Void
    ) async throws -> Outcome {
        guard Self.isSupportedAudioFile(fileURL) else {
            throw Failure.unsupportedFile(name: fileURL.lastPathComponent)
        }

        // Ogg-Opus (WhatsApp/Telegram/Signal voice notes) → temp .m4a. Every
        // other format is handed to the engine untouched.
        var workingURL = fileURL
        var temporaryDecodedURL: URL?
        defer {
            if let temporaryDecodedURL {
                try? FileManager.default.removeItem(at: temporaryDecodedURL)
            }
        }
        if OpusAudioDecoder.needsDecoding(fileURL) {
            onStage(.decodingAudio)
            do {
                let decoded = try OpusAudioDecoder.decodeToTemporaryM4A(fileURL)
                temporaryDecodedURL = decoded
                workingURL = decoded
            } catch {
                logger.error("Opus decode failed: \(error.localizedDescription)")
                throw Failure.decodeFailed(underlying: error)
            }
        }

        let engineID = resolveEngine(preferredLanguage: preferredLanguage)
        let engine = transcriptionService.engine(for: engineID)

        // First-use model download. `isReady` is true once the model files are
        // on disk (even pre-warm-up), so repeat runs skip straight to decoding.
        if !engine.isReady {
            onStage(.preparingModel(progress: 0))
            do {
                try await engine.prefetch { progress in
                    onStage(.preparingModel(progress: progress))
                }
            } catch {
                logger.error("Model prepare failed: \(error.localizedDescription)")
                throw Failure.transcriptionFailed(underlying: error)
            }
        }

        onStage(.transcribing)
        let chunks: [MeetingTranscriptChunk]
        do {
            chunks = try await engine.transcribeFile(at: workingURL)
        } catch {
            logger.error("transcribeFile failed: \(error.localizedDescription)")
            throw Failure.transcriptionFailed(underlying: error)
        }

        let text = Self.joinChunks(chunks)
        guard !text.isEmpty else { throw Failure.emptyTranscript }
        let duration = chunks.last?.endTimeSeconds ?? 0
        return Outcome(text: text, durationSeconds: duration, engine: engineID)
    }

    /// Picks an engine for the language, but prefers whichever model is already
    /// downloaded so a drop never silently kicks off a surprise ~500MB fetch
    /// when a usable engine is sitting right there.
    func resolveEngine(preferredLanguage: MeetingLanguage) -> MeetingTranscriptionEngine {
        let recommended = MeetingTranscriptionEngine.recommended(for: preferredLanguage)
        let alternative: MeetingTranscriptionEngine =
            (recommended == .parakeetV2) ? .whisperSmallMultilingual : .parakeetV2
        return Self.preferredEngine(
            recommended: recommended,
            recommendedReady: transcriptionService.engine(for: recommended).isReady,
            alternative: alternative,
            alternativeReady: transcriptionService.engine(for: alternative).isReady
        )
    }

    // MARK: - Pure helpers (unit-tested)

    /// Engine choice given which models are already on disk. Recommended wins
    /// when present; otherwise fall back to an already-downloaded alternative;
    /// otherwise take the recommended and accept the download.
    nonisolated static func preferredEngine(
        recommended: MeetingTranscriptionEngine,
        recommendedReady: Bool,
        alternative: MeetingTranscriptionEngine,
        alternativeReady: Bool
    ) -> MeetingTranscriptionEngine {
        if recommendedReady { return recommended }
        if alternativeReady { return alternative }
        return recommended
    }

    /// Flattens transcript chunks into a single clean string.
    nonisolated static func joinChunks(_ chunks: [MeetingTranscriptChunk]) -> String {
        chunks
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
