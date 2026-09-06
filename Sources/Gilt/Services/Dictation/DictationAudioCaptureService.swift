@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Microphone-only audio capture for the dictation overlay.
///
/// Differences from `MeetingAudioCaptureService`:
/// - Mic-only (no ScreenCaptureKit / system audio path)
/// - In-memory only — we don't persist raw dictation audio to disk
/// - Resets the buffer stream on each `start()` so consecutive dictations are
///   independent
@MainActor
final class DictationAudioCaptureService {
    // ponytail: the coordinator only calls start/stop and reads the buffer
    // stream + collected samples; nobody observes richer capture state.
    // Reintroduce a CaptureState enum + ObservableObject if a UI ever needs it.
    private var isRecording = false

    /// Async stream of mic buffers — handed to the transcription engine for
    /// the live (decorative) streaming pass.
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> { streamWrapper.stream }

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationAudio")
    /// Built fresh on each `start()` and dropped to nil in `finalizeStop()`.
    /// This is what releases the orange microphone indicator on macOS — calling
    /// `audioEngine.stop()` halts the render loop but leaves the underlying
    /// `AUAudioUnit` initialized, which keeps coreaudiod's "this app is
    /// recording" state held. Only ARC-dropping the engine releases that.
    /// Do NOT change this back to a `let` long-lived instance.
    private var audioEngine: AVAudioEngine?
    private let targetSampleRate: Double = 16_000
    private let targetFormat: AVAudioFormat
    private let bufferTapBus: AVAudioNodeBus = 0
    private var startedAt: Date?
    private var micBridge: MeetingAudioBufferBridge?
    private let streamWrapper = DictationAudioStreamWrapper()
    private var tapSink: DictationAudioTapSink?
    /// Snapshot taken in `finalizeStop()` — `tapSink` is cleared before the
    /// coordinator reads samples after the stream ends.
    private var finalizedCollectedSamples: [Float] = []

