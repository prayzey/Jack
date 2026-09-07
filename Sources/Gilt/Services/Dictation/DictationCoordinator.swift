@preconcurrency import AVFoundation
import Combine
import Foundation
import OSLog
import QuartzCore
import SwiftUI

/// Central state machine for the dictation feature.
///
/// State flow:
///   idle → listening → transcribing → (rewriting) → pasting → done → idle
///
/// External signals into this coordinator:
///   - `startSession()` / `stopSession()` from `DictationHotkeyMonitor`
///   - `cancelSession()` from the overlay's Escape key handler
///
/// External signals out:
///   - `phase` (drives the floating overlay)
///   - `level` (drives the grid animation)
///   - `lastResult` (drives history + paste handoff)
@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var phase: DictationPhase = .idle
    /// Live mic RMS — proxied from the audio service for view binding ease.
    @Published private(set) var level: Double = 0
    @Published private(set) var isPreparing = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var lastResultWasCopied = false
    @Published private(set) var polishWasSkipped = false
    private var meterTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private var pasteTargetTask: Task<DictationPasteTarget?, Never>?
    private var sessionTargetApp: (bundleID: String, displayName: String)?
    private var sessionTargetPID: pid_t?
    private var sleepObserver: NSObjectProtocol?
    /// Rolling partial transcript — accumulates as the engine yields finalized
    /// chunks during the listening phase. Empty until the first chunk lands.
    /// This is what makes the pill feel "live" rather than buffered:
    /// the user sees their words appearing under the grid as they speak.
    @Published private(set) var liveTranscript: String = ""
    /// How many leading words in `liveTranscript` are visually confirmed (sharp).
    /// The remaining words stay readable in a lighter shade until confirmed.
    @Published private(set) var liveTranscriptStableWordCount: Int = 0

    /// Most recent completed dictation. The view layer can show "Done — pasted"
    /// briefly before fading out.
    @Published private(set) var lastResult: String?
    /// What this dictation is *for* — `.polish` is the default flow that
    /// cleans + pastes the transcript; `.askScreen` treats the transcript as
    /// a question to answer against the frontmost window's contents.
    ///
    /// Published so the floating pill can render differently per mode
    /// without the coordinator handing it explicitly.
    @Published private(set) var currentMode: DictationMode = .polish
    /// Sink for `.compose` mode. Set by `DictationComposeWindowManager` while
    /// the compose window is open and cleared when it closes. When present,
    /// a compose-mode dictation delivers its finished text here (inserted at
    /// the editor's caret) instead of pasting into the frontmost app. Nil at
    /// all other times, so a compose-mode session that somehow fires with the
    /// window closed simply drops the text rather than pasting it somewhere
    /// the user didn't expect.
    var onComposeText: ((String) -> Void)?
    /// True while a dictation is in flight (anything other than idle).
    var isActive: Bool {
        switch phase {
        case .idle: return false
        case .listening, .transcribing, .rewriting, .executing, .pasting, .done, .failed:
            return true
        }
    }

    /// Engine cache — Parakeet/Whisper warm-up is expensive (multi-second
    /// first time, ~150ms otherwise). Held until the idle watcher releases
    /// it per the user's `engineIdleUnload` setting.
    private var engine: MeetingTranscriptionEngineProtocol?
    private var engineID: MeetingTranscriptionEngine?
    private lazy var transcriptionService: MeetingTranscriptionService = {
        let modelsRoot = MeetingAppSupportLocator.modelsRoot(
            in: MeetingAppSupportLocator.meetingsRoot()
        )
        return MeetingTranscriptionService(modelsRoot: modelsRoot)
    }()

    private let audio: DictationAudioCaptureService
    private let paste = DictationPasteService()
    private let ducker = AudioDucker()
    private let screenContext = ScreenContextService.shared
    /// Used by `.askScreen` mode to grab the full raw text of the frontmost
    /// window (not just the extracted spelling-hint terms that the polish
    /// path uses). Cheap to instantiate — stateless aside from its logger.
    private let askScreenReader = ScreenContextReader()
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationCoordinator")
    private weak var store: DictationStore?
    private weak var statsStore: TranscriptionStatsStore?
    /// Optional — attached by `ClipboardStore` after init. When present and
    /// `DictationSettings.learnFromEdits` is on, polish-mode pastes spawn a
    /// background watch that may learn word-level corrections.
    private var correctionLearner: CorrectionLearner?
    /// Optional — same lifecycle as `correctionLearner`. Read at Polish
    /// prompt-build time so learned corrections inject as vocab terms.
    private weak var correctionStore: CorrectionStore?
    private var voiceActionExecutor: VoiceActionExecutor?
    /// Which model backs this session's polish passes. Decided once at
    /// session start: Qwen on machines with memory headroom, the Apple
    /// Intelligence system model on 8 GB Macs (out-of-process, ~zero app
    /// memory). The same choice governs the final pass; nil preserves the transcript.
    private enum PolishProvider { case qwen, appleIntelligence }
    private var livePolishProvider: PolishProvider?
    /// Re-polishes completed sentences while the user is still speaking so
    /// the caption visibly heals ("tomatoes… oops, onions" → "onions").
    private var livePolisher: LiveDictationPolisher?
    /// Latest cumulative streaming transcript — what `livePolisher.compose`
    /// splices its polished prefix into when a pass lands.
    private var currentLiveRaw = ""
    private var currentLiveCommitted = ""
    private var sessionTask: Task<Void, Never>?
    private var screenContextTask: Task<[String]?, Never>?
    /// Parallel task used only by `.askScreen` mode. Captures the full raw
    /// window text (vs. `screenContextTask` which keeps only term lists).
    /// Kicked off at session start because by the time the user releases the
    /// key, Jack is frontmost and the target window is gone.
    private var askScreenCaptureTask: Task<ScreenContextReader.CaptureResult?, Never>?
    private var sessionStartedAt: Date?
    /// Screen-context terms merged into live vocab once the parallel capture lands.
    private var liveScreenContextTerms: [String] = []
    /// Built once per session — vocab matcher is not rerun on every partial.
    private var sessionWeightedTerms: [VocabularyMatcher.WeightedTerm] = []
    private var lastCaptionPublishAt: CFAbsoluteTime = 0
    /// Trailing-edge republish of a debounce-dropped caption — see
    /// `publishLiveCaption`.
    private var pendingCaptionFlushTask: Task<Void, Never>?

    /// Timestamp of the most recent meaningful "the user is using dictation"
    /// signal. Compared against `settings.engineIdleUnload.idleSeconds` by
    /// the idle watcher — when the gap exceeds the threshold and we're idle,
    /// the engine + Qwen are released. Pattern lifted from Handy's
    /// `TranscriptionManager.touch_activity` / idle thread.
    private var lastActivityAt: Date = Date()
    /// Background task that ticks every 10 seconds and considers unloading
    /// the loaded engines. Started lazily on first use, cancelled when no
    /// engines are loaded so we don't spin a timer for nothing.
    private var idleWatcherTask: Task<Void, Never>?

    init(audio: DictationAudioCaptureService = DictationAudioCaptureService()) {
        self.audio = audio
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive, self.phase != .done else { return }
                self.fail(reason: L10n.string("dictation.error.sleep", default: "Dictation stopped because your Mac went to sleep. You can copy the draft below."))
            }
        }
    }

    isolated deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }

    func attach(store: DictationStore) {
        self.store = store
    }

    /// Attached separately from `attach(store:)` because the stats store is
    /// owned by `ClipboardStore`, not `DictationStore`. We don't want the
    /// dictation domain to know anything about clipboard internals — it just
    /// gets handed a sink to forward word counts into.
    func attach(statsStore: TranscriptionStatsStore) {
        self.statsStore = statsStore
    }

    /// Attached by `ClipboardStore` once the model container is up. Pair:
    /// the learner is what spawns AX watches after each polish paste; the
    /// store is what the polish prompt-builder reads to inject learned
    /// corrections as vocabulary terms.
    func attach(correctionLearner: CorrectionLearner, correctionStore: CorrectionStore) {
        self.correctionLearner = correctionLearner
        self.correctionStore = correctionStore
    }

    /// Attached by `Jack` bootstrap. Executes native voice commands (reminders,
    /// Spotify) in `.actions` mode.
    func attach(voiceActionExecutor: VoiceActionExecutor) {
        self.voiceActionExecutor = voiceActionExecutor
    }

    // MARK: - Public lifecycle

    /// Begin a dictation session. Safe to call from any thread.
    ///
    /// `mode` defaults to `.polish` so existing callers (the primary
    /// dictation hotkey, the toggle handler, anything else that doesn't
    /// know about modes) keep working unchanged. The second hotkey monitor
    /// owned by `DictationLauncher` passes `.askScreen` to fire the
    /// ask-the-screen flow.
    func startSession(mode: DictationMode = .polish) {
        if case .failed = phase { resetToIdle() }
        guard !isActive else { return }
        let id = UUID()
        sessionID = id
        sessionTargetApp = TranscriptionStatsStore.frontmostAppSnapshot()
        sessionTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if mode == .polish || mode == .askScreen, let pid = sessionTargetPID {
            pasteTargetTask = Task.detached { DictationPasteTarget.capture(pid: pid) }
        }
        isPreparing = true
        elapsedSeconds = 0
        lastResult = nil
        lastResultWasCopied = false
        polishWasSkipped = false
        sessionStartedAt = Date()
        liveTranscript = ""
        liveTranscriptStableWordCount = 0
        liveScreenContextTerms = []
        sessionWeightedTerms = []
        lastCaptionPublishAt = 0
        currentMode = mode
        phase = .listening
        logger.info("Dictation session started — mode=\(mode.rawValue)")
        touchActivity()
        startIdleWatcherIfNeeded()

        // Fade other audio down (if the user enabled it) right as we enter
        // the listening phase. We don't await this on the main lifecycle
        // path — the ducker fades the system volume in the background while
        // we kick off audio capture.
        if let settings = store?.settings, settings.duckOtherAudio {
            Task { [weak self] in
                guard let self, self.sessionID == id, self.phase == .listening else { return }
                await self.ducker.startDucking(amount: settings.duckAmount)
            }
        }

        // Kick screen capture immediately. The user's target app is still
        // frontmost at this exact moment — once they start speaking and the
        // dictation pill takes focus the frontmost-app heuristic would
        // point at Jack itself. Two parallel paths because the two modes
        // want different shapes of result.
        screenContextTask = nil
        askScreenCaptureTask = nil
        switch mode {
        case .polish:
            // Term-list capture for the spelling-hint Polish prompt.
            if let settings = store?.settings, settings.useScreenContext {
                let existingVocab = settings.allActiveVocabularyTerms()
                screenContextTask = Task { [screenContext, settings, existingVocab] in
                    await screenContext.capture(
                        settings: settings,
                        existingVocabulary: existingVocab
                    )
                }
            }
        case .askScreen:
            // Full-text capture for ScreenQAEngine. We deliberately ignore
            // `useScreenContext` here — askScreen is itself a request to
            // read the screen, so the user's intent supersedes the polish-
            // mode toggle. Capture mode defaults to AX + OCR fallback (the
            // best-coverage option) regardless of the polish setting.
            let mode = store?.settings.screenContextMode ?? .accessibilityWithOCRFallback
            let excluded = store?.settings.screenContextExcludedBundleIDs ?? []
            let axMin = store?.settings.screenContextAXMinimumChars ?? 80
            askScreenCaptureTask = Task { [askScreenReader] in
                await askScreenReader.capture(
                    mode: mode,
                    excludedBundleIDs: excluded,
                    axMinimumChars: axMin
                )
            }
        case .compose:
            // No screen-context capture. Compose reuses the polish pipeline in
            // runSession, but the frontmost window at session start is Jack's
            // own compose editor — reading it back as spelling-hint context
            // would be noise. Custom/pack vocab still applies; it doesn't
            // depend on screenContextTask.
            break
        case .actions:
            break
        }

        sessionTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.sessionID == id else { return }
            // The release can precede even the first turn of this task.
            guard self.phase == .listening else {
                self.resetToIdle()
                return
            }
            do {
                try await self.runSession()
            } catch {
                guard !Task.isCancelled, self.sessionID == id else { return }
                if error is CancellationError {
                    self.resetToIdle()
                    return
                }
                self.logger.error("Session failed: \(error.localizedDescription)")
                self.fail(reason: error.localizedDescription)
            }
        }
    }

    /// Stop recording and proceed to transcription. Pushed by hotkey release
    /// (push-to-talk) or a second tap (toggle).
    func stopSession() {
        guard case .listening = phase else { return }
        logger.info("Dictation session stopping — moving to transcription")
        // Flip the phase immediately so the pill swaps to "Transcribing"
        // the moment the user releases. The audio service's stream finish
        // will propagate through the engine's transcribeStream and let the
        // final chunk land before we move on to polish/paste.
        phase = .transcribing
        let id = sessionID
        finalizationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.sessionID == id, self.phase == .transcribing else { return }
            self.fail(reason: L10n.string("dictation.error.finalizeTimeout", default: "Finishing the transcript took too long. Copy your draft and try again."))
        }
        audio.stop()
        // Bring other audio back up as soon as we stop listening — the user
        // shouldn't have to wait through transcription + polish + paste to
        // hear their music again.
        Task { [weak self] in await self?.ducker.stopDucking() }
    }

    /// Tear everything down immediately, paste nothing, keep nothing.
    func cancelSession() {
        guard isActive else { return }
        logger.info("Dictation session cancelled")
        audio.stop(immediately: true)
        sessionTask?.cancel()
        sessionTask = nil
        screenContextTask?.cancel()
        screenContextTask = nil
        askScreenCaptureTask?.cancel()
        askScreenCaptureTask = nil
        Task { [weak self] in await self?.ducker.stopDucking() }
        resetToIdle()
    }

    /// Called when the toggle trigger fires — start if idle, stop if recording.
    func handleToggle(mode: DictationMode = .polish) {
        switch phase {
        case .listening:
            stopSession()
        case .idle, .failed:
            startSession(mode: mode)
        default:
            // Ignore extra presses while transcribing/pasting — a second tap
            // must not start a overlapping session or tear down in-flight work.
            break
        }
    }

    // MARK: - Session runner

    private func runSession() async throws {
        guard let store else {
            throw NSError(domain: "Jack.Dictation", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Dictation store not attached"
            ])
        }

        let settings = store.settings
        let id = sessionID

        // 1. Capture starts immediately — buffers begin queueing in the
        // audio service's AsyncStream regardless of whether the engine is
        // ready. The user sees the grid animate as soon as their voice
        // arrives.
        try await audio.start(
            preferredDeviceUID: settings.preferredMicDeviceUID,
            requestedGain: settings.inputGain
        )

        try Task.checkCancellation()
        isPreparing = false
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard let self, !Task.isCancelled, self.sessionID == id,
                      self.phase == .listening else { return }
                self.level = self.audio.level
                self.elapsedSeconds = self.audio.elapsedSeconds
                if let error = self.audio.failure {
                    self.fail(reason: error.localizedDescription)
                    return
                }
                if self.elapsedSeconds >= DictationAudioCaptureService.maximumDurationSeconds {
                    self.stopSession()
                    return
                }
            }
        }

        // 2. Warm the engine synchronously. On a warm cache this is ~150ms;
        // on a cold one (first launch) it can take several seconds. While we
        // wait, audio is still buffering — we won't drop frames. The pill
        // already shows "Listening" so the user has no idea anything is
        // catching up.
        // Respect the user's engine pick from Settings → Dictate → Advanced;
        // normalize legacy / meeting-only selections back to the default.
        let speechEngine = MeetingTranscriptionEngine.normalizedDictationEngine(settings.speechEngine)
        store.settings.speechEngine = speechEngine
        let engine = ensureEngine(for: speechEngine)
        if let native = engine as? AppleSpeechTranscriptionEngine { await native.refreshAvailability() }

        // Guardrail: warmUp() will silently kick off a Hugging Face download
        // if the model isn't on disk yet. That can mean hundreds of MB
        // streaming in while the dictation pill just sits there looking
        // frozen. Bail early with a clear message instead — the user
        // explicitly downloads from Settings → Dictate → Advanced.
        if !engine.isReady {
            logger.info("Dictation aborted — dictation model not downloaded")
            fail(reason: L10n.string("dictation.error.modelMissing", default: "Download the speech model in Settings → Dictate → Advanced, then try again."))
            return
        }

        try await engine.warmUp()

        if Task.isCancelled { return }

        // 3. Live caption while audio arrives.
        var liveAccumulated = ""
        sessionWeightedTerms = LiveCaptionComposer.buildWeightedTerms(
            settings: settings,
            correctionStore: correctionStore,
            screenTerms: liveScreenContextTerms
        )
        if let native = engine as? AppleSpeechTranscriptionEngine {
            native.vocabularyHints = Array(sessionWeightedTerms.map(\.canonical).prefix(100))
        }
        let styleEngine = DictationStyleEngine(cacheDirectory: store.qwenCacheURL)
        setUpLivePolisher(settings: settings, speechEngine: speechEngine, styleEngine: styleEngine)
        let liveScreenTermsTask = screenContextTask
        Task { [weak self] in
            let terms = await liveScreenTermsTask?.value ?? []
            await MainActor.run {
                guard let self, self.sessionID == id, self.phase == .listening else { return }
                self.liveScreenContextTerms = terms
                self.sessionWeightedTerms = LiveCaptionComposer.buildWeightedTerms(
                    settings: settings,
                    correctionStore: self.correctionStore,
                    screenTerms: terms
                )
            }
        }
        // Windowed live preview — canonical paste may still re-decode below.
        let startedAt = sessionStartedAt ?? Date()
        let chunkStream = engine.transcribeStream(
            from: audio.audioBufferStream,
            meetingStartedAt: startedAt
        )
        var previousWindowText = ""
        for try await chunk in chunkStream {
            if Task.isCancelled { return }
            let windowText = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let update = chunk.streamingUpdate {
                liveAccumulated = update.text
                currentLiveRaw = update.text
                currentLiveCommitted = update.confirmedText
                livePolisher?.ingest(committedRaw: update.confirmedText)
                let state = livePolisher?.compose(
                    cumulativeRaw: update.text, committedRaw: update.confirmedText
                ) ?? LiveCaptionComposer.State(
                    text: update.text,
                    stableWordCount: LiveCaptionComposer.wordCount(update.confirmedText)
                )
                publishLiveCaption(state, force: update.isFinal, skipCleanup: true)
                continue
            }
            guard !windowText.isEmpty else { continue }
            let merged = LiveCaptionComposer.mergeWindowed(
                accumulated: liveAccumulated,
                previousWindow: previousWindowText,
                currentWindow: windowText
            )
            liveAccumulated = merged.text
            previousWindowText = windowText
            publishLiveCaption(merged)
        }

        if Task.isCancelled { return }

        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        if let error = audio.failure { throw error }
        elapsedSeconds = audio.elapsedSeconds

        // Native streaming has already finalized, including an empty result.
        // Windowed engines may still need a full decode.
        let collected = audio.collectedSamples
        let liveFallback = liveAccumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collected.isEmpty || !liveFallback.isEmpty else {
            logger.info("Dictation produced no audio — discarding session")
            fail(reason: L10n.string("dictation.error.noSpeech", default: "No speech was detected. Check your microphone and try again."))
            return
        }
        let oneShotRawFromEngine: String
        if speechEngine.supportsNativeStreaming {
            // The streaming decode IS the canonical transcript for the
            // unified model — the final chunk already drained the
            // decoder's right context. A second full decode would only
            // add latency between key release and paste.
            oneShotRawFromEngine = liveFallback
        } else if !settings.postProcessEnabled {
            let live = liveAccumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if !live.isEmpty {
                oneShotRawFromEngine = live
            } else {
                oneShotRawFromEngine = try await engine.transcribeSamples(collected)
            }
        } else {
            oneShotRawFromEngine = try await engine.transcribeSamples(collected)
        }

        if Task.isCancelled { return }

        // Strip Parakeet's trailing period when the user dictated only one
        // word. Done at the engine boundary, before any other pass, so a
        // genuine "hello period" (two words out of Parakeet) doesn't get
        // its explicit period stripped after the spoken-punctuation
        // expansion later collapses it to a single-token "hello.".
        let oneShotRaw = TranscriptCleaner.stripSingleWordTrailingPeriod(oneShotRawFromEngine)

        // Mode fork. Polish keeps going through the cleaner / vocab /
        // optional-Qwen pipeline below. AskScreen splits off here because
        // it doesn't want polish, doesn't want vocab substitutions, and
        // wants to send the transcript verbatim as the *question* to Qwen.
        if currentMode == .actions {
            try await runVoiceActions(transcript: oneShotRaw, store: store)
            return
        }
        if currentMode == .askScreen {
            try await runAskScreen(question: oneShotRaw, store: store)
            return
        }

        // 5. Vocabulary substitutions. Runs first so the cleaner sees the
        // canonical forms ("ChatGPT") rather than the spelled-out variants
        // ("chat g p t"). Engine-agnostic — pure string work.
        //
        // Screen context terms get merged in at the end of the list, so
        // user-curated vocab (which is hand-picked) always wins on dedupe.
        // Never block paste on screen-context capture — use whatever terms we
        // already merged live; late capture is best-effort for polish only.
        screenContextTask?.cancel()
        screenContextTask = nil
        let contextTerms = liveScreenContextTerms
        let weightedTerms = sessionWeightedTerms.isEmpty
            ? LiveCaptionComposer.buildWeightedTerms(
                settings: settings,
                correctionStore: correctionStore,
                screenTerms: contextTerms
            )
            : sessionWeightedTerms
        let withVocab = VocabularyMatcher.apply(oneShotRaw, weighted: weightedTerms)

        // 6. Pre-clean smart formatting: expand spoken punctuation commands
        // ("comma" → ",", "new paragraph" → "\n\n") before the cleaner runs.
        // Deterministic regex work — no model needed.
        //
        // Gated on Polish so "Polish off" really means raw Parakeet output.
        // Without this gate, users who turned Polish off would still get
        // spoken-word punctuation substitution, sentence capitalization,
        // and smart typography — and report (correctly) that "no filter"
        // doesn't feel like no filter. The pre-clean pass only runs as
        // part of the Polish pipeline now.
        let withPunctuation = settings.postProcessEnabled
            ? SmartFormatter.applyPreClean(withVocab, settings: settings)
            : withVocab

        // 7. Always-on filler/stutter cleanup. Cheap regex work; visible
        // polish without an LLM. Mirrors Handy's filter_transcription_output.
        let raw = TranscriptCleaner.clean(withPunctuation)

        guard !raw.isEmpty else {
            logger.info("Dictation produced no transcript")
            fail(reason: L10n.string("dictation.error.noSpeech", default: "No speech was detected. Check your microphone and try again."))
            return
        }

        // Post-process (optional). Qwen only runs when Polish is on. The
        // structural-formatting toggles (lists, paragraphs) are *modifiers*
        // on the Polish pass — they don't enable Qwen on their own, because
        // otherwise users who explicitly turned Polish off would still
        // silently hit the LLM (and block paste on a download). Matches the
        // user-facing mental model: "Polish off = pure Parakeet, no Qwen."
        let needsQwen = settings.postProcessEnabled
            && (settings.level != .none
                || settings.formatLists
                || settings.formatParagraphs)
        let polished: String
        if needsQwen {
            phase = .rewriting
            // Drain any in-flight live pass first — the shared model must
            // never see two generate calls at once, and a drained pass may
            // already cover the whole final transcript (reuse below).
            await livePolisher?.finishSession()
            if Task.isCancelled { return }
            let effectiveLevel = settings.postProcessEnabled ? settings.level : .none
            if !settings.formatLists, !settings.formatParagraphs,
               let live = livePolisher?.finalResult(matching: raw) {
                // The user paused before releasing the key, so live polish
                // already processed the exact final transcript — paste with
                // zero extra model latency. ponytail: exact-match reuse only;
                // splicing a suffix-only pass onto the live prefix is the
                // upgrade path if this doesn't hit often enough.
                logger.info("Live polish covered the final transcript — skipping final pass")
                polished = live
            } else if livePolishProvider == .appleIntelligence {
                // 8 GB machines: the whole session runs on the system model
                // so the 2.4 GB Qwen never loads. Same prompt matrix, same
                // failure posture (nil → raw transcript).
                let prompt = DictationStyleEngine.makePrompt(
                    style: settings.style,
                    level: effectiveLevel,
                    formatLists: settings.formatLists,
                    formatParagraphs: settings.formatParagraphs,
                    screenContextTerms: contextTerms,
                    transcript: raw
                )
                let output = await AppleIntelligencePolisher.polish(
                    prompt: prompt,
                    onPartial: { [weak self] partial in
                        guard let self, self.sessionID == id, self.phase == .rewriting else { return }
                        let preview = DictationStyleEngine.cleanOutput(partial, original: raw)
                        if !preview.isEmpty { self.publishPolishPreview(preview) }
                    }
                )
                var cleaned = DictationStyleEngine.cleanOutput(output ?? "", original: raw)
                if settings.formatLists {
                    cleaned = DictationStyleEngine.normalizeInlineNumberedList(cleaned)
                }
                polished = DictationStyleEngine.validatedOutput(cleaned, original: raw)
                polishWasSkipped = output == nil || (polished == raw && cleaned != raw)
            } else if livePolishProvider == .qwen {
                polished = await styleEngine.process(
                    rawTranscript: raw,
                    style: settings.style,
                    // If the user wants formatting but didn't turn on AI polish,
                    // we still need a level — `.none` keeps Qwen from rewriting
                    // wording while still letting it format structure.
                    level: effectiveLevel,
                    formatLists: settings.formatLists,
                    formatParagraphs: settings.formatParagraphs,
                    screenContextTerms: contextTerms,
                    onFallback: { [weak self] in
                        guard let self, self.sessionID == id, self.phase == .rewriting else { return }
                        self.polishWasSkipped = true
                    },
                    // Stream the rewrite into the overlay so the user watches
                    // their raw words heal into the polished version instead of
                    // staring at a frozen transcript behind "Polishing…".
                    onPartial: { [weak self] preview in
                        guard let self, self.sessionID == id, self.phase == .rewriting else { return }
                        self.publishPolishPreview(preview)
                    }
                )
            } else {
                polished = raw
                polishWasSkipped = true
            }
        } else {
            polished = raw
        }

        // 8. Post-clean smart formatting — runs on the final canonical text.
        // Sentence capitalization and curly quotes / em dashes belong here
        // because they depend on final sentence boundaries.
        //
        // Same gating as step 6: skip entirely when Polish is off so the
        // user gets raw Parakeet output (modulo the always-on filler
        // cleanup and any vocab packs they opted into). Without this gate,
        // standalone "i" still becomes "I", every sentence start gets
        // capitalized, and quotes get curled — all of which read as
        // "polish is too strong" when the user explicitly disabled Polish.
        let finalText = settings.postProcessEnabled
            ? SmartFormatter.applyPostClean(polished, settings: settings)
            : polished

        if Task.isCancelled { return }

        // Land the canonical text in the caption (no debounce) so the brief
        // pasting/done beat shows exactly what was pasted, not a mid-stream
        // partial.
        publishPolishPreview(finalText, force: true)

        // Compose mode short-circuits the paste path. The finished text goes
        // to the open compose editor (inserted at the caret) rather than into
        // some external app, so there's no target-app snapshot, no pasteboard
        // dance, and no correction watch (which only makes sense against the
        // external field the user pasted into). The clipboard is left
        // untouched — composing must never clobber what the user copied.
        if currentMode == .compose {
            onComposeText?(finalText)
            lastResult = finalText
            // Duration must be read before resetToIdle() nils sessionStartedAt.
            Analytics.dictationCompleted(
                mode: DictationMode.compose.rawValue,
                durationSeconds: audio.elapsedSeconds
            )
            resetToIdle()
            touchActivity()
            maybeUnloadImmediately(reason: "compose complete")
            return
        }

        // Attribute delivery and learning to the destination captured before
        // recording, even if focus moved while recognition was finishing.
        let targetApp = sessionTargetApp
        // Learning only starts after a paste to this unchanged destination.
        let targetPID = sessionTargetPID

        // Paste and/or save. When `saveToClipboardHistory` is on we skip the
        // pasteboard restore — the dictation text stays on the clipboard so
        // `ClipboardMonitor` ingests it naturally on its next tick. When the
        // user has both auto-paste and history off, copyOnly() at least lets
        // them Cmd+V manually.
        phase = .pasting
        let copied: Bool
        if settings.autoPasteIntoActiveApp {
            copied = await !paste.paste(
                text: finalText,
                restorePasteboard: !settings.saveToClipboardHistory,
                target: await pasteTargetTask?.value
            )
        } else {
            paste.copyOnly(finalText, saveToHistory: settings.saveToClipboardHistory)
            copied = true
        }
        guard !Task.isCancelled, sessionID == id else { return }
        lastResultWasCopied = copied

        lastResult = finalText
        // Brief "Pasted" beat in the overlay before teardown. Duration must
        // be read before resetToIdle() nils sessionStartedAt — the old
        // reset-first order recorded every dictation as 0 seconds.
        phase = .done

        let duration = audio.elapsedSeconds
        Analytics.dictationCompleted(mode: currentMode.rawValue, durationSeconds: duration)
        let entry = DictationHistoryEntry(
            text: finalText,
            rawTranscript: oneShotRawFromEngine,
            style: settings.style,
            level: settings.level,
            durationSeconds: duration
        )
        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { return }
            if settings.learnFromEdits, !self.lastResultWasCopied,
               let learner = self.correctionLearner,
               settings.autoPasteIntoActiveApp
            {
                learner.startWatching(
                    pastedText: finalText,
                    targetAppPID: targetPID,
                    targetAppName: targetApp?.displayName,
                    targetAppBundleID: targetApp?.bundleID
                )
            }
            store.appendHistory(entry)
            self.statsStore?.recordDictation(
                entryID: entry.entryID,
                words: TranscriptionStatsStore.wordCount(finalText),
                durationSeconds: duration,
                appBundleID: targetApp?.bundleID,
                appDisplayName: targetApp?.displayName,
                at: entry.createdAt
            )
            self.touchActivity()
            self.maybeUnloadImmediately(reason: "transcription complete")
        }

        // Hold the done state just long enough to register, then tear down.
        // Guarded so a cancel/new session that already moved the phase
        // doesn't get yanked back to idle underneath the user.
        try? await Task.sleep(for: .seconds((lastResultWasCopied || polishWasSkipped) ? 3 : 0.7))
        if !Task.isCancelled, sessionID == id, case .done = phase {
            resetToIdle()
        }
    }

    // MARK: - Voice actions session runner

    private func runVoiceActions(transcript: String, store: DictationStore) async throws {
        let settings = store.settings
        let cleanedTranscript = TranscriptCleaner
            .clean(transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTranscript.isEmpty else {
            logger.info("Voice actions produced no transcript — discarding session")
            resetToIdle()
            return
        }

        guard let executor = voiceActionExecutor else {
            fail(reason: "Voice actions aren't ready yet. Restart Jack and try again.")
            return
        }

        if Task.isCancelled { return }

        phase = .executing
        let result = await executor.execute(
            transcript: cleanedTranscript,
            connectors: settings.voiceActionConnectors
        )

        if Task.isCancelled { return }

        let message: String
        switch result {
        case .reminderCreated(let title):
            message = "Reminder set: \(title)"
        case .spotify(let text):
            message = text
        case .permissionDenied(let app):
            fail(reason: "\(app) access is required. Turn it on in Settings → Dictate → Voice actions.")
            return
        case .notRecognized:
            fail(reason: "Didn't catch a command. Try “remind me to call mom tomorrow” or “pause”.")
            return
        case .failed(let reason):
            fail(reason: reason)
            return
        }

        lastResult = message
        phase = .done
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }
        resetToIdle()
        touchActivity()
        maybeUnloadImmediately(reason: "voice action complete")
    }

    // MARK: - Ask-the-screen session runner

    /// The post-transcription half of an `.askScreen` session. The transcript
    /// is the user's spoken question; we await the parallel screen-capture
    /// task we kicked off in `startSession`, hand both to `ScreenQAEngine`,
    /// and paste the answer (or a graceful fallback string).
    ///
    /// Mirrors the bookkeeping the polish path does — target-app snapshot
    /// for stats, history entry, paste vs copy depending on settings — so
    /// askScreen feels like a first-class dictation flow, not a side branch.
    private func runAskScreen(question: String, store: DictationStore) async throws {
        let id = sessionID
        let settings = store.settings

        // 1. The raw transcript needs minimal cleanup before becoming a
        // prompt — strip fillers so the question is tight, but skip vocab
        // substitution + smart formatting (this isn't text the user will
        // see; it's a prompt for Qwen).
        let questionCleaned = TranscriptCleaner
            .clean(question)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !questionCleaned.isEmpty else {
            logger.info("AskScreen produced no question — discarding session")
            resetToIdle()
            return
        }

        // 2. Capture is already running in the background — await it.
        phase = .rewriting
        let captureResult = await askScreenCaptureTask?.value
        askScreenCaptureTask = nil

        let screenText = captureResult?.text ?? ""
        let appName = captureResult?.frontmostName

        if Task.isCancelled { return }

        // 3. Ask Qwen. ScreenQAEngine handles all the "model not loaded"
        // and truncation logic internally and returns one of three outcomes.
        let qa = ScreenQAEngine(cacheDirectory: store.qwenCacheURL)
        let outcome = await qa.answer(
            question: questionCleaned,
            screenText: screenText,
            appName: appName
        )

        if Task.isCancelled { return }

        let finalText: String
        switch outcome {
        case .answer(let text):
            finalText = text
        case .modelUnavailable:
            // Don't paste a model-error string into the user's editor —
            // surface the failure on the pill instead, like a transcribe
            // error would.
            fail(reason: "AI model isn't downloaded yet. Open Jack settings to download it, then try again.")
            return
        case .failed(let message):
            fail(reason: "Couldn't answer. \(message)")
            return
        }

        // 4. Mirror the polish path: snapshot target app, paste-or-copy,
        // record history + stats. The history entry stores the *question*
        // as the raw transcript and the *answer* as the final text, so the
        // user can re-read both in dictation history.
        let targetApp = sessionTargetApp

        phase = .pasting
        let copied: Bool
        if settings.autoPasteIntoActiveApp {
            copied = await !paste.paste(
                text: finalText,
                restorePasteboard: !settings.saveToClipboardHistory,
                target: await pasteTargetTask?.value
            )
        } else {
            paste.copyOnly(finalText, saveToHistory: settings.saveToClipboardHistory)
            copied = true
        }
        guard !Task.isCancelled, sessionID == id else { return }
        lastResultWasCopied = copied

        lastResult = finalText
        // Duration must be read before resetToIdle() nils sessionStartedAt —
        // the old reset-first order recorded every ask-screen dictation as 0s.
        let duration = audio.elapsedSeconds
        resetToIdle()

        Analytics.dictationCompleted(mode: DictationMode.askScreen.rawValue, durationSeconds: duration)
        let entry = DictationHistoryEntry(
            text: finalText,
            rawTranscript: questionCleaned,
            style: settings.style,
            level: settings.level,
            durationSeconds: duration
        )
        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { return }
            store.appendHistory(entry)
            self.statsStore?.recordDictation(
                entryID: entry.entryID,
                words: TranscriptionStatsStore.wordCount(finalText),
                durationSeconds: duration,
                appBundleID: targetApp?.bundleID,
                appDisplayName: targetApp?.displayName,
                at: entry.createdAt
            )
            self.touchActivity()
            self.maybeUnloadImmediately(reason: "ask-screen complete")
        }
    }

    private func ensureEngine(for id: MeetingTranscriptionEngine) -> MeetingTranscriptionEngineProtocol {
        if let engine, engineID == id { return engine }
        let instance = transcriptionService.engine(for: id)
        if let parakeet = instance as? ParakeetTranscriptionEngine {
            // Shorter window than meetings: dictation wants snappy word-level
            // feel, even at a small accuracy cost at sentence boundaries.
            parakeet.streamingWindowSeconds = 1.2
        }
        engine = instance
        engineID = id
        return instance
    }

    // MARK: - Live polish setup

    /// Live polish keeps Qwen (~2.4 GB) resident *while* the ~0.7 GB ASR
    /// helper streams. On 8 GB unified memory that means swap and stuttering
    /// captions, so those machines route to the Apple Intelligence polisher
    /// instead (see `PolishProvider`).
    nonisolated static var hasLivePolishMemoryHeadroom: Bool {
        ProcessInfo.processInfo.physicalMemory > 8 * 1_073_741_824
    }

    private func setUpLivePolisher(
        settings: DictationSettings,
        speechEngine: MeetingTranscriptionEngine,
        styleEngine: DictationStyleEngine
    ) {
        livePolisher = nil
        livePolishProvider = nil
        currentLiveRaw = ""
        currentLiveCommitted = ""
        // Only the polish/compose flows paste the transcript; actions and
        // ask-screen use it as a command/question, so live polish would just
        // burn the model. Level `.none` means "don't rewrite wording" — the
        // list/paragraph toggles alone are final-pass work.
        let wantsLivePolish = settings.livePolishEnabled
            && settings.postProcessEnabled
            && settings.level != .none
            && speechEngine.supportsNativeStreaming
            && (currentMode == .polish || currentMode == .compose)
        switch settings.livePolishEngine {
        case .automatic:
            if Self.hasLivePolishMemoryHeadroom {
                livePolishProvider = .qwen
            } else if AppleIntelligencePolisher.isAvailable {
                livePolishProvider = .appleIntelligence
            }
        case .qwen:
            // Explicit user override — honored even on 8 GB Macs, where the
            // memory gate would otherwise pick Apple Intelligence or nothing.
            livePolishProvider = .qwen
        case .appleIntelligence:
            livePolishProvider = AppleIntelligencePolisher.isAvailable ? .appleIntelligence : nil
        }
        guard wantsLivePolish, let provider = livePolishProvider else { return }

        // Mirrors steps 5–7 of the final pipeline (vocab → pre-clean →
        // filler cleanup) so a live-polished prefix is byte-equal to what
        // the final pass would feed the model for the same raw text — the
        // exact-match reuse in runSession depends on this.
        let prepare: @MainActor (String) -> String = { [weak self] rawPrefix in
            guard let self else { return rawPrefix }
            let withVocab = VocabularyMatcher.apply(rawPrefix, weighted: self.sessionWeightedTerms)
            let withPunct = SmartFormatter.applyPreClean(withVocab, settings: settings)
            return TranscriptCleaner.clean(withPunct)
        }
        let style = settings.style
        let level = settings.level
        // List/paragraph blocks are global document structure — they belong
        // to the final pass over the full transcript, never to a live prefix.
        let polishChunk: @MainActor (String) async -> String
        switch provider {
        case .qwen:
            polishChunk = { input in
                await styleEngine.process(
                    rawTranscript: input,
                    style: style,
                    level: level,
                    formatLists: false,
                    formatParagraphs: false,
                    timeoutSeconds: 2
                )
            }
        case .appleIntelligence:
            polishChunk = { input in
                let prompt = DictationStyleEngine.makePrompt(
                    style: style,
                    level: level,
                    formatLists: false,
                    formatParagraphs: false,
                    screenContextTerms: [],
                    transcript: input
                )
                guard let output = await AppleIntelligencePolisher.polish(prompt: prompt, timeoutSeconds: 2) else {
                    return input
                }
                let cleaned = DictationStyleEngine.cleanOutput(output, original: input)
                return DictationStyleEngine.validatedOutput(cleaned, original: input)
            }
        }
        // Warm Qwen now, while the user is still speaking — otherwise the
        // first pass eats the disk→memory load (up to ~8s cold) and the
        // session can end before a single heal lands.
        if provider == .qwen, let cache = store?.qwenCacheURL {
            Task { try? await QwenLocalLLM.shared.ensureLoadedFromCache(cacheDirectory: cache) }
        }
        let id = sessionID
        let polisher = LiveDictationPolisher(prepare: prepare, polishChunk: polishChunk)
        polisher.onUpdate = { [weak self] in
            guard let self, self.sessionID == id, case .listening = self.phase else { return }
            guard let state = self.livePolisher?.compose(cumulativeRaw: self.currentLiveRaw, committedRaw: self.currentLiveCommitted) else { return }
            self.publishLiveCaption(state, force: true, skipCleanup: true)
        }
        livePolisher = polisher
        logger.info("Live polish enabled — provider=\(provider == .qwen ? "qwen" : "appleIntelligence")")
    }

    // MARK: - Helpers

    private func publishLiveCaption(
        _ raw: LiveCaptionComposer.State,
        force: Bool = false,
        skipCleanup: Bool = false
    ) {
        let now = CACurrentMediaTime()
        if !force, now - lastCaptionPublishAt < 0.08 {
            // Trailing-edge flush. The ASR helper only emits when the text
            // changes, so a debounce-dropped chunk is gone until the user
            // says another word — the caption visibly lags one word behind
            // speech ("butter" missing until the next word). Re-publish the
            // dropped state once the debounce window passes.
            pendingCaptionFlushTask?.cancel()
            pendingCaptionFlushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard let self, !Task.isCancelled else { return }
                guard case .listening = self.phase else { return }
                self.publishLiveCaption(raw, force: true, skipCleanup: skipCleanup)
            }
            return
        }
        pendingCaptionFlushTask?.cancel()
        pendingCaptionFlushTask = nil
        let published = skipCleanup ? raw : LiveCaptionComposer.publishableLiveState(from: raw)
        guard published.text != liveTranscript
            || published.stableWordCount != liveTranscriptStableWordCount
        else { return }
        lastCaptionPublishAt = now
        liveTranscript = published.text
        liveTranscriptStableWordCount = published.stableWordCount
    }

    /// Rewriting-phase caption: replace the raw transcript with the polish as
    /// it generates. Every word renders sharp — this is output text, not
    /// tentative ASR, so no provisional (blurred) tail.
    private func publishPolishPreview(_ text: String, force: Bool = false) {
        let now = CACurrentMediaTime()
        if !force, now - lastCaptionPublishAt < 0.15 { return }
        guard force || text != liveTranscript else { return }
        lastCaptionPublishAt = now
        liveTranscript = text
        liveTranscriptStableWordCount = LiveCaptionComposer.wordCount(text)
    }

    private func fail(reason: String) {
        sessionTask?.cancel()
        finalizationTimeoutTask?.cancel()
        audio.stop(immediately: true)
        meterTask?.cancel()
        meterTask = nil
        isPreparing = false
        level = 0
        screenContextTask?.cancel()
        askScreenCaptureTask?.cancel()
        pendingCaptionFlushTask?.cancel()
        livePolisher?.cancel()
        phase = .failed(reason: reason)
        Task { [weak self] in await self?.ducker.stopDucking() }
    }

    private func resetToIdle() {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        pasteTargetTask?.cancel()
        pasteTargetTask = nil
        sessionTargetApp = nil
        sessionTargetPID = nil
        sessionID = nil
        audio.stop(immediately: true)
        meterTask?.cancel()
        meterTask = nil
        isPreparing = false
        screenContextTask?.cancel()
        screenContextTask = nil
        askScreenCaptureTask?.cancel()
        askScreenCaptureTask = nil
        sessionTask = nil
        sessionStartedAt = nil
        livePolisher?.cancel()
        livePolisher = nil
        livePolishProvider = nil
        currentLiveRaw = ""
        currentLiveCommitted = ""
        pendingCaptionFlushTask?.cancel()
        pendingCaptionFlushTask = nil
        liveTranscript = ""
        liveTranscriptStableWordCount = 0
        liveScreenContextTerms = []
        sessionWeightedTerms = []
        currentMode = .polish
        phase = .idle
        level = 0
        // Belt-and-suspenders: if any path got us here without stopDucking
        // already running (rare error paths, empty-audio early return, etc.),
        // restore other audio now.
        Task { [weak self] in await self?.ducker.stopDucking() }
    }

    // MARK: - Idle unload (memory hygiene)

    /// Reset the idle timer to "now". Called every time the user touches
    /// dictation (session start, transcription complete) and on every tick
    /// of the watcher while a session is active — so a long recording can
    /// never cause an unload mid-sentence.
    private func touchActivity() {
        lastActivityAt = Date()
    }

    /// Start the 10-second watcher if it isn't already running. Skipped
    /// entirely when the user picked `.never` or `.immediately` — those
    /// modes don't use the timer.
    private func startIdleWatcherIfNeeded() {
        guard idleWatcherTask == nil else { return }
        let mode = store?.settings.engineIdleUnload ?? .min5
        guard mode.idleSeconds != nil else { return }

        idleWatcherTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard let self else { return }
                await MainActor.run { self.idleWatcherTick() }
            }
        }
    }

    /// One tick of the idle watcher. Decides whether to unload, refresh the
    /// timer, or shut the watcher down because no engines are loaded.
    private func idleWatcherTick() {
        // Nothing to release — stop ticking until the next dictation
        // boots an engine.
        if engine == nil, !QwenLocalLLM.shared.isLoaded {
            idleWatcherTask?.cancel()
            idleWatcherTask = nil
            return
        }

        // While a dictation is in progress, refresh the timestamp instead
        // of evaluating — same trick Handy uses to guarantee we never
        // unload mid-recording.
        if isActive {
            touchActivity()
            return
        }

        let mode = store?.settings.engineIdleUnload ?? .min5
        guard let limit = mode.idleSeconds else {
            // User flipped to .never or .immediately mid-session — stop the
            // watcher. (`.immediately` is driven by `maybeUnloadImmediately`
            // and doesn't need the timer.)
            idleWatcherTask?.cancel()
            idleWatcherTask = nil
            return
        }

        let idleFor = Date().timeIntervalSince(lastActivityAt)
        if idleFor >= limit {
            logger.info("Engines idle for \(Int(idleFor))s ≥ \(Int(limit))s — releasing")
            unloadEngines()
            idleWatcherTask?.cancel()
            idleWatcherTask = nil
        }
    }

    /// Hot path for the "after every dictation" mode. Called from the
    /// success path of `runSession`. Skipped silently when the user picked
    /// any other mode.
    private func maybeUnloadImmediately(reason: String) {
        let mode = store?.settings.engineIdleUnload ?? .min5
        guard mode == .immediately else { return }
        logger.info("Engine unload (immediately) after \(reason)")
        unloadEngines()
    }

    /// Release Parakeet/Whisper AND Qwen. Setting the speech engine to
    /// `nil` lets Swift's ARC drop FluidAudio's `AsrManager` + cached
    /// models; Qwen has its own guarded `unload()` that shuts down llama.cpp's
    /// backend cleanly. Safe to call when nothing is loaded.
    private func unloadEngines() {
        if engine != nil {
            engine = nil
            engineID = nil
        }
        if QwenLocalLLM.shared.isLoaded {
            QwenLocalLLM.shared.unload()
        }
    }
}
