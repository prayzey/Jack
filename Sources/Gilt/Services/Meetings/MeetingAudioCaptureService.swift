@preconcurrency import AVFoundation
import Combine
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

/// Captures meeting audio and surfaces a live RMS level so the UI can render a
/// calm-but-real waveform. Microphone capture uses AVAudioEngine; system audio
/// uses ScreenCaptureKit's audio stream.
@MainActor
final class MeetingAudioCaptureService: ObservableObject {
    /// Live state of the audio capture pipeline.
    enum CaptureState: Equatable {
        case idle
        case requestingPermission
        case denied(reason: String)
        case starting
        case recording
        case paused
        case stopped
        case failed(reason: String)
    }

    @Published private(set) var state: CaptureState = .idle
    /// Audio meter level in 0...1. Updates ~30 times per second while recording.
    @Published private(set) var level: Double = 0
    /// Elapsed seconds since recording started. Updated on the main actor.
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var activeSource: MeetingAudioSource = .microphone

    /// Software gain multiplier applied in the tap when the bound mic doesn't
    /// expose settable hardware volume. `1.0` = no change. Same rules as the
    /// dictation service — capped at 2.0 in `start(...)`.
    private var softwareGainFactor: Float = 1.0

    /// Async stream of newly written audio buffers. Consumers (the streaming
    /// transcription engine) attach to this and feed buffers into whisper.cpp.
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> { streamWrapper.stream }

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingAudio")
    /// Built fresh on each `start()` and dropped to nil in `stop()`. This is
    /// what releases the orange microphone indicator on macOS — calling
    /// `audioEngine.stop()` halts the render loop but leaves the underlying
    /// `AUAudioUnit` initialized, which keeps coreaudiod's "this app is
    /// recording" state held. Only ARC-dropping the engine releases that.
    /// Do NOT change this back to a `let` long-lived instance.
    /// (Pause/resume DOES reuse the same engine instance — only `stop()`
    /// drops it, since the user expects to be able to hit Resume.)
    private var audioEngine: AVAudioEngine?
    private var systemAudioCapture: SystemAudioCapture?
    private let bufferTapBus: AVAudioNodeBus = 0
    /// Whisper.cpp + most ASR models expect 16 kHz mono PCM. We resample once
    /// here so downstream code doesn't have to.
    private let targetSampleRate: Double = 16_000
    private let targetFormat: AVAudioFormat
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private var levelTimer: Timer?
    private var microphoneTapBridge: MeetingAudioBufferBridge?
    /// Cached converters keyed by input format description. Building a converter
    /// per buffer is expensive — sample rates and channel counts don't change
    /// mid-stream, so one converter per upstream format is enough.
    private var converterCache: [String: AVAudioConverter] = [:]

    private let streamWrapper = MeetingAudioStreamWrapper()