    init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            preconditionFailure("Failed to build dictation audio format")
        }
        self.targetFormat = format
    }

    deinit {
        streamWrapper.finish()
    }

    // MARK: - Permission

    @discardableResult
    func requestMicrophoneAccess() async -> Bool {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        switch current {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    // MARK: - Lifecycle

    /// Start a new dictation capture session.
    ///
    /// - Parameters:
    ///   - preferredDeviceUID: The mic the user picked in settings. `nil`
    ///     means follow the system default — we skip the device-binding call
    ///     and AVAudioEngine binds to whatever `kAudioHardwarePropertyDefaultInputDevice`
    ///     resolves to at engine init.
    ///   - requestedGain: User-chosen gain. Interpretation depends on whether
    ///     the bound device supports settable hardware volume:
    ///       - settable: clamped to `0...1` and written to
    ///         `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`
    ///       - not settable: clamped to `1...2` and applied as a software
    ///         multiplier in the tap (only the >1.0 portion does anything —
    ///         we never *attenuate* in software, that's what hardware gain
    ///         is for)
    func start(preferredDeviceUID: String? = nil, requestedGain: Float = 1.0) async throws {
        if isRecording { return }

        guard await requestMicrophoneAccess() else {
            throw DictationAudioError.permissionDenied
        }

        streamWrapper.reset()
        finalizedCollectedSamples = []
        tapSink = DictationAudioTapSink(
            targetFormat: targetFormat,
            targetSampleRate: targetSampleRate,
            streamWrapper: streamWrapper
        )

        // Fresh engine per session. The previous one was torn down in
        // `finalizeStop()` so coreaudiod could release the input device and
        // turn the orange mic indicator off.
        //
        // Why off-main: the first access to `engine.inputNode` lazily
        // initializes the AVAudioIOUnit, which synchronously round-trips to
        // coreaudiod (via `AVAEHalUtil::GetSubDevices` → `HALC_ProxyObject`
        // → `mach_msg`) on AVAudioEngine's internal serial queue. When
        // coreaudiod is wedged — observed in production twice on this
        // machine — that round-trip never returns. If the caller is
        // MainActor, the entire UI freezes; SIGTERM can't even take down
        // the process because the main run loop is blocked waiting for the
        // sync barrier. The off-main + timeout build below keeps MainActor
        // responsive and lets us surface a clean error instead of bricking
        // the app. Engine binding, gain resolution, and format probe all
        // move into the same background task so any one of them stalling
        // counts toward the same budget.
        let setup: AudioEngineSetup
        do {
            setup = try await Self.buildAudioEngineSetup(
                preferredDeviceUID: preferredDeviceUID,
                requestedGain: requestedGain
            )
        } catch {
            audioEngine = nil
            if let dictationErr = error as? DictationAudioError, dictationErr == .audioSystemUnresponsive {
                logger.error("AVAudioEngine build timed out — coreaudiod appears wedged")
            }
            throw error
        }

        let engine = setup.engine
        audioEngine = engine
        tapSink?.softwareGainFactor = setup.softwareGainFactor

        guard setup.inputFormat.sampleRate > 0 else {
            audioEngine = nil
            throw DictationAudioError.noInput
        }

        // inputNode is already initialized inside the background build — this
        // access is fast and cannot wedge.
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: bufferTapBus)
        guard let tapSink else {
            throw DictationAudioError.noInput
        }
        let bridge = Self.makeBridge(sink: tapSink)
        micBridge = bridge
        inputNode.installTap(
            onBus: bufferTapBus,
            bufferSize: 1024,
            format: setup.inputFormat,
            block: Self.makeTapBlock(bridge: bridge)
        )
        engine.prepare()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: bufferTapBus)
            audioEngine = nil
            micBridge = nil
            throw error
        }

        startedAt = Date()
        isRecording = true
        logger.info("Dictation audio capture started")
    }

    /// Result of the off-main engine bootstrap. Carried across actor
    /// boundaries via `@unchecked Sendable` because AVAudioEngine /
    /// AVAudioFormat are imported `@preconcurrency` — they predate strict
    /// Sendable but are safe to hand back to MainActor as long as we don't
    /// touch them concurrently from elsewhere, which we don't.
    private struct AudioEngineSetup: @unchecked Sendable {
        let engine: AVAudioEngine
        let inputFormat: AVAudioFormat
        let softwareGainFactor: Float
    }

    /// Build an AVAudioEngine + bind mic + probe input format on a background
    /// queue, racing against a hard timeout. See the call site for *why* this
    /// has to be off-main.
    ///
    /// On timeout: the in-flight setup task keeps running (we can't cancel a
    /// blocked `mach_msg`), but its result is dropped — the abandoned engine
    /// is unreferenced and will be ARC-released the instant coreaudiod ever
    /// responds. No shared state leaks into the next session because each
    /// `start()` builds a fresh engine from scratch.
    private nonisolated static func buildAudioEngineSetup(
        preferredDeviceUID: String?,
        requestedGain: Float,
        timeoutSeconds: Double = 4.0
    ) async throws -> AudioEngineSetup {
        try await withCheckedThrowingContinuation { continuation in
            // Race latch: whoever calls `claim()` first owns the continuation.
            // The loser is a silent no-op — never resume the same continuation
            // twice or Swift will trap. Wrapped in a `final class` so the
            // mutable `fired` flag can be captured across the timeout and
            // work closures without tripping strict-concurrency rules.
            let latch = ContinuationLatch()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if latch.claim() {
                    continuation.resume(throwing: DictationAudioError.audioSystemUnresponsive)
                }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let engine = AVAudioEngine()

                // Bind the chosen mic to the input audio unit BEFORE installTap.
                // The input format is cached at first tap install — a late switch
                // leaves the cached format stale and the next session crashes
                // inside installTap with the `_outputFormat.channelCount`
                // assert. (Safe to call with nil UID — that's the no-op
                // "use default" path.)
                AudioInputDeviceManager.bind(engine, toUID: preferredDeviceUID)

                // Decide which gain mode applies. The check has to happen
                // against the device the engine ACTUALLY ended up bound to —
                // if `bind` failed (unplugged), we resolve gain against the
                // live system default.
                let effectiveUID = preferredDeviceUID ?? AudioInputDeviceManager.defaultInputDeviceID().flatMap {
                    AudioInputDeviceManager.deviceUID(forID: $0)
                }
                let softwareGain: Float
                if AudioInputDeviceManager.canSetHardwareGain(forUID: effectiveUID) {
                    AudioInputDeviceManager.setHardwareGain(max(0, min(1, requestedGain)), forUID: effectiveUID)
                    softwareGain = 1.0
                } else {
                    softwareGain = max(1.0, min(2.0, requestedGain))
                }

                // Force input node + format resolution NOW, while we're
                // off-main. This is the call that wedges on coreaudiod
                // (see the call-site comment in `start()` for the full
                // stack). If it stalls past the timeout above, the result
                // gets dropped on the floor.
                let inputFormat = engine.inputNode.inputFormat(forBus: 0)

                if latch.claim() {
                    continuation.resume(returning: AudioEngineSetup(
                        engine: engine,
                        inputFormat: inputFormat,
                        softwareGainFactor: softwareGain
                    ))
                }
            }
        }
    }

    /// Hang the mic open briefly after key release so the trailing syllable
    /// isn't clipped. Flash finalization injects trailing silence before `finish()`.
    private let trailingHangNanoseconds: UInt64 = 100_000_000

    func stop() {
        guard isRecording else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.trailingHangNanoseconds ?? 0)
            self?.finalizeStop()
        }
    }

    private func finalizeStop() {
        guard isRecording else { return }
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: bufferTapBus)
            if engine.isRunning { engine.stop() }
        }
        // Drop the engine reference so ARC deallocates the underlying
        // `AUAudioUnit` for the input bus. This is what tells coreaudiod
        // we're done with the microphone — only then does the orange menu
        // bar indicator go away. `stop()` alone doesn't do this.
        audioEngine = nil
        micBridge = nil
        finalizedCollectedSamples = tapSink?.drainAndSnapshot() ?? []
        tapSink = nil
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        isRecording = false
        streamWrapper.finish()
        logger.info("Dictation audio capture stopped after \(String(format: "%.2f", duration))s")
    }

    // MARK: - Internal

    nonisolated private static func makeBridge(sink: DictationAudioTapSink) -> MeetingAudioBufferBridge {
        MeetingAudioBufferBridge { buffer in
            sink.handle(rawBuffer: buffer)
        }
    }

    /// Collected 16 kHz mono samples for the recording that just ended.
    var collectedSamples: [Float] {
        if !finalizedCollectedSamples.isEmpty {
            return finalizedCollectedSamples
        }
        return tapSink?.snapshotSamples() ?? []
    }

    nonisolated private static func makeTapBlock(bridge: MeetingAudioBufferBridge) -> AVAudioNodeTapBlock {
        { buffer, _ in bridge.handle(buffer) }
    }
}

