import AVFoundation
import Foundation

/// Routes a meeting's audio to the correct transcription engine based on
/// language and quality preference. Engines are lazily instantiated and cached
/// so reopening a meeting doesn't reload models.
@MainActor
final class MeetingTranscriptionService {
    private let modelsRoot: URL
    private var cache: [MeetingTranscriptionEngine: any MeetingTranscriptionEngineProtocol] = [:]

    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    func engine(for engineID: MeetingTranscriptionEngine) -> any MeetingTranscriptionEngineProtocol {
        if let cached = cache[engineID] {
            return cached
        }
        let folder = MeetingAppSupportLocator.transcriptionModelFolder(
            engine: engineID,
            in: modelsRoot
        )
        let modelFileURL = folder.appendingPathComponent(engineID.modelFileName)

        let engine: any MeetingTranscriptionEngineProtocol
        switch engineID {
        case .parakeetFlash, .parakeetV2:
            engine = ParakeetTranscriptionEngine(modelURL: modelFileURL)
        case .parakeetUnifiedStream:
            engine = TranscribeCppStreamingEngine(modelURL: modelFileURL)
        case .whisperSmallMultilingual:
            engine = WhisperTranscriptionEngine(engine: engineID, modelURL: modelFileURL)
        }
        cache[engineID] = engine
        return engine
    }
}