    init() {
        // Single-channel float PCM at the model's expected sample rate.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            preconditionFailure("Failed to create target audio format")
        }
        self.targetFormat = format
    }

    deinit {
        // `stop()` must be called explicitly before this service is released.
        // We intentionally avoid touching @MainActor-isolated audio engine
        // state from a nonisolated deinit (Swift 6 concurrency rule).
        streamWrapper.finish()
    }

    // MARK: - Permission

    /// Requests microphone access if not already granted. Resolves with the
    /// granted state. Safe to call repeatedly.
    func requestMicrophoneAccess() async -> Bool {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        switch current {
        case .authorized:
            return true
        case .denied, .restricted:
            state = .denied(reason: L10n.string(
                "meeting.audio.error.denied",
                default: "Microphone access is denied. Open System Settings to grant access."
            ))
            return false
        case .notDetermined:
            state = .requestingPermission
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                state = .denied(reason: L10n.string(
                    "meeting.audio.error.denied",
                    default: "Microphone access is denied. Open System Settings to grant access."
                ))
            } else {
                state = .idle
            }
            return granted
        @unknown default:
            return false
        }
    }

    // MARK: - Lifecycle

    /// Starts capturing audio into the given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: Destination CAF file.
    ///   - source: Mic-only, system-audio-only, or both.
    ///   - preferredDeviceUID: The mic the user picked in Meetings settings.
    ///     `nil` = system default. Only meaningful when `source` includes mic.
    ///   - requestedGain: User-chosen gain. Same dual-mode interpretation as
    ///     the dictation service — hardware volume on supported devices,
    ///     software multiplier (capped at 2.0x) on devices without settable
    ///     hardware volume. Only applied to the mic path; system-audio
    ///     samples come from ScreenCaptureKit and are passed through as-is.
    func start(
        writingTo audioURL: URL,
        source: MeetingAudioSource = .microphone,
        preferredDeviceUID: String? = nil,
        requestedGain: Float = 1.0
    ) async throws {
        if case .recording = state { return }
        if case .starting = state { return }

        logger.info("Meeting capture starting: source=\(source.rawValue, privacy: .public)")

        if source.requiresMicrophone {
            let granted = await requestMicrophoneAccess()
            guard granted else {
                logger.error("Meeting capture aborted: microphone permission denied")
                throw MeetingAudioError.permissionDenied
            }
        }

        state = .starting
        activeSource = source
        streamWrapper.reset()
        converterCache.removeAll()

        try FileManager.default.createDirectory(
            at: audioURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
        }

        // Audio file is CAF (Core Audio Format) — robust against power-loss
        // mid-recording and supported natively by AVAudioFile. We write float32
        // to match `targetFormat` so AVAudioFile can write our converted buffers
        // directly without re-converting.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: audioURL, settings: fileSettings)
        } catch {
            logger.error("Failed to open audio file: \(error.localizedDescription, privacy: .public)")
            state = .failed(reason: L10n.string(
                "meeting.audio.error.write",
                default: "Could not write the meeting recording to disk."
            ))
            throw MeetingAudioError.fileWriteFailed
        }
        self.audioFile = file

        var systemCapture: SystemAudioCapture?
        if source.requiresSystemAudio {
            do {
                let capture = makeSystemAudioCapture()
                try await capture.start(sampleRate: Int(targetSampleRate))
                systemCapture = capture
                logger.info("System audio capture started via ScreenCaptureKit")
            } catch {
                audioFile = nil
                let failure = MeetingAudioError.systemAudioUnavailable(underlying: error)
                logger.error("System audio capture failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(reason: failure.localizedDescription)
                throw failure
            }
        }

        if source.requiresMicrophone {
            do {
                // Fresh engine per session — the previous one was deallocated
                // in `stop()` so coreaudiod could release the mic indicator.
                let engine = AVAudioEngine()
                audioEngine = engine

                // Bind the user-selected mic BEFORE inputFormat is read or
                // installTap is called — the input node caches its format on
                // first tap install and a late switch crashes the next session.
                // nil UID = no-op, follow the system default.
                AudioInputDeviceManager.bind(engine, toUID: preferredDeviceUID)

                // Resolve which device gain reads/writes will hit. If the
                // bind failed (mic unplugged), fall back to the live system
                // default so the gain decision matches what the engine
                // actually ended up bound to.
                let effectiveUID = preferredDeviceUID ?? AudioInputDeviceManager.defaultInputDeviceID().flatMap {
                    AudioInputDeviceManager.deviceUID(forID: $0)
                }
                if AudioInputDeviceManager.canSetHardwareGain(forUID: effectiveUID) {
                    AudioInputDeviceManager.setHardwareGain(max(0, min(1, requestedGain)), forUID: effectiveUID)
                    softwareGainFactor = 1.0
                } else {
                    softwareGainFactor = max(1.0, min(2.0, requestedGain))
                }

                let inputNode = engine.inputNode
                let inputFormat = inputNode.inputFormat(forBus: bufferTapBus)
                logger.info("Microphone input format: sampleRate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public)")
                try startMicrophoneCapture(inputNode: inputNode, inputFormat: inputFormat)
                engine.prepare()
                try engine.start()
                logger.info("AVAudioEngine started for microphone capture")
            } catch {
                stopMicrophoneCapture()
                if let capture = systemCapture {
                    Task { try? await capture.stop() }
                }
                logger.error("Microphone capture failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(reason: microphoneStartFailureMessage(for: error))
                audioFile = nil
                throw error
            }
        }

        systemAudioCapture = systemCapture
        startTime = Date()
        state = .recording
        installLevelTimer()
        logger.info("Meeting audio capture is now recording source=\(source.rawValue, privacy: .public)")
    }

    func pause() {
        guard case .recording = state else { return }
        if activeSource.requiresMicrophone {
            audioEngine?.pause()
        }
        let capture = systemAudioCapture
        systemAudioCapture = nil
        if let capture {
            Task {
                do {
                    try await capture.stop()
                } catch {
                    self.logger.error("System audio pause failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        levelTimer?.invalidate()
        levelTimer = nil
        state = .paused
        logger.info("Paused meeting audio capture")
    }

    func resume() async throws {
        guard case .paused = state else { return }
        var resumedSystemCapture: SystemAudioCapture?
        if activeSource.requiresMicrophone {
            // The engine is paused (not deallocated) so the existing instance
            // restarts. If the user paused, quit/relaunched the meeting flow,
            // and is now resuming, `start()` (not `resume()`) is what runs —
            // so `audioEngine == nil` here would be a programmer bug.
            try audioEngine?.start()
        }
        if activeSource.requiresSystemAudio {
            let capture = makeSystemAudioCapture()
            do {
                try await capture.start(sampleRate: Int(targetSampleRate))
                resumedSystemCapture = capture
            } catch {
                if activeSource.requiresMicrophone {
                    audioEngine?.pause()
                }
                let failure = MeetingAudioError.systemAudioUnavailable(underlying: error)
                logger.error("System audio resume failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(reason: failure.localizedDescription)
                throw failure
            }
        }
        systemAudioCapture = resumedSystemCapture
        installLevelTimer()
        state = .recording
        logger.info("Resumed meeting audio capture")
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        stopMicrophoneCapture()
        let capture = systemAudioCapture
        systemAudioCapture = nil
        Task {
            do {
                try await capture?.stop()
            } catch {
                self.logger.error("System audio stop failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        levelTimer?.invalidate()
        levelTimer = nil
        startTime = nil
        elapsedSeconds = 0
        level = 0
        audioFile = nil
        converterCache.removeAll()
        state = .stopped
        streamWrapper.finish()
        logger.info("Stopped meeting audio capture")
    }

    // MARK: - Internal

    private func startMicrophoneCapture(inputNode: AVAudioInputNode, inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            state = .failed(reason: L10n.string(
                "meeting.audio.error.noInput",
                default: "No audio input was detected. Connect a microphone and try again."
            ))
            throw MeetingAudioError.noInput
        }

        inputNode.removeTap(onBus: bufferTapBus)
        let bridge = Self.makeAudioBufferBridge(service: self)
        microphoneTapBridge = bridge
        inputNode.installTap(
            onBus: bufferTapBus,
            bufferSize: 2048,
            format: inputFormat,
            block: Self.makeMicrophoneTapBlock(bridge: bridge)
        )
    }

    private func stopMicrophoneCapture() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: bufferTapBus)
            if engine.isRunning { engine.stop() }
        }
        // Drop the engine reference so ARC deallocates the underlying
        // `AUAudioUnit`. This is the call that finally lets coreaudiod
        // release the input device and turn the orange menu-bar mic
        // indicator off. `stop()` alone doesn't do this.
        audioEngine = nil
        microphoneTapBridge = nil
    }

    private func makeSystemAudioCapture() -> SystemAudioCapture {
        let bridge = Self.makeAudioBufferBridge(service: self)
        return SystemAudioCapture(
            onSampleBuffer: Self.makeSystemAudioSampleHandler(bridge: bridge),
            onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.logger.error("System audio stream stopped with error: \(error.localizedDescription, privacy: .public)")
                    self?.state = .failed(reason: error.localizedDescription)
                }
            }
        )
    }

    nonisolated static func makeAudioBufferBridge(service: MeetingAudioCaptureService?) -> MeetingAudioBufferBridge {
        MeetingAudioBufferBridge { [weak service] buffer in
            Task { @MainActor [weak service] in
                service?.handleIncomingBuffer(buffer)
            }
        }
    }

    nonisolated static func makeMicrophoneTapBlock(bridge: MeetingAudioBufferBridge) -> AVAudioNodeTapBlock {
        { buffer, _ in
            bridge.handle(buffer)
        }
    }

    nonisolated static func makeSystemAudioSampleHandler(bridge: MeetingAudioBufferBridge) -> @Sendable (CMSampleBuffer) -> Void {
        { sampleBuffer in
            guard let pcmBuffer = AVAudioPCMBuffer.fromCMSampleBuffer(sampleBuffer) else { return }
            bridge.handle(pcmBuffer)
        }
    }

    private func handleIncomingBuffer(_ rawBuffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }
        guard rawBuffer.frameLength > 0 else { return }

        let converted: AVAudioPCMBuffer
        if Self.formatsEqual(rawBuffer.format, targetFormat) {
            converted = rawBuffer
        } else {
            guard let resampled = resample(rawBuffer) else { return }
            converted = resampled
        }

        guard converted.frameLength > 0 else { return }

        // Apply software gain before write/stream/level so the recording file,
        // live transcription stream, and meter all see the boosted signal.
        // No-op when softwareGainFactor == 1.0 (hardware-gain mode).
        applySoftwareGainIfNeeded(converted)

        do {
            try file.write(from: converted)
        } catch {
            logger.error("Audio file write failed: \(error.localizedDescription, privacy: .public)")
        }

        // Push to live stream for streaming transcription.
        streamWrapper.send(converted)

        let rms = averagePower(of: converted)
        Task { @MainActor [weak self] in
            self?.level = rms
        }
    }

    /// In-place gain + clamp. Same shape as the dictation service version —
    /// kept duplicated rather than extracted because the two services are
    /// intentionally independent (different lifecycle).
    private func applySoftwareGainIfNeeded(_ buffer: AVAudioPCMBuffer) {
        guard softwareGainFactor > 1.0, let channelData = buffer.floatChannelData else {
            return
        }
        let gain = softwareGainFactor
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for c in 0..<channels {
            let samples = channelData[c]
            for i in 0..<frames {
                samples[i] = min(1.0, max(-1.0, samples[i] * gain))
            }
        }
    }

    /// Returns a buffer in `targetFormat`, allocating one large enough to hold
    /// every input frame after sample-rate conversion. Caches the converter so
    /// we don't pay the construction cost per buffer (~hundreds per second).
    private func resample(_ rawBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let converter = converter(for: rawBuffer.format)
        guard let converter else {
            logger.error("Could not build AVAudioConverter for incoming format \(rawBuffer.format, privacy: .public)")
            return nil
        }

        // Compute output capacity from the actual sample-rate ratio plus a small
        // safety margin so the converter never truncates trailing samples.
        let ratio = targetSampleRate / rawBuffer.format.sampleRate
        let estimatedFrames = Double(rawBuffer.frameLength) * ratio
        let capacity = AVAudioFrameCount(max(estimatedFrames.rounded(.up) + 1024, 1024))

        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            logger.error("Failed to allocate output buffer for resampling")
            return nil
        }

        let input = SingleUseAudioBufferInput(buffer: rawBuffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error, withInputFrom: input.provide)
        if let error {
            logger.error("Audio resample failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        if status == .error { return nil }
        return output
    }

    private func converter(for inputFormat: AVAudioFormat) -> AVAudioConverter? {
        let key = Self.cacheKey(for: inputFormat)
        if let cached = converterCache[key] { return cached }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return nil
        }
        converterCache[key] = converter
        logger.info("Built AVAudioConverter: \(inputFormat.sampleRate, privacy: .public)Hz/\(inputFormat.channelCount, privacy: .public)ch → 16000Hz/1ch")
        return converter
    }

    private static func cacheKey(for format: AVAudioFormat) -> String {
        "\(format.sampleRate)-\(format.channelCount)-\(format.commonFormat.rawValue)-\(format.isInterleaved)"
    }

    private static func formatsEqual(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
        a.sampleRate == b.sampleRate
            && a.channelCount == b.channelCount
            && a.commonFormat == b.commonFormat
            && a.isInterleaved == b.isInterleaved
    }

    private func microphoneStartFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        // CoreAudio kAudioHardwareNoDevicesError = 1852989743 ('nodev'),
        // OSStatus -10851 = no input device.
        if nsError.code == 1_852_989_743 || nsError.code == -10_851 {
            return L10n.string(
                "meeting.audio.error.noInput",
                default: "No audio input was detected. Connect a microphone and try again."
            )
        }
        return L10n.string(
            "meeting.audio.error.engineFailed",
            default: "The microphone couldn't be started: \(error.localizedDescription)"
        )
    }

    private func installLevelTimer() {
        levelTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let startTime = self.startTime else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startTime)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    /// Normalized RMS power in 0...1.
    private func averagePower(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard frames > 0, channels > 0 else { return 0 }

        var sum: Double = 0
        for channel in 0..<channels {
            let samples = channelData[channel]
            for i in 0..<frames {
                let value = Double(samples[i])
                sum += value * value
            }
        }
        let rms = sqrt(sum / Double(frames * channels))
        // Compress to a calmer 0..1 curve — raw RMS clusters near zero for speech.
        return min(1.0, sqrt(rms) * 3.0)
    }
}

