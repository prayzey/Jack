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
    // The coordinator samples capture metrics; audio callbacks stay off MainActor.
    private(set) var isRecording = false
    private var captureID: UUID?
    private var stopTask: Task<Void, Never>?
    private let requestAccess: @MainActor () async -> Bool
    /// Read at each session start: `DictationSettings.preferBuiltInMicOverBluetooth`.
    private let preferBuiltInMic: @MainActor () -> Bool
    /// The device volume to put back when this session ends, set only when
    /// Jack changed it because the user picked a gain.
    private var volumeToRestore: DeviceVolumeRestore?

    var level: Double { tapSink?.snapshotLevel() ?? 0 }
    nonisolated static let maximumDurationSeconds: Double = 600
    var elapsedSeconds: Double {
        Double(tapSink?.sampleCount ?? finalizedCollectedSamples.count) / targetSampleRate
    }
    var failure: DictationAudioError? { interruption ?? tapSink?.failure ?? streamWrapper.failure }
    private var interruption: DictationAudioError?
    private var configurationObserver: NSObjectProtocol?

    /// Async stream of mic buffers — handed to the transcription engine for
    /// the live transcription pass.
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

    init(
        requestAccess: @escaping @MainActor () async -> Bool = DictationAudioCaptureService.requestMicrophoneAccess,
        preferBuiltInMic: @escaping @MainActor () -> Bool = { true }
    ) {
        self.requestAccess = requestAccess
        self.preferBuiltInMic = preferBuiltInMic
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
    static func requestMicrophoneAccess() async -> Bool {
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
    ///     means follow the system default: AVAudioEngine binds to whatever
    ///     `kAudioHardwarePropertyDefaultInputDevice` resolves to at engine
    ///     init, unless that default is Bluetooth and `preferBuiltInMic`
    ///     says to use the built-in mic instead.
    ///   - requestedGain: User-chosen gain, or `nil` to leave the device's
    ///     own volume alone. Interpretation depends on whether the bound
    ///     device supports settable hardware volume:
    ///       - settable: clamped to `0...1` and written to
    ///         `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`; the
    ///         previous volume comes back when capture stops or fails
    ///       - not settable: clamped to `1...2` and applied as a software
    ///         multiplier in the tap (only the >1.0 portion does anything —
    ///         we never *attenuate* in software, that's what hardware gain
    ///         is for)
    func start(preferredDeviceUID: String? = nil, requestedGain: Float? = nil) async throws {
        if isRecording { return }
        let id = UUID()
        captureID = id
        stopTask?.cancel()
        stopTask = nil

        let granted = await requestAccess()
        try Task.checkCancellation()
        guard captureID == id else { throw CancellationError() }
        guard granted else {
            throw DictationAudioError.permissionDenied
        }

        interruption = nil
        streamWrapper.reset()
        finalizedCollectedSamples = []
        tapSink = DictationAudioTapSink(
            targetFormat: targetFormat,
            targetSampleRate: targetSampleRate,
            streamWrapper: streamWrapper
        )

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["JACK_DICTATION_TEST_AUDIO"], let tapSink {
            try startTestFeed(path: path, sink: tapSink)
            return
        }
        #endif

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
                preferBuiltInMic: preferBuiltInMic(),
                requestedGain: requestedGain
            )
        } catch {
            guard captureID == id, !Task.isCancelled else { throw CancellationError() }
            audioEngine = nil
            if let dictationErr = error as? DictationAudioError, dictationErr == .audioSystemUnresponsive {
                logger.error("AVAudioEngine build timed out — coreaudiod appears wedged")
            }
            throw error
        }

        // The build may have changed the device volume. Every exit below that
        // doesn't reach recording puts it back; once recording,
        // `finalizeStop()` owns the restore.
        var recordingStarted = false
        defer { if !recordingStarted { setup.volumeToRestore?.apply() } }

        // A key release or Escape can arrive while permission/setup is awaiting.
        // Never start the microphone after that session has already ended.
        try Task.checkCancellation()
        guard captureID == id else { throw CancellationError() }

        let engine = setup.engine
        audioEngine = engine
        tapSink?.levelProcessor.inputBoost = setup.softwareGainFactor

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

        configurationObserver = Self.observeConfigurationChanges(for: engine) { [weak self] in
            guard let self, self.captureID == id, self.isRecording else { return }
            self.interruption = .deviceChanged
            self.stop(immediately: true)
        }
        volumeToRestore = setup.volumeToRestore
        recordingStarted = true
        startedAt = Date()
        isRecording = true
        logger.info("Dictation audio capture started")
    }

    static func observeConfigurationChanges(
        for engine: AVAudioEngine,
        onInterruption: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        let checkEngine: @MainActor () -> Void = { [weak engine] in
            // Startup can deliver a queued configuration notification after
            // recording begins. A real hardware interruption stops the engine;
            // check its current state before tearing down a working microphone.
            guard let engine, !engine.isRunning else { return }
            onInterruption()
        }
        return NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            Task { @MainActor in
                checkEngine()
            }
        }
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
        let volumeToRestore: DeviceVolumeRestore?
    }

    /// A device's input volume from before Jack changed it.
    private struct DeviceVolumeRestore: Sendable {
        let uid: String
        let volume: Float

        /// Synchronous so a session that starts right after this one reads
        /// the user's own volume as "previous", not the one Jack applied.
        func apply() {
            AudioInputDeviceManager.setHardwareGain(volume, forUID: uid)
        }
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
        preferBuiltInMic: Bool,
        requestedGain: Float?,
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
                let defaultID = AudioInputDeviceManager.defaultInputDeviceID()
                let bindUID = AudioInputDeviceManager.dictationInputUID(
                    preferredUID: preferredDeviceUID,
                    defaultTransport: defaultID.map { AudioInputDeviceManager.transportType(forID: $0) },
                    availableDevices: AudioInputDeviceManager.inputDevices(),
                    preferBuiltInOverBluetooth: preferBuiltInMic
                )

                // Decide which gain mode applies. The check has to happen
                // against the device the engine ACTUALLY ended up bound to —
                // if `bind` failed (unplugged), we resolve gain against the
                // live system default.
                let effectiveUID = AudioInputDeviceManager.bind(engine, toUID: bindUID)
                    ? bindUID
                    : defaultID.flatMap { AudioInputDeviceManager.deviceUID(forID: $0) }
                let softwareGain: Float
                var volumeToRestore: DeviceVolumeRestore?
                if let requestedGain, let effectiveUID,
                   AudioInputDeviceManager.canSetHardwareGain(forUID: effectiveUID) {
                    // Only touch the device's own volume when the user picked
                    // a gain, and remember the old level so it comes back.
                    volumeToRestore = AudioInputDeviceManager.hardwareGain(forUID: effectiveUID)
                        .map { DeviceVolumeRestore(uid: effectiveUID, volume: $0) }
                    AudioInputDeviceManager.setHardwareGain(max(0, min(1, requestedGain)), forUID: effectiveUID)
                    softwareGain = 1.0
                } else {
                    softwareGain = max(1.0, min(2.0, requestedGain ?? 1.0))
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
                        softwareGainFactor: softwareGain,
                        volumeToRestore: volumeToRestore
                    ))
                } else {
                    // `start()` already gave up on this build after the
                    // timeout, so nobody else will undo the volume change.
                    volumeToRestore?.apply()
                }
            }
        }
    }

    /// Hang the mic open briefly after key release so the trailing syllable
    /// isn't clipped. Flash finalization injects trailing silence before `finish()`.
    private let trailingHangNanoseconds: UInt64 = 100_000_000

    func stop(immediately: Bool = false) {
        stopTask?.cancel()
        stopTask = nil
        guard isRecording else {
            captureID = nil
            tapSink = nil
            streamWrapper.finish()
            return
        }
        if immediately {
            finalizeStop()
            return
        }
        let id = captureID
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.trailingHangNanoseconds ?? 0)
            guard !Task.isCancelled, self?.captureID == id else { return }
            self?.finalizeStop()
        }
    }

    private func finalizeStop() {
        guard isRecording else { return }
        #if DEBUG
        testFeedTask?.cancel()
        testFeedTask = nil
        #endif
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
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
        volumeToRestore?.apply()
        volumeToRestore = nil
        finalizedCollectedSamples = tapSink?.drainAndSnapshot() ?? []
        interruption = interruption ?? tapSink?.failure ?? streamWrapper.failure
        tapSink = nil
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        isRecording = false
        captureID = nil
        streamWrapper.finish()
        logger.info("Dictation audio capture stopped after \(String(format: "%.2f", duration))s")
    }

    #if DEBUG
    private var testFeedTask: Task<Void, Never>?

    /// Test-only microphone. With `JACK_DICTATION_TEST_AUDIO` set to an audio
    /// file, a debug build hears that file in real time, then silence until
    /// the session stops, so a whole dictation can be measured end to end
    /// without anyone speaking. Release builds never compile this.
    private func startTestFeed(path: String, sink: DictationAudioTapSink) throws {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        let frames: AVAudioFrameCount = 1024
        let interval = Double(frames) / format.sampleRate
        nonisolated(unsafe) let source = file
        testFeedTask = Task.detached(priority: .userInitiated) {
            var next = ContinuousClock.now
            while !Task.isCancelled {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                if (try? source.read(into: buffer, frameCount: frames)) == nil || buffer.frameLength == 0 {
                    buffer.frameLength = frames
                    for channel in 0..<Int(format.channelCount) {
                        buffer.floatChannelData?[channel].update(repeating: 0, count: Int(frames))
                    }
                }
                sink.handle(rawBuffer: buffer)
                next = next.advanced(by: .seconds(interval))
                try? await Task.sleep(until: next, clock: .continuous)
            }
        }
        startedAt = Date()
        isRecording = true
        logger.notice("Dictation is hearing a test file instead of the microphone")
    }
    #endif

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
final class DictationAudioTapSink: @unchecked Sendable {
    private let queue: DispatchQueue
    private let targetFormat: AVAudioFormat
    private let targetSampleRate: Double
    private let streamWrapper: DictationAudioStreamWrapper
    private let lock = NSLock()
    private var collectedSamples: [Float] = []
    private var queuedBuffers = 0
    private var processingFailure: DictationAudioError?