// MARK: - Off-main tap processing

/// Resamples, collects, and streams mic buffers on a utility queue so the
/// audio tap never hops to MainActor (~30–50 Hz).
private final class DictationAudioTapSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "gilt.dictation.audio", qos: .utility)
    private let targetFormat: AVAudioFormat
    private let targetSampleRate: Double
    private let streamWrapper: DictationAudioStreamWrapper
    private let lock = NSLock()
    private var collectedSamples: [Float] = []
    private var resampleConverter: AVAudioConverter?
    private var resampleSourceFormat: AVAudioFormat?
    var softwareGainFactor: Float = 1.0

    init(
        targetFormat: AVAudioFormat,
        targetSampleRate: Double,
        streamWrapper: DictationAudioStreamWrapper
    ) {
        self.targetFormat = targetFormat
        self.targetSampleRate = targetSampleRate
        self.streamWrapper = streamWrapper
    }

    func handle(rawBuffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            self.process(rawBuffer)
        }
    }

    func snapshotSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return collectedSamples
    }

    /// Waits for queued tap work, then returns the full sample tape.
    func drainAndSnapshot() -> [Float] {
        queue.sync {
            lock.lock()
            defer { lock.unlock() }
            return collectedSamples
        }
    }

    private func process(_ rawBuffer: AVAudioPCMBuffer) {
        guard let converted = convert(rawBuffer) else { return }
        applySoftwareGainIfNeeded(converted)
        streamWrapper.send(copyPCMBuffer(converted))

        guard let channelData = converted.floatChannelData?[0] else { return }
        let frames = Int(converted.frameLength)
        lock.lock()
        collectedSamples.reserveCapacity(collectedSamples.count + frames)
        collectedSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
        lock.unlock()
    }

    private func convert(_ rawBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if rawBuffer.format.sampleRate == targetSampleRate
            && rawBuffer.format.channelCount == targetFormat.channelCount {
            return rawBuffer
        }
        guard let resampled = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(targetSampleRate)
        ) else { return nil }
        if resampleConverter == nil || resampleSourceFormat != rawBuffer.format {
            resampleConverter = AVAudioConverter(from: rawBuffer.format, to: targetFormat)
            resampleSourceFormat = rawBuffer.format
        }
        guard let converter = resampleConverter else { return nil }
        let input = SingleUseInput(buffer: rawBuffer)
        var error: NSError?
        converter.convert(to: resampled, error: &error, withInputFrom: input.provide)
        guard error == nil else { return nil }
        return resampled
    }

    private func applySoftwareGainIfNeeded(_ buffer: AVAudioPCMBuffer) {
        guard softwareGainFactor > 1.0, let channelData = buffer.floatChannelData else { return }
        let gain = softwareGainFactor
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for c in 0..<channels {
            let samples = channelData[c]
            for i in 0..<frames {
                let amplified = samples[i] * gain
                samples[i] = min(1.0, max(-1.0, amplified))
            }
        }
    }

    private func copyPCMBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard
            let copy = AVAudioPCMBuffer(
                pcmFormat: source.format,
                frameCapacity: source.frameCapacity
            )
        else { return source }
        copy.frameLength = source.frameLength
        let channels = Int(source.format.channelCount)
        let frames = Int(source.frameLength)
        guard frames > 0,
              let src = source.floatChannelData,
              let dst = copy.floatChannelData else { return source }
        for channel in 0..<channels {
            dst[channel].update(from: src[channel], count: frames)
        }
        return copy
    }
}

enum DictationAudioError: LocalizedError {
    case permissionDenied
    case noInput
    /// Engine bootstrap exceeded its timeout — almost always means coreaudiod
    /// is in a bad state. Recovery is "try again, and if that fails restart
    /// the Mac"; nothing the app can do from userland will un-wedge a stuck
    /// coreaudiod. Surfaced as a failed session so the next dictation attempt
    /// gets a clean slate.
    case audioSystemUnresponsive

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone access is required for dictation."
        case .noInput: return "No audio input detected. Connect a mic and try again."
        case .audioSystemUnresponsive: return "Audio system isn't responding. Try again. If it keeps happening, restart your Mac."
        }
    }
}

/// One-shot race latch for `withCheckedThrowingContinuation` plumbing.
/// First caller to win `claim()` owns the continuation; everyone else gets
/// `false` and must be silent — resuming the same continuation twice traps
/// in Swift. `@unchecked Sendable` because the `NSLock`-guarded `Bool` is
/// safe to mutate across threads.
private final class ContinuationLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

private final class DictationAudioStreamWrapper: @unchecked Sendable {
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

private final class SingleUseInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var consumed = false

    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }

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