enum MeetingAudioError: LocalizedError {
    case permissionDenied
    case noInput
    case systemAudioUnavailable(underlying: Error)
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L10n.string(
                "meeting.audio.error.denied",
                default: "Microphone access is denied. Open System Settings to grant access."
            )
        case .noInput:
            return L10n.string(
                "meeting.audio.error.noInput",
                default: "No audio input was detected. Connect a microphone and try again."
            )
        case .systemAudioUnavailable(let underlying):
            let nsError = underlying as NSError
            let description = nsError.localizedDescription
            let looksLikePermission =
                nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                || description.localizedCaseInsensitiveContains("permission")
                || description.localizedCaseInsensitiveContains("declined")
                || description.localizedCaseInsensitiveContains("not authorized")
                || description.localizedCaseInsensitiveContains("tcc")
            if looksLikePermission {
                return L10n.string(
                    "meeting.audio.error.systemPermission",
                    default: "System audio capture needs Screen Recording permission. Open System Settings > Privacy & Security > Screen Recording, enable Jack, then try again."
                )
            }
            return L10n.string(
                "meeting.audio.error.systemUnavailable",
                default: "System audio capture could not start."
            ) + " (\(description))"
        case .fileWriteFailed:
            return L10n.string(
                "meeting.audio.error.write",
                default: "Could not write the meeting recording to disk."
            )
        }
    }
}