    var failure: DictationAudioError? { lock.withLock { processingFailure } }
    var sampleCount: Int { lock.withLock { collectedSamples.count } }
    private var level: Double = 0
    private var resampleConverter: AVAudioConverter?
    private var resampleSourceFormat: AVAudioFormat?
    /// Set on MainActor before the tap is installed, then only used on `queue`.
    var levelProcessor: DictationInputLevelProcessor

    init(
        targetFormat: AVAudioFormat,
        targetSampleRate: Double,
        streamWrapper: DictationAudioStreamWrapper,
        queue: DispatchQueue = DispatchQueue(label: "gilt.dictation.audio", qos: .utility)
    ) {
        self.targetFormat = targetFormat
        self.targetSampleRate = targetSampleRate
        self.streamWrapper = streamWrapper
        self.queue = queue
        self.levelProcessor = DictationInputLevelProcessor(sampleRate: Float(targetSampleRate))
    }

    func handle(rawBuffer: AVAudioPCMBuffer) {
        let accepted = lock.withLock {
            guard processingFailure == nil else { return false }
            guard queuedBuffers < 64 else {
                processingFailure = .overloaded
                return false
            }
            queuedBuffers += 1
            return true
        }
        guard accepted else { return }
        // AVAudioEngine reuses tap storage after this callback returns.
        // Copy before leaving the callback, never inside the worker queue.
        guard let owned = copyPCMBuffer(rawBuffer) else {
            lock.withLock { queuedBuffers -= 1; processingFailure = .overloaded }
            return
        }
        queue.async { [self] in
            defer { lock.withLock { queuedBuffers -= 1 } }
            self.process(owned)
        }
    }

