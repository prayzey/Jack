import AVFoundation
import Combine
import Foundation
import OSLog

/// Single source of truth for the active meeting. Owns the audio capture
/// service, the transcription engine, and the rolling transcript. Views observe
/// it via `@EnvironmentObject` on the meeting window.
@MainActor
final class MeetingSessionController: ObservableObject {
    /// Top-level lifecycle of the controller. Distinct from
    /// `MeetingAudioCaptureService.CaptureState` because the controller also
    /// owns transcription/summarization status.
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case paused
        case finishing
        case ready
        case failed(reason: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: [MeetingTranscriptChunk] = []
    @Published private(set) var summary: MeetingSummary?
    @Published private(set) var askHistory: [MeetingQuestion] = []
    @Published private(set) var liveLevel: Double = 0
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var currentMeetingID: UUID?
    /// Click-to-ask suggestions surfaced in the Ask tab. Refreshed every
    /// 5 minutes during a meeting based on what's actually been said. Falls
    /// back to a generic list when the AI hasn't generated any yet.
    @Published private(set) var suggestedQuestions: [String] = MeetingQuestionAnsweringService.defaultStarterQuestions
    /// Essay-style recap that backs the Story tab. Auto-extended every five
    /// minutes during a live meeting; freely editable by the user. The
    /// in-memory copy is the source of truth while a meeting is loaded — the
    /// view debounces writes back through `updateStoryText(_:)`.
    @Published private(set) var storyText: String = ""
    /// True while a story extension or regeneration is in flight. Drives the
    /// "writing now" status in the Story tab.
    @Published private(set) var isWritingStory: Bool = false

    /// Cadence at which `regenerateSuggestedQuestionsIfDue` re-fires while
    /// a meeting is live. Exposed for tests.
    static let suggestedQuestionsRefreshInterval: TimeInterval = 5 * 60
    /// Cadence at which `extendStoryIfDue` re-fires while a meeting is live.
    static let storyExtensionInterval: TimeInterval = 5 * 60

    /// When suggestions were last successfully generated for the currently
    /// loaded meeting. `nil` means "never" — the next chunk should trigger.
    private var lastSuggestionsUpdatedAt: Date?
    private var isGeneratingSuggestions = false
    /// When the story was last extended. Drives the 5-minute cadence.
    private var lastStoryExtendedAt: Date?
    /// Index of the last transcript chunk we consumed for a story extension.
    /// Next iteration only feeds chunks past this point.
    private var lastStoryExtendedChunkCount: Int = 0
    private var isExtendingStory = false

    let audio: MeetingAudioCaptureService
    let store: MeetingStore
    let transcriptionService: MeetingTranscriptionService
    let summarizationService: MeetingSummarizationService
    let qaService: MeetingQuestionAnsweringService
    let storyService: MeetingStoryService
    let modelManager: MeetingModelManager

    private var cancellables: Set<AnyCancellable> = []
    private var transcriptionTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "MeetingSession")
    /// Weak hand-off so the meeting domain can post word totals without
    /// pulling ClipboardStore into its dependency graph.
    private weak var statsStore: TranscriptionStatsStore?

    init(store: MeetingStore) {
        self.store = store
        self.audio = MeetingAudioCaptureService()
        let transcriptionService = MeetingTranscriptionService(modelsRoot: store.modelsRoot)
        self.transcriptionService = transcriptionService
        self.summarizationService = MeetingSummarizationService(modelsRoot: store.modelsRoot)
        self.qaService = MeetingQuestionAnsweringService(modelsRoot: store.modelsRoot)
        self.storyService = MeetingStoryService(modelsRoot: store.modelsRoot)
        self.modelManager = MeetingModelManager(
            modelsRoot: store.modelsRoot,
            transcriptionService: transcriptionService
        )
        bindAudio()
    }

    func attach(statsStore: TranscriptionStatsStore) {
        self.statsStore = statsStore
    }

    // MARK: - Public lifecycle