/// Thin wrapper around an `AsyncStream` continuation so callers don't need to
/// manage the continuation lifecycle directly.
private final class MeetingAudioStreamWrapper: @unchecked Sendable {
    private(set) var stream: AsyncStream<AVAudioPCMBuffer>
    private let lock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    init() {
        var continuationOut: AsyncStream<AVAudioPCMBuffer>.Continuation?
        self.stream = AsyncStream { continuation in
            continuationOut = continuation
        }
        self.continuation = continuationOut
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        var continuationOut: AsyncStream<AVAudioPCMBuffer>.Continuation?
        stream = AsyncStream { continuation in
            continuationOut = continuation
        }
        continuation = continuationOut
    }

    func send(_ buffer: sending AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.yield(buffer)
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }
}

final class MeetingAudioBufferBridge: @unchecked Sendable {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        onBuffer(buffer)
    }
}

private final class SingleUseAudioBufferInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var consumed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(
        packetCount: AVAudioPacketCount,
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        _ = packetCount
        lock.lock()
        defer { lock.unlock() }
        if consumed {
            status.pointee = .noDataNow
            return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
    }
}

private final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "SystemAudioCapture")
    private let sampleQueue = DispatchQueue(label: "Jack.Meeting.SystemAudioCapture")
    private let lock = NSLock()
    private let onSampleBuffer: @Sendable (CMSampleBuffer) -> Void
    private let onFailure: @Sendable (Error) -> Void
    private var stream: SCStream?

    init(
        onSampleBuffer: @escaping @Sendable (CMSampleBuffer) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.onSampleBuffer = onSampleBuffer
        self.onFailure = onFailure
        super.init()
    }

    func start(sampleRate: Int) async throws {
        let alreadyStarted = lock.withLock { self.stream != nil }
        if alreadyStarted { return }

        // SCShareableContent is the first call that triggers the Screen Recording
        // permission prompt on first use. If permission is denied, it throws an
        // SCStreamError; we let it propagate so the UI can show a clear message.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            logger.error("SCShareableContent failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let display = content.displays.first else {
            logger.error("No displays available for SCShareableContent")
            throw MeetingAudioError.noInput
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        // We need an SCStream for the audio output but don't actually use the
        // video frames. The minimum width/height accepted varies by macOS
        // release; 2x2 is the smallest reliably accepted in practice. Using
        // 1x1 has caused initialization failures on some macOS 14+ builds.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        // SCStream supports 8000, 16000, 24000, 48000 Hz. We pick 16k so our
        // downstream resampler is a no-op for system audio — same rate, just
        // mono mixdown to handle.
        configuration.sampleRate = sampleRate
        configuration.channelCount = 2
        configuration.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        } catch {
            logger.error("Failed to add audio stream output: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        do {
            try await stream.startCapture()
        } catch {
            logger.error("SCStream startCapture failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        lock.withLock {
            self.stream = stream
        }
        logger.info("SCStream started: sampleRate=\(sampleRate, privacy: .public)")
    }

    func stop() async throws {
        let stream = lock.withLock {
            let current = self.stream
            self.stream = nil
            return current
        }
        guard let stream else { return }
        try await stream.stopCapture()
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        onSampleBuffer(sampleBuffer)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(error)
    }
}