    func snapshotSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return collectedSamples
    }

    func snapshotLevel() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return level
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
        guard let converted = convert(rawBuffer) else {
            lock.withLock { processingFailure = .overloaded }
            return
        }
        guard let channelData = converted.floatChannelData?[0] else { return }
        let frames = Int(converted.frameLength)
        // Target format is mono, so channel 0 is the whole signal.
        levelProcessor.process(UnsafeMutableBufferPointer(start: channelData, count: frames))
        let measuredLevel = MeetingAudioCaptureService.averagePower(of: converted)
        lock.lock()
        // Keep a hard ceiling even if the main actor is delayed. The normal
        // session timer finishes at ten minutes; overflow reports an error.
        guard collectedSamples.count + frames <= Int((DictationAudioCaptureService.maximumDurationSeconds + 1) * targetSampleRate) else {
            processingFailure = .overloaded
            lock.unlock()
            return
        }
        level = measuredLevel
        collectedSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
        lock.unlock()
        streamWrapper.send(converted)
    }

    private func convert(_ rawBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if rawBuffer.format == targetFormat {
            return rawBuffer
        }
        guard let resampled = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(ceil(Double(rawBuffer.frameLength) * targetSampleRate / rawBuffer.format.sampleRate)) + 32
        ) else { return nil }
        if resampleConverter == nil || resampleSourceFormat != rawBuffer.format {
            resampleConverter = AVAudioConverter(from: rawBuffer.format, to: targetFormat)
            // Without downmix the converter keeps only channel 0, so a voice
            // on input 2 of a multi-channel interface would be lost.
            resampleConverter?.downmix = true
            resampleConverter?.sampleRateConverterQuality = AVAudioQuality.high.rawValue
            resampleSourceFormat = rawBuffer.format
        }
        guard let converter = resampleConverter else { return nil }
        let input = SingleUsePCMInput(buffer: rawBuffer)
        var error: NSError?
        converter.convert(to: resampled, error: &error, withInputFrom: input.provide)
        guard error == nil else { return nil }
        return resampled
    }

    private func copyPCMBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let src = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<src.count {
            guard let from = src[index].mData, let to = dst[index].mData else { return nil }
            memcpy(to, from, Int(src[index].mDataByteSize))
        }
        return copy
    }

}

