import Combine
import Foundation
import OSLog

/// Tracks model presence + drives downloads for the meeting feature.
///
/// Each underlying library (WhisperKit, FluidAudio, LLM.swift) manages its own
/// model cache, so "download" here really means "ask the engine to warm up";
/// the library's own loader handles the actual Hugging Face fetch and on-disk
/// layout.
///
/// We surface a unified `MeetingModelDownloadState` to the UI so the Models
/// panel stays consistent across all three engines.
@MainActor
final class MeetingModelManager: ObservableObject {
    @Published private(set) var transcriptionStates: [MeetingTranscriptionEngine: MeetingModelDownloadState] = [:]
    @Published private(set) var summarizationState: MeetingModelDownloadState = .missing
    @Published private(set) var activeDownloads: Set<String> = []

    private let modelsRoot: URL
    private let transcriptionService: MeetingTranscriptionService?
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingModelManager")

    init(modelsRoot: URL, transcriptionService: MeetingTranscriptionService? = nil) {
        self.modelsRoot = modelsRoot
        self.transcriptionService = transcriptionService
        try? FileManager.default.createDirectory(
            at: modelsRoot,
            withIntermediateDirectories: true,
            attributes: nil
        )
        refreshAll()
    }

    func refreshAll() {
        for engine in MeetingTranscriptionEngine.allCases {
            transcriptionStates[engine] = inferTranscriptionState(for: engine)
        }
        let cacheDir = MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: modelsRoot
        )
        summarizationState = (QwenLocalLLM.shared.isLoaded || QwenLocalLLM.cachedModelExists(in: cacheDir))
            ? .ready
            : .missing
    }

    func transcriptionState(for engine: MeetingTranscriptionEngine) -> MeetingModelDownloadState {
        transcriptionStates[engine] ?? .missing
    }

    func deleteModel(_ engine: MeetingTranscriptionEngine) {
        // Library caches live under FluidAudio's / WhisperKit's own Application
        // Support folder. We can't always remove them — but clearing our own
        // folder (used as the WhisperKit modelFolder) gets us most of the way.
        let folder = MeetingAppSupportLocator.transcriptionModelFolder(engine: engine, in: modelsRoot)
        try? FileManager.default.removeItem(at: folder)
        transcriptionStates[engine] = .missing
    }

    func deleteSummaryModel() {
        QwenLocalLLM.shared.unload()
        let folder = MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: modelsRoot
        )
        try? FileManager.default.removeItem(at: folder)
        summarizationState = .missing
    }

    // MARK: - Downloads

    /// Triggers the underlying engine's `prefetch(reportingProgress:)` so the
    /// library does its own Hugging Face download and we get real progress
    /// callbacks (instead of a static 0%).
    func downloadTranscriptionModel(_ engine: MeetingTranscriptionEngine) async {
        guard activeDownloads.insert(engine.rawValue).inserted else { return }
        defer { activeDownloads.remove(engine.rawValue) }

        transcriptionStates[engine] = .downloading(progress: 0, receivedBytes: 0)

        guard let service = transcriptionService else {
            transcriptionStates[engine] = .failed(reason: "Transcription service unavailable.")
            return
        }
        let engineInstance = service.engine(for: engine)
        let totalBytes = engine.approximateDownloadSizeBytes
        do {
            try await engineInstance.prefetch { [weak self] fraction in
                guard let self else { return }
                let bytes = Int64(fraction * Double(totalBytes))
                self.transcriptionStates[engine] = .downloading(progress: fraction, receivedBytes: bytes)
            }
            transcriptionStates[engine] = .ready
        } catch {
            logger.error("Transcription prefetch failed for \(engine.rawValue): \(error.localizedDescription)")
            transcriptionStates[engine] = .failed(reason: error.localizedDescription)
        }
    }

    /// Downloads + loads the Qwen summary model. LLM.swift gives us real
    /// granular progress via a callback so we can show a precise progress bar.
    func downloadSummarizationModel() async {
        let key = MeetingSummarizationEngine.qwen35_4b_q4.rawValue
        guard activeDownloads.insert(key).inserted else { return }
        defer { activeDownloads.remove(key) }

        summarizationState = .downloading(progress: 0, receivedBytes: 0)

        let cacheDir = MeetingAppSupportLocator.summarizationModelFolder(
            engine: .qwen35_4b_q4,
            in: modelsRoot
        )
        let totalBytes = MeetingSummarizationEngine.qwen35_4b_q4.approximateDownloadSizeBytes

        do {
            try await QwenLocalLLM.shared.ensureLoaded(cacheDirectory: cacheDir) { [weak self] progress in
                guard let self else { return }
                let received = Int64(progress * Double(totalBytes))
                self.summarizationState = .downloading(progress: progress, receivedBytes: received)
            }
            summarizationState = .ready
        } catch {
            logger.error("Qwen download failed: \(error.localizedDescription)")
            summarizationState = .failed(reason: error.localizedDescription)
        }
    }

    // MARK: - Internal state

    /// We rely on the engine cache (in-memory) for `.ready` — once the engine
    /// has been warmed up in this process it stays warm. Across launches we
    /// can't reliably detect cache presence without coupling to each library's
    /// internals, so first-use after launch shows a quick "downloading"
    /// transition even though the bytes are already on disk.
    private func inferTranscriptionState(for engine: MeetingTranscriptionEngine) -> MeetingModelDownloadState {
        guard let service = transcriptionService else { return .missing }
        return service.engine(for: engine).isReady ? .ready : .missing
    }
}