extension AVAudioPCMBuffer {
    /// Converts a CMSampleBuffer (delivered from `SCStream` audio outputs) into
    /// an `AVAudioPCMBuffer`. Uses Apple's recommended `withAudioBufferList`
    /// pattern from the ScreenCaptureKit sample code, and additionally handles
    /// interleaved-input layouts by de-interleaving into the standard
    /// non-interleaved float32 buffer that the rest of the pipeline expects.
    ///
    /// Why this matters: ScreenCaptureKit historically delivered audio in
    /// non-interleaved float32 (matching `AVAudioFormat(standardFormatWith…)`),
    /// but on some macOS releases buffers arrive interleaved. The prior path
    /// (`CMSampleBufferCopyPCMDataIntoAudioBufferList`) silently produced
    /// empty/garbled output in that case, which is why the meeting waveform
    /// stayed flat and the transcript never appeared with system audio
    /// selected.
    static func fromCMSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard sampleBuffer.dataReadiness == .ready,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }

        let channels = AVAudioChannelCount(asbd.mChannelsPerFrame)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        let isPCM = asbd.mFormatID == kAudioFormatLinearPCM

        guard isPCM, channels > 0 else { return nil }

        // `standardFormatWithSampleRate` is non-interleaved float32 — the
        // canonical shape the rest of the pipeline expects.
        guard let destinationFormat = AVAudioFormat(
            standardFormatWithSampleRate: asbd.mSampleRate,
            channels: channels
        ) else { return nil }

        var result: AVAudioPCMBuffer?
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            let abl = audioBufferList.unsafePointer.pointee
            let numberBuffers = Int(abl.mNumberBuffers)

            // For non-interleaved float32 we can read directly through
            // AVAudioPCMBuffer's bufferListNoCopy initializer.
            if isFloat, !isInterleaved, numberBuffers == Int(channels) {
                var mutableASBD = asbd
                guard let sourceFormat = AVAudioFormat(streamDescription: &mutableASBD),
                      let source = AVAudioPCMBuffer(
                          pcmFormat: sourceFormat,
                          bufferListNoCopy: audioBufferList.unsafePointer
                      ),
                      source.frameLength > 0,
                      let destination = AVAudioPCMBuffer(
                          pcmFormat: destinationFormat,
                          frameCapacity: source.frameLength
                      )
                else { return }
                destination.frameLength = source.frameLength
                if let srcChannels = source.floatChannelData,
                   let dstChannels = destination.floatChannelData {
                    let bytesPerChannel = Int(source.frameLength) * MemoryLayout<Float>.size
                    for channel in 0..<Int(channels) {
                        memcpy(dstChannels[channel], srcChannels[channel], bytesPerChannel)
                    }
                    result = destination
                }
                return
            }

            // Interleaved float32: one audio buffer containing LRLR… samples.
            // We de-interleave into the non-interleaved destination so the
            // downstream resampler / level meter / file writer never have to
            // worry about layout.
            if isFloat, isInterleaved, numberBuffers == 1 {
                let buffer = withUnsafePointer(to: abl.mBuffers) { $0.pointee }
                let dataPtr = buffer.mData?.assumingMemoryBound(to: Float.self)
                let totalBytes = Int(buffer.mDataByteSize)
                let bytesPerFrame = Int(channels) * MemoryLayout<Float>.size
                guard let dataPtr, bytesPerFrame > 0 else { return }
                let frameCount = AVAudioFrameCount(totalBytes / bytesPerFrame)
                guard frameCount > 0,
                      let destination = AVAudioPCMBuffer(
                          pcmFormat: destinationFormat,
                          frameCapacity: frameCount
                      ),
                      let dstChannels = destination.floatChannelData
                else { return }
                destination.frameLength = frameCount
                let channelCount = Int(channels)
                for frame in 0..<Int(frameCount) {
                    for channel in 0..<channelCount {
                        dstChannels[channel][frame] = dataPtr[frame * channelCount + channel]
                    }
                }
                result = destination
                return
            }

            // Int16 fallback for completeness — rarely seen from SCStream but
            // possible from mic capture paths that route through here.
            if !isFloat, !isInterleaved, numberBuffers == Int(channels) {
                var mutableASBD = asbd
                guard let sourceFormat = AVAudioFormat(streamDescription: &mutableASBD),
                      let source = AVAudioPCMBuffer(
                          pcmFormat: sourceFormat,
                          bufferListNoCopy: audioBufferList.unsafePointer
                      ),
                      source.frameLength > 0
                else { return }

                guard let destination = AVAudioPCMBuffer(
                    pcmFormat: destinationFormat,
                    frameCapacity: source.frameLength
                ), let dstChannels = destination.floatChannelData,
                      let srcInt16 = source.int16ChannelData
                else { return }
                destination.frameLength = source.frameLength
                let scale: Float = 1.0 / 32_768.0
                for channel in 0..<Int(channels) {
                    let src = srcInt16[channel]
                    let dst = dstChannels[channel]
                    for frame in 0..<Int(source.frameLength) {
                        dst[frame] = Float(src[frame]) * scale
                    }
                }
                result = destination
                return
            }
        }
        return result
    }
}

