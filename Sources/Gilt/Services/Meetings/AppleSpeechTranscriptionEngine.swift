@preconcurrency import AVFoundation
import Foundation
import Speech

/// macOS manages the on-device assets. Installation is an explicit Settings
/// action; starting a dictation only uses assets already on this Mac.
@MainActor
final class AppleSpeechTranscriptionEngine: MeetingTranscriptionEngineProtocol {
    let engineID: MeetingTranscriptionEngine = .appleSpeech
    private(set) var isReady = false
    var vocabularyHints: [String] = []
    private let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }

    func refreshAvailability() async {
        guard #available(macOS 26, *), let module = try? await makeModule() else {
            isReady = false
            return
        }
        // Installed language assets are shared across apps, but the system
        // reports .supported until this app reserves its locale. Reservation
        // does not download; missing assets still require the Settings action.
        _ = try? await AssetInventory.reserve(locale: locale)
        isReady = await AssetInventory.status(forModules: [module]) == .installed
    }

    func warmUp() async throws {
        await refreshAvailability()
        guard isReady else { throw MeetingTranscriptionError.modelMissing(engine: engineID) }
    }

    func prefetch(reportingProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        guard #available(macOS 26, *) else { throw MeetingTranscriptionError.modelMissing(engine: engineID) }
        let module = try await makeModule()
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let progress = Task {
                while !Task.isCancelled {
                    reportingProgress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { progress.cancel() }
            let installationProgress = request.progress
            try await withTaskCancellationHandler {
                try await request.downloadAndInstall()
            } onCancel: { installationProgress.cancel() }
            try Task.checkCancellation()
        }
        try await warmUp()
        reportingProgress(1)
    }

    @available(macOS 26, *)
    private func makeModule() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechError.unsupportedLanguage
        }
        return SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
    }

    func transcribeStream(
        from audio: AsyncStream<AVAudioPCMBuffer>, meetingStartedAt: Date
    ) -> AsyncThrowingStream<MeetingTranscriptChunk, Error> {
        let input = AppleSpeechAudioInput(buffers: audio)
        let hints = vocabularyHints
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard #available(macOS 26, *) else {
                    continuation.finish(throwing: MeetingTranscriptionError.modelMissing(engine: engineID))
                    return
                }
                do {
                    try await warmUp()
                    let module = try await makeModule()
                    let analyzer = SpeechAnalyzer(modules: [module])
                    if !hints.isEmpty {
                        let context = AnalysisContext()
                        context.contextualStrings[.general] = hints
                        try? await analyzer.setContext(context)
                    }
                    try await withTaskCancellationHandler {
                        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                            throw MeetingTranscriptionError.transcriptionFailed
                        }
                        try await analyzer.prepareToAnalyze(in: format)
                        let inputs = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(512))
                        let reader = Task {
                            var committed = ""
                            for try await result in module.results {
                                try Task.checkCancellation()
                                let text = String(result.text.characters)
                                if result.isFinal {
                                    committed += text
                                }
                                let update = StreamingTranscriptUpdate(
                                    committed: committed, tentative: result.isFinal ? "" : text,
                                    isFinal: result.isFinal
                                )
                                continuation.yield(MeetingTranscriptChunk(
                                    startTimeSeconds: 0, endTimeSeconds: 0,
                                    text: update.text, engineRaw: engineID.rawValue, streamingUpdate: update
                                ))
                            }
                            return committed
                        }
                        defer { reader.cancel(); inputs.continuation.finish() }
                        async let analysis: Void = analyzer.start(inputSequence: inputs.stream)
                        var converter: AVAudioConverter?
                        for await buffer in input.buffers {
                            try Task.checkCancellation()
                            let converted = try Self.convert(buffer, to: format, converter: &converter)
                            if case .dropped = inputs.continuation.yield(AnalyzerInput(buffer: converted)) {
                                throw AppleSpeechError.overloaded
                            }
                        }
                        inputs.continuation.finish()
                        try await analysis
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        let final = StreamingTranscriptUpdate(committed: try await reader.value, isFinal: true)
                        try Task.checkCancellation()
                        continuation.yield(MeetingTranscriptChunk(
                            startTimeSeconds: 0, endTimeSeconds: 0,
                            text: final.text, engineRaw: engineID.rawValue, streamingUpdate: final
                        ))
                    } onCancel: {
                        Task { await analyzer.cancelAndFinishNow() }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func transcribeFile(at audioURL: URL) async throws -> [MeetingTranscriptChunk] {
        let samples = try TranscribeCppStreamingEngine.loadSamples16kMono(from: audioURL)
        let text = try await transcribeSamples(samples)
        return [MeetingTranscriptChunk(
            startTimeSeconds: 0, endTimeSeconds: Double(samples.count) / 16_000,
            text: text, engineRaw: engineID.rawValue
        )]
    }

    func transcribeSamples(_ samples: [Float]) async throws -> String {
        let input = AsyncStream<AVAudioPCMBuffer> { continuation in
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            for offset in stride(from: 0, to: samples.count, by: 1600) {
                let count = min(1600, samples.count - offset)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { continue }
                buffer.frameLength = AVAudioFrameCount(count)
                samples.withUnsafeBufferPointer { pointer in
                    buffer.floatChannelData?[0].update(from: pointer.baseAddress!.advanced(by: offset), count: count)
                }
                continuation.yield(buffer)
            }
            continuation.finish()
        }
        var final = ""
        for try await chunk in transcribeStream(from: input, meetingStartedAt: Date()) { final = chunk.text }
        return final
    }

    /// Dictation capture supplies independent 16 kHz buffers. Convert each once
    /// to the system model's format, retaining converter state across buffers.
    private static func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat, converter: inout AVAudioConverter?
    ) throws -> AVAudioPCMBuffer {
        if converter == nil { converter = AVAudioConverter(from: buffer.format, to: format) }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw MeetingTranscriptionError.transcriptionFailed
        }
        let input = SingleUsePCMInput(buffer: buffer)
        var error: NSError?
        converter.convert(to: output, error: &error, withInputFrom: input.provide)
        if let error { throw error }
        return output
    }
}

private struct AppleSpeechAudioInput: @unchecked Sendable {
    let buffers: AsyncStream<AVAudioPCMBuffer>
}

private enum AppleSpeechError: LocalizedError {
    case unsupportedLanguage, overloaded
    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage:
            return L10n.string("dictation.error.appleLanguage", default: "Apple Speech is unavailable for this Mac's language. Choose the English speech model in Settings → Dictate.")
        case .overloaded:
            return L10n.string("dictation.error.overloaded", default: "Speech processing couldn't keep up. Copy your draft and try a shorter dictation.")
        }
    }
}