// MARK: - Level control

/// Shapes the 16 kHz mono feed before the recognizer sees it: the user's
/// software boost, a light automatic gain control (AGC) that lifts quiet
/// mics toward a steady speech level, then a soft limiter instead of a hard
/// clip. A plain value type so tests can drive it with synthetic signals.
/// `process` allocates nothing and costs two `exp` calls per buffer plus a
/// multiply per sample (`tanh` only on the rare samples above the knee).
struct DictationInputLevelProcessor {
    /// Speech level the AGC aims for: -20 dBFS RMS.
    static let targetRMS: Float = 0.1
    /// Most the AGC adds: +12 dB. Past that it mostly lifts room noise.
    static let maxBoost: Float = 3.98
    /// Below -50 dBFS the input is background hiss, so the AGC stays at 1.
    static let gateRMS: Float = 0.00316
    /// Samples under this pass through untouched; above it the limiter
    /// bends smoothly toward 1 instead of clipping.
    static let limiterKnee: Float = 0.8

    let sampleRate: Float
    /// The user's software boost (`1...2`) for mics without a settable
    /// hardware volume.
    var inputBoost: Float = 1
    private(set) var agcGain: Float = 1
    private var meanSquare: Float = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    mutating func process(_ samples: UnsafeMutableBufferPointer<Float>) {
        guard !samples.isEmpty else { return }
        let count = Float(samples.count)
        let seconds = count / sampleRate
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let bufferMeanSquare = sum / count * inputBoost * inputBoost
        if meanSquare == 0 {
            // First audio of the session: start the estimate here. Ramping up
            // from zero would read every opening as quiet and boost it.
            meanSquare = bufferMeanSquare
        } else {
            // Slow level estimate: rises in 50 ms so a loud start isn't
            // boosted, falls over 300 ms so pauses between words keep the gain.
            meanSquare += (bufferMeanSquare - meanSquare)
                * Self.smoothing(seconds, timeConstant: bufferMeanSquare > meanSquare ? 0.05 : 0.3)
        }
        let rms = meanSquare.squareRoot()
        // Never attenuate (floor 1), never pass max boost, never lift hiss.
        let wanted = rms < Self.gateRMS ? 1 : min(Self.maxBoost, max(1, Self.targetRMS / rms))
        // Attack faster than release: drop the gain quickly when speech gets
        // loud, raise it slowly so it doesn't pump between words.
        let next = agcGain + (wanted - agcGain)
            * Self.smoothing(seconds, timeConstant: wanted < agcGain ? 0.05 : 0.5)
        // Ramp across the buffer so a gain change never clicks.
        let step = (next - agcGain) / count
        var gain = agcGain
        for index in samples.indices {
            gain += step
            samples[index] = Self.softLimit(samples[index] * inputBoost * gain)
        }
        agcGain = next
    }

