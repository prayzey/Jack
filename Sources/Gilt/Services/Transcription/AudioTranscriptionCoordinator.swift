import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Where a transcription job was kicked off from. Used for logging today; a
/// natural seam for per-surface behavior later.
enum TranscriptionSource: String, Sendable {
    case workspaceDrop
    case menuBarDrop
    case openPanel
}

/// One file's journey from drop to saved transcript. Drives the HUD.
struct TranscriptionJob: Identifiable, Equatable {
    enum Stage: Equatable {
        case queued
        case decoding
        case preparingModel(progress: Double)
        case transcribing
        case completed(charCount: Int)
        case noSpeech
        case failed(message: String)

        var isTerminal: Bool {
            switch self {
            case .completed, .noSpeech, .failed: return true
            case .queued, .decoding, .preparingModel, .transcribing: return false
            }
        }

        var isFailure: Bool {
            switch self {
            case .failed, .noSpeech: return true
            default: return false
            }
        }
    }

    let id: UUID
    let fileName: String
    var stage: Stage
    /// 1-based position when a batch of files is dropped at once, for the
    /// "2 of 3" affordance. `total == 1` hides it.
    var index: Int
    var total: Int
}

/// Single entry point for "transcribe this audio file". Drop targets and the
/// open-panel command call `transcribe(fileURLs:source:)`; everything else —
/// queueing, engine work, the result clip, and the progress HUD — happens here.
///
/// Jobs run one at a time on purpose: each engine holds a CoreML/MLX model, so
/// serial processing keeps memory flat and avoids two models fighting for the
/// Neural Engine.
@MainActor
final class AudioTranscriptionCoordinator: ObservableObject {
    static let shared = AudioTranscriptionCoordinator()

    /// The job currently shown in the HUD (the in-flight one, or the most
    /// recently finished one until it auto-dismisses).
    @Published private(set) var currentJob: TranscriptionJob?

    private weak var store: ClipboardStore?
    private let service = AudioFileTranscriptionService()
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "AudioTranscriptionCoordinator")

    private var queue: [URL] = []
    private var processedInBatch = 0
    private var batchTotal = 0
    private var isProcessing = false
    private var hideTask: Task<Void, Never>?

    private init() {}

    func bind(to store: ClipboardStore) {
        self.store = store
    }

    /// Filters to audio files and enqueues them. Non-audio drops surface a brief
    /// "not an audio file" HUD instead of failing silently.
    func transcribe(fileURLs: [URL], source: TranscriptionSource) {
        let audioURLs = fileURLs.filter { AudioFileTranscriptionService.isSupportedAudioFile($0) }
        guard !audioURLs.isEmpty else {
            if let firstNonAudio = fileURLs.first {
                presentRejection(fileName: firstNonAudio.lastPathComponent)
            }
            return
        }
        logger.info("Queueing \(audioURLs.count) file(s) from \(source.rawValue)")
        queue.append(contentsOf: audioURLs)
        batchTotal += audioURLs.count
        Task { await processQueue() }
    }

    /// Opens a file picker and transcribes the selection. The universal,
    /// mode-independent entry point — drop targets only exist where there's a
    /// surface to drop onto, so this is how the feature is reached from menus.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Transcribe"
        panel.message = "Choose a voice note or audio file to transcribe."
        // `.audio` covers m4a/mp3/wav/aiff/caf/aac. Ogg-Opus doesn't reliably
        // advertise public.audio, so add it (and .ogg/.oga) by extension.
        var types: [UTType] = [.audio]
        for ext in OpusAudioDecoder.oggOpusExtensions {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModalInFront() == .OK else { return }
        transcribe(fileURLs: panel.urls, source: .openPanel)
    }

    // MARK: - Queue processing

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        hideTask?.cancel()
        defer {
            isProcessing = false
            batchTotal = 0
            processedInBatch = 0
            scheduleHideAfterDelay()
        }

        while !queue.isEmpty {
            let url = queue.removeFirst()
            processedInBatch += 1
            await process(url, index: processedInBatch, total: batchTotal)
        }
    }

    private func process(_ url: URL, index: Int, total: Int) async {
        let jobID = UUID()
        currentJob = TranscriptionJob(
            id: jobID,
            fileName: url.lastPathComponent,
            stage: .queued,
            index: index,
            total: total
        )
        TranscriptionHUDWindowManager.shared.show()

        let language = MeetingHub.shared.store.settings.defaultLanguage
        do {
            let outcome = try await service.transcribe(
                fileURL: url,
                preferredLanguage: language
            ) { [weak self] stage in
                guard let self, self.currentJob?.id == jobID else { return }
                self.currentJob?.stage = Self.map(stage)
            }

            store?.addTranscriptClip(
                text: outcome.text,
                fileName: url.lastPathComponent,
                durationSeconds: outcome.durationSeconds
            )
            updateStage(jobID, .completed(charCount: outcome.text.count))
            logger.info("Transcribed \(url.lastPathComponent, privacy: .public) — \(outcome.text.count) chars via \(outcome.engine.rawValue)")
        } catch AudioFileTranscriptionService.Failure.emptyTranscript {
            updateStage(jobID, .noSpeech)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Transcription failed."
            updateStage(jobID, .failed(message: message))
            logger.error("Transcription failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func updateStage(_ jobID: UUID, _ stage: TranscriptionJob.Stage) {
        guard currentJob?.id == jobID else { return }
        currentJob?.stage = stage
    }

    private static func map(_ stage: AudioFileTranscriptionService.Stage) -> TranscriptionJob.Stage {
        switch stage {
        case .decodingAudio: return .decoding
        case .preparingModel(let progress): return .preparingModel(progress: progress)
        case .transcribing: return .transcribing
        }
    }

    // MARK: - HUD lifecycle

    private func presentRejection(fileName: String) {
        hideTask?.cancel()
        currentJob = TranscriptionJob(
            id: UUID(),
            fileName: fileName,
            stage: .failed(message: "That isn't an audio file Jack can transcribe."),
            index: 1,
            total: 1
        )
        TranscriptionHUDWindowManager.shared.show()
        scheduleHideAfterDelay()
    }

    private func scheduleHideAfterDelay() {
        guard let job = currentJob, job.stage.isTerminal else { return }
        hideTask?.cancel()
        let delay: UInt64 = job.stage.isFailure ? 6_000_000_000 : 3_500_000_000
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard let self, !self.isProcessing else { return }
            self.currentJob = nil
            TranscriptionHUDWindowManager.shared.hide()
        }
    }
}