    /// Switches the controller to a specific meeting, loading transcript +
    /// summary from disk so the UI is always rendering the persisted state.
    func selectMeeting(_ meetingID: UUID) {
        if currentMeetingID == meetingID { return }
        currentMeetingID = meetingID
        transcript = store.loadTranscript(for: meetingID)
        summary = store.loadSummary(for: meetingID)
        askHistory = store.loadAskHistory(for: meetingID)
        let session = store.session(for: meetingID)
        let persisted = session?.suggestedQuestions ?? []
        suggestedQuestions = persisted.isEmpty
            ? MeetingQuestionAnsweringService.defaultStarterQuestions
            : persisted
        lastSuggestionsUpdatedAt = session?.suggestedQuestionsUpdatedAt
        storyText = session?.storyText ?? ""
        lastStoryExtendedAt = session?.storyLastExtendedAt
        lastStoryExtendedChunkCount = session?.storyLastExtendedChunkCount ?? 0
        isWritingStory = false
        phase = (transcript.isEmpty && summary == nil) ? .idle : .ready
    }

    func clearSelection() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        currentMeetingID = nil
        transcript = []
        summary = nil
        askHistory = []
        suggestedQuestions = MeetingQuestionAnsweringService.defaultStarterQuestions
        lastSuggestionsUpdatedAt = nil
        storyText = ""
        lastStoryExtendedAt = nil
        lastStoryExtendedChunkCount = 0
        isWritingStory = false
        phase = .idle
    }

    func startRecording(for session: MeetingSession) async {
        currentMeetingID = session.meetingID
        transcript = store.loadTranscript(for: session.meetingID)
        summary = store.loadSummary(for: session.meetingID)
        askHistory = store.loadAskHistory(for: session.meetingID)
        phase = .preparing

        let audioURL = store.audioURL(for: session.meetingID)
        do {
            var updated = session
            updated.state = .recording
            updated.startedAt = Date()
            store.save(session: updated)

            // Capture starts before model warm-up so the user immediately sees
            // the live recording surface. The AsyncStream buffers audio while
            // Parakeet/Whisper finishes loading.
            try await audio.start(
                writingTo: audioURL,
                source: session.audioSource,
                preferredDeviceUID: store.settings.preferredMicDeviceUID,
                requestedGain: store.settings.inputGain
            )
            phase = .recording

            let engine = transcriptionService.engine(for: session.transcriptionEngine)
            try? await engine.warmUp()
            beginStreamingTranscription(engine: engine, session: updated)
        } catch {
            var failed = session
            failed.state = .failed
            failed.updatedAt = Date()
            store.save(session: failed)
            logger.error("Meeting start failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(reason: error.localizedDescription)
        }
    }

    func pause() {
        audio.pause()
        phase = .paused
        if let id = currentMeetingID, var session = store.session(for: id) {
            session.state = .paused
            store.save(session: session)
        }
    }

    func resume() {
        Task { @MainActor in
            do {
                try await audio.resume()
                phase = .recording
                if let id = currentMeetingID, var session = store.session(for: id) {
                    session.state = .recording
                    store.save(session: session)
                }
            } catch {
                phase = .failed(reason: error.localizedDescription)
            }
        }
    }

    func stopAndProcess() async {
        guard let meetingID = currentMeetingID else { return }
        phase = .finishing
        audio.stop()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        var session = store.session(for: meetingID) ?? MeetingSession(meetingID: meetingID, language: .english)
        session.endedAt = Date()
        if let startedAt = session.startedAt {
            session.durationSeconds = Date().timeIntervalSince(startedAt)
        }
        session.state = .processing
        store.save(session: session)

        // Re-transcribe from file for a clean final transcript (the streaming
        // pass is fast but coarser).
        do {
            let engine = transcriptionService.engine(for: session.transcriptionEngine)
            let audioURL = store.audioURL(for: meetingID)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                let finalChunks = try await engine.transcribeFile(at: audioURL)
                if !finalChunks.isEmpty {
                    transcript = finalChunks
                    store.replaceTranscript(finalChunks, for: meetingID)
                }
            }

            if store.settings.autoSummarize {
                summary = try await summarizationService.summarize(
                    transcript: transcript,
                    previousSummary: summary,
                    meetingID: meetingID,
                    language: session.language
                )
                if let summary {
                    store.saveSummary(summary, for: meetingID)
                }
            }

            session.state = .ready
            store.save(session: session)
            phase = .ready

            // Record lifetime stats now that the final transcript is settled.
            // `recordMeeting` dedupes by meeting ID, so a re-processed meeting
            // (e.g. user kicks off a re-transcribe) doesn't double-count.
            let totalWords = transcript.reduce(0) { acc, chunk in
                acc + TranscriptionStatsStore.wordCount(chunk.text)
            }
            statsStore?.recordMeeting(
                meetingID: session.meetingID,
                words: totalWords,
                durationSeconds: session.durationSeconds,
                at: session.endedAt ?? Date()
            )
            Analytics.meetingCompleted(
                engine: session.transcriptionEngine.rawValue,
                durationSeconds: session.durationSeconds,
                words: totalWords
            )
        } catch {
            session.state = .failed
            store.save(session: session)
            phase = .failed(reason: error.localizedDescription)
        }
    }

    func askQuestion(_ question: String) async {
        guard let meetingID = currentMeetingID else { return }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let session = store.session(for: meetingID)
        let language = session?.language ?? .auto
        let rollingNotes = summary?.rollingNotes ?? ""
        // Hand the previous question through so the QA service can treat
        // "more details" / "tell me more" as expansions of the prior context
        // rather than fresh keyword searches that miss the thread.
        let previousQuestion = askHistory.last
        do {
            let answer = try await qaService.answer(
                question: question,
                in: transcript,
                rollingNotes: rollingNotes,
                meetingID: meetingID,
                language: language,
                previousQuestion: previousQuestion
            )
            askHistory.append(answer)
            store.saveAskHistory(askHistory, for: meetingID)
        } catch {
            let fallback = MeetingQuestion(
                meetingID: meetingID,
                question: question,
                answer: error.localizedDescription,
                answeredAt: Date()
            )
            askHistory.append(fallback)
            store.saveAskHistory(askHistory, for: meetingID)
        }
    }

    /// Re-asks Qwen for fresh suggested questions if enough time has passed
    /// since the last refresh and the transcript has grown. Safe to call on
    /// every transcript chunk — it short-circuits when there's nothing to do.
    func regenerateSuggestedQuestionsIfDue(force: Bool = false) {
        guard let meetingID = currentMeetingID else { return }
        guard !isGeneratingSuggestions else { return }
        guard !transcript.isEmpty else { return }

        if !force, !Self.shouldRegenerate(
            lastUpdate: lastSuggestionsUpdatedAt,
            now: Date(),
            interval: Self.suggestedQuestionsRefreshInterval
        ) {
            return
        }

        isGeneratingSuggestions = true
        let snapshot = transcript
        let language = store.session(for: meetingID)?.language ?? .auto

        Task { [weak self] in
            guard let self else { return }
            let questions = await self.qaService.generateSuggestedQuestions(
                from: snapshot,
                language: language
            )
            await MainActor.run {
                self.applySuggestedQuestions(questions, for: meetingID)
                self.isGeneratingSuggestions = false
            }
        }
    }

    nonisolated static func shouldRegenerate(
        lastUpdate: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let lastUpdate else { return true }
        return now.timeIntervalSince(lastUpdate) >= interval
    }

    private func applySuggestedQuestions(_ questions: [String], for meetingID: UUID) {
        guard currentMeetingID == meetingID else { return }
        let cleaned = questions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        suggestedQuestions = cleaned
        lastSuggestionsUpdatedAt = Date()
        if var session = store.session(for: meetingID) {
            session.suggestedQuestions = cleaned
            session.suggestedQuestionsUpdatedAt = lastSuggestionsUpdatedAt
            store.save(session: session)
        }
    }

    // MARK: - Story

    /// Persists a user edit from the Story tab. Called by the view after a
    /// debounce window so we don't write on every keystroke.
    func updateStoryText(_ text: String) {
        guard let meetingID = currentMeetingID else { return }
        storyText = text
        if var session = store.session(for: meetingID) {
            session.storyText = text
            store.save(session: session)
        }
    }

    /// Append-only iteration. Called from the live transcription loop on every
    /// new chunk; short-circuits unless five minutes have elapsed since the
    /// last extension and at least one new chunk has landed since then.
    func extendStoryIfDue() {
        guard let meetingID = currentMeetingID else { return }
        guard !isExtendingStory else { return }
        // Only extend during live capture or while finishing — once a meeting
        // is fully saved the user drives this with the Regenerate button.
        switch phase {
        case .recording, .paused, .preparing, .finishing: break
        default: return
        }

        let totalChunks = transcript.count
        guard totalChunks > lastStoryExtendedChunkCount else { return }
        if let lastAt = lastStoryExtendedAt,
           Date().timeIntervalSince(lastAt) < Self.storyExtensionInterval {
            return
        }

        let newChunks = Array(transcript[lastStoryExtendedChunkCount..<totalChunks])
        guard !newChunks.isEmpty else { return }

        let language = store.session(for: meetingID)?.language ?? .auto
        let existing = storyText
        isExtendingStory = true
        isWritingStory = true

        Task { [weak self, storyService] in
            guard let self else { return }
            let newParagraph = await storyService.extend(
                existingStory: existing,
                newChunks: newChunks,
                language: language
            )
            await MainActor.run {
                self.applyStoryExtension(
                    newParagraph,
                    consumedThroughChunkCount: totalChunks,
                    for: meetingID
                )
            }
        }
    }

    private func applyStoryExtension(
        _ newParagraph: String?,
        consumedThroughChunkCount: Int,
        for meetingID: UUID
    ) {
        defer {
            isExtendingStory = false
            isWritingStory = false
        }
        // The user may have switched meetings while the model was thinking.
        guard currentMeetingID == meetingID else { return }

        // Always advance the cursor, even on a NO_EXTENSION result, so we
        // don't re-feed the same silence to the model every chunk.
        lastStoryExtendedChunkCount = consumedThroughChunkCount
        lastStoryExtendedAt = Date()

        if let newParagraph, !newParagraph.isEmpty {
            let separator = storyText.isEmpty ? "" : "\n\n"
            storyText = storyText + separator + newParagraph
        }

        if var session = store.session(for: meetingID) {
            session.storyText = storyText
            session.storyLastExtendedAt = lastStoryExtendedAt
            session.storyLastExtendedChunkCount = lastStoryExtendedChunkCount
            store.save(session: session)
        }
    }

    /// User-triggered full redraft of the essay. Overwrites whatever's there.
    func regenerateStory() async {
        guard let meetingID = currentMeetingID else { return }
        guard !transcript.isEmpty else { return }
        let session = store.session(for: meetingID)
        let language = session?.language ?? .auto
        let title = session?.displayTitle ?? ""

        isWritingStory = true
        defer { isWritingStory = false }

        let fresh = await storyService.regenerate(
            transcript: transcript,
            meetingTitle: title,
            language: language
        )
        guard let fresh, !fresh.isEmpty else { return }
        guard currentMeetingID == meetingID else { return }

        storyText = fresh
        lastStoryExtendedChunkCount = transcript.count
        lastStoryExtendedAt = Date()
        if var session = store.session(for: meetingID) {
            session.storyText = fresh
            session.storyLastExtendedAt = lastStoryExtendedAt
            session.storyLastExtendedChunkCount = lastStoryExtendedChunkCount
            store.save(session: session)
        }
    }

    func regenerateSummary() async {
        guard let meetingID = currentMeetingID,
              let session = store.session(for: meetingID) else { return }
        do {
            let newSummary = try await summarizationService.summarize(
                transcript: transcript,
                previousSummary: summary,
                meetingID: meetingID,
                language: session.language
            )
            summary = newSummary
            store.saveSummary(newSummary, for: meetingID)
        } catch {
            phase = .failed(reason: error.localizedDescription)
        }
    }

    func deleteMeeting(_ meetingID: UUID) {
        if currentMeetingID == meetingID {
            audio.stop()
            transcriptionTask?.cancel()
            transcriptionTask = nil
            clearSelection()
        }
        store.deleteSession(meetingID)
    }

    // MARK: - Private

    private func bindAudio() {
        audio.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.liveLevel = value }
            .store(in: &cancellables)

        audio.$elapsedSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.elapsedSeconds = value }
            .store(in: &cancellables)
    }

    private func beginStreamingTranscription(
        engine: any MeetingTranscriptionEngineProtocol,
        session: MeetingSession
    ) {
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = engine.transcribeStream(
                from: self.audio.audioBufferStream,
                meetingStartedAt: session.startedAt ?? Date()
            )
            do {
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.transcript.append(chunk)
                        self.store.appendTranscriptChunk(chunk, to: session.meetingID)
                        // Every transcript chunk is an opportunity to refresh
                        // suggested questions and extend the story — both helpers
                        // short-circuit unless 5 minutes have actually passed
                        // since the last refresh.
                        self.regenerateSuggestedQuestionsIfDue()
                        self.extendStoryIfDue()
                    }
                }
            } catch {
                // The engine couldn't start or died mid-session — surface it
                // rather than leaving the meeting silently untranscribed.
                if !Task.isCancelled {
                    await MainActor.run { self.phase = .failed(reason: error.localizedDescription) }
                }
            }
        }
    }
}