    /// Identity up to the knee, then a tanh curve that meets the line with
    /// the same slope and approaches ±1 without passing it.
    static func softLimit(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > limiterKnee else { return x }
        let headroom = 1 - limiterKnee
        return copysign(limiterKnee + headroom * tanh((magnitude - limiterKnee) / headroom), x)
    }

    private static func smoothing(_ seconds: Float, timeConstant: Float) -> Float {
        1 - exp(-seconds / timeConstant)
    }
}

enum DictationAudioError: LocalizedError {
    case permissionDenied
    case deviceChanged, overloaded
    case noInput
    /// Engine bootstrap exceeded its timeout — almost always means coreaudiod
    /// is in a bad state. Recovery is "try again, and if that fails restart
    /// the Mac"; nothing the app can do from userland will un-wedge a stuck
    /// coreaudiod. Surfaced as a failed session so the next dictation attempt
    /// gets a clean slate.
    case audioSystemUnresponsive

    var errorDescription: String? {
        switch self {
        case .deviceChanged: return L10n.string("dictation.error.deviceChanged", default: "The microphone changed or disconnected. Copy your draft, check your microphone, and try again.")
        case .overloaded: return L10n.string("dictation.error.overloaded", default: "Speech processing couldn't keep up. Copy your draft and try a shorter dictation.")
        case .permissionDenied: return L10n.string("dictation.error.permission", default: "Microphone access is required for dictation.")
        case .noInput: return L10n.string("dictation.error.noInput", default: "No audio input detected. Connect a mic and try again.")
        case .audioSystemUnresponsive: return L10n.string("dictation.error.audioSystem", default: "Audio system isn't responding. Try again. If it keeps happening, restart your Mac.")
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

final class DictationAudioStreamWrapper: @unchecked Sendable {
    /// About 90 s of 16 kHz chunks (a few MB at most). The English model can
    /// take about 10 s to load after an idle unload, and everything said
    /// meanwhile waits here; the old 512 (about 11 s) left no margin.
    static let bufferLimit = 4096
    private(set) var stream: AsyncStream<AVAudioPCMBuffer>
    private let lock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var overflowed = false
    var failure: DictationAudioError? { lock.withLock { overflowed ? .overloaded : nil } }

    init() {
        var continuationOut: AsyncStream<AVAudioPCMBuffer>.Continuation?
        self.stream = AsyncStream(bufferingPolicy: .bufferingOldest(Self.bufferLimit)) { continuation in
            continuationOut = continuation
        }
        self.continuation = continuationOut
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        var continuationOut: AsyncStream<AVAudioPCMBuffer>.Continuation?
        overflowed = false
        stream = AsyncStream(bufferingPolicy: .bufferingOldest(Self.bufferLimit)) { continuation in
            continuationOut = continuation
        }
        continuation = continuationOut
    }

    func send(_ buffer: sending AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if case .dropped = continuation?.yield(buffer) { overflowed = true }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }
}

final class SingleUsePCMInput: @unchecked Sendable {
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
