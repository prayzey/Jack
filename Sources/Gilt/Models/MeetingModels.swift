import Foundation

// MARK: - Meeting language

/// A user-selectable meeting language. Drives which speech-to-text engine the app
/// routes to, plus the localized UI affordances around capture.
enum MeetingLanguage: String, Codable, CaseIterable, Identifiable {
    case auto
    case english = "en"
    case spanish = "es"
    case german = "de"
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return L10n.string("meeting.language.auto", default: "Auto-detect")
        case .english: return L10n.string("meeting.language.english", default: "English")
        case .spanish: return L10n.string("meeting.language.spanish", default: "Spanish")
        case .german: return L10n.string("meeting.language.german", default: "German")
        case .mixed: return L10n.string("meeting.language.mixed", default: "Mixed / Other")
        }
    }

    var flagEmoji: String {
        switch self {
        case .auto: return "🌐"
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        case .german: return "🇩🇪"
        case .mixed: return "🌐"
        }
    }

    var bcpTag: String {
        switch self {
        case .auto: return "und"
        case .english: return "en"
        case .spanish: return "es"
        case .german: return "de"
        case .mixed: return "und"
        }
    }

    /// Brief explanation for the language picker. Tells the user which engine
    /// each choice routes to so the trade-off (speed vs. multilingual coverage)
    /// is explicit rather than buried in code.
    var captureSubtitle: String {
        switch self {
        case .auto:
            return L10n.string("meeting.language.auto.subtitle", default: "Whisper - handles any language")
        case .english:
            return L10n.string("meeting.language.english.subtitle", default: "Parakeet - fastest, English only")
        case .spanish, .german, .mixed:
            return L10n.string("meeting.language.other.subtitle", default: "Whisper multilingual")
        }
    }
}

// MARK: - Transcription engine

/// Identifier for the speech-to-text engine that should be used for a meeting.
/// The selection is derived from the user's chosen `MeetingLanguage` plus their
/// preferred quality tier in settings.
enum MeetingTranscriptionEngine: String, Codable, CaseIterable, Identifiable {
    case parakeetFlash = "parakeet-realtime-eou-120m-v1"
    case parakeetV2 = "parakeet-tdt-0.6b-v2"
    case parakeetUnifiedStream = "parakeet-unified-en-0.6b"
    case whisperSmallMultilingual = "whisper-small-multilingual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeetFlash, .parakeetV2: return "English speech model"
        case .parakeetUnifiedStream: return "English streaming model (beta)"
        case .whisperSmallMultilingual: return "Multilingual speech model"
        }
    }

    /// The dictation engine. Dictation is single-model: the NVIDIA unified
    /// streaming model. (Meetings keep their own engine selection.)
    static let dictationEngine: MeetingTranscriptionEngine = .parakeetUnifiedStream

    /// Engines shown in Settings → Dictate → Advanced.
    static let dictationEngines: [MeetingTranscriptionEngine] = [.parakeetUnifiedStream]

    /// Engines listed in the Meetings model panel.
    static let meetingEngines: [MeetingTranscriptionEngine] = [.parakeetV2, .whisperSmallMultilingual]

    /// Approximate on-disk size of the model file, used to drive download UI copy.
    var approximateDownloadSizeBytes: Int64 {
        switch self {
        case .parakeetFlash: return 250_000_000
        case .parakeetV2: return 650_000_000
        case .parakeetUnifiedStream: return 731_000_000
        case .whisperSmallMultilingual: return 488_000_000
        }
    }

    /// File name written into the per-engine model directory once download succeeds.
    var modelFileName: String {
        switch self {
        case .parakeetFlash: return "streaming_encoder.mlmodelc"
        case .parakeetV2: return "parakeet-tdt-0.6b-v2.mlx"
        case .parakeetUnifiedStream: return "parakeet-unified-en-0.6b-Q8_0.gguf"
        case .whisperSmallMultilingual: return "ggml-small.bin"
        }
    }

    /// Direct download URL for engines whose model is a single file we fetch
    /// ourselves (no library-managed cache). Nil for library-managed engines.
    var directDownloadURL: URL? {
        switch self {
        case .parakeetUnifiedStream:
            return URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/main/parakeet-unified-en-0.6b-Q8_0.gguf")
        case .parakeetFlash, .parakeetV2, .whisperSmallMultilingual:
            return nil
        }
    }

    /// Maps legacy or non-dictation selections to a supported dictation engine.
    static func normalizedDictationEngine(_ engine: MeetingTranscriptionEngine) -> MeetingTranscriptionEngine {
        dictationEngines.contains(engine) ? engine : dictationEngine
    }
}

// MARK: - Summarization engine

enum MeetingSummarizationEngine: String, Codable, CaseIterable, Identifiable {
    case qwen35_4b_q4 = "qwen3.5-4b-q4"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen35_4b_q4: return "Qwen 3.5 4B (Q4)"
        }
    }

    var approximateDownloadSizeBytes: Int64 {
        switch self {
        case .qwen35_4b_q4: return 2_400_000_000
        }
    }

    var modelFolderName: String {
        switch self {
        case .qwen35_4b_q4: return "qwen3.5-4b-q4"
        }
    }
}

/// Which engine actually writes meeting recaps, action items, and Ask answers.
/// The user's preference (`AppSettings.aiMeetingPreferAppleModel`) is a wish;
/// Apple Intelligence availability decides whether it can be honored. Keeping
/// this resolution in one place means the models sheet and the summarization
/// pipeline can never disagree about which engine is in use.
enum MeetingSummarizationChoice: Equatable {
    case appleIntelligence
    case localQwen

    static func effective(preferApple: Bool, appleUsable: Bool) -> MeetingSummarizationChoice {
        (preferApple && appleUsable) ? .appleIntelligence : .localQwen
    }
}

// MARK: - Model download state

enum MeetingModelDownloadState: Equatable {
    case missing
    case downloading(progress: Double, receivedBytes: Int64)
    case ready
    case failed(reason: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

}

// MARK: - Meeting session

/// Lifecycle state for a meeting session. Persisted so the dashboard can show
/// in-flight sessions even if the app is relaunched.
enum MeetingSessionState: String, Codable {
    case draft        // Created but never recorded
    case recording    // Currently capturing audio
    case paused       // Recording paused
    case processing   // Recording finished, models still working through chunks
    case ready        // Transcript + summary available
    case failed       // Capture or processing failed
}

/// Source of audio for a meeting. The first version is mic-only; system audio
/// arrives later and the enum gives us a place to grow into.
enum MeetingAudioSource: String, Codable, CaseIterable, Identifiable {
    case microphone
    case systemAudio
    case microphonePlusSystemAudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone:
            return L10n.string("meeting.audioSource.mic", default: "Microphone")
        case .systemAudio:
            return L10n.string("meeting.audioSource.system", default: "System Audio")
        case .microphonePlusSystemAudio:
            return L10n.string("meeting.audioSource.both", default: "Mic + System Audio")
        }
    }

    var requiresMicrophone: Bool {
        switch self {
        case .microphone, .microphonePlusSystemAudio:
            return true
        case .systemAudio:
            return false
        }
    }

    var requiresSystemAudio: Bool {
        switch self {
        case .systemAudio, .microphonePlusSystemAudio:
            return true
        case .microphone:
            return false
        }
    }

    var captureSubtitle: String {
        switch self {
        case .microphone:
            return L10n.string("meeting.audioSource.mic.subtitle", default: "From your mic")
        case .systemAudio:
            return L10n.string("meeting.audioSource.system.subtitle", default: "Apps and calls")
        case .microphonePlusSystemAudio:
            return L10n.string("meeting.audioSource.both.subtitle", default: "Your voice + apps")
        }
    }
}

struct MeetingSession: Codable, Identifiable, Equatable {
    var meetingID: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var durationSeconds: Double
    var language: MeetingLanguage
    var transcriptionEngine: MeetingTranscriptionEngine
    var audioSource: MeetingAudioSource
    var state: MeetingSessionState
    /// AI-generated questions the user can click in the Ask tab. Refreshed
    /// every ~5 minutes during a meeting so they stay relevant to whatever
    /// has actually been said recently. Empty until the first generation
    /// fires (we keep a hardcoded fallback list in the view).
    var suggestedQuestions: [String]
    /// When `suggestedQuestions` was last regenerated. Drives the 5-minute
    /// cadence — older than 5 minutes triggers a refresh on the next
    /// transcript chunk.
    var suggestedQuestionsUpdatedAt: Date?
    /// Long-form essay-style recap. Auto-extended every 5 minutes during a
    /// live meeting and freely editable by the user. The model is instructed
    /// never to rewrite this — extensions are pure append, and user edits are
    /// preserved by feeding the current text back as locked context.
    var storyText: String
    /// When `storyText` was last extended by the model. Drives cadence.
    var storyLastExtendedAt: Date?
    /// The index into `transcript` that we last consumed for a story
    /// extension. Next iteration only feeds chunks past this point, keeping
    /// the prompt size flat as the meeting grows.
    var storyLastExtendedChunkCount: Int

    init(
        meetingID: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSeconds: Double = 0,
        language: MeetingLanguage = .auto,
        transcriptionEngine: MeetingTranscriptionEngine = .whisperSmallMultilingual,
        audioSource: MeetingAudioSource = .microphone,
        state: MeetingSessionState = .draft,
        suggestedQuestions: [String] = [],
        suggestedQuestionsUpdatedAt: Date? = nil,
        storyText: String = "",
        storyLastExtendedAt: Date? = nil,
        storyLastExtendedChunkCount: Int = 0
    ) {
        self.meetingID = meetingID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.language = language
        self.transcriptionEngine = transcriptionEngine
        self.audioSource = audioSource
        self.state = state
        self.suggestedQuestions = suggestedQuestions
        self.suggestedQuestionsUpdatedAt = suggestedQuestionsUpdatedAt
        self.storyText = storyText
        self.storyLastExtendedAt = storyLastExtendedAt
        self.storyLastExtendedChunkCount = storyLastExtendedChunkCount
    }

    var id: UUID { meetingID }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    // Custom decode so meeting.json files written before the Story tab existed
    // still load (storyText et al. fall back to defaults).
    private enum CodingKeys: String, CodingKey {
        case meetingID, title, createdAt, updatedAt, startedAt, endedAt
        case durationSeconds, language, transcriptionEngine, audioSource
        case state
        case suggestedQuestions, suggestedQuestionsUpdatedAt
        case storyText, storyLastExtendedAt, storyLastExtendedChunkCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetingID = try c.decode(UUID.self, forKey: .meetingID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        language = try c.decodeIfPresent(MeetingLanguage.self, forKey: .language) ?? .auto
        transcriptionEngine = try c.decodeIfPresent(MeetingTranscriptionEngine.self, forKey: .transcriptionEngine) ?? .whisperSmallMultilingual
        audioSource = try c.decodeIfPresent(MeetingAudioSource.self, forKey: .audioSource) ?? .microphone
        state = try c.decodeIfPresent(MeetingSessionState.self, forKey: .state) ?? .draft
        suggestedQuestions = try c.decodeIfPresent([String].self, forKey: .suggestedQuestions) ?? []
        suggestedQuestionsUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .suggestedQuestionsUpdatedAt)
        storyText = try c.decodeIfPresent(String.self, forKey: .storyText) ?? ""
        storyLastExtendedAt = try c.decodeIfPresent(Date.self, forKey: .storyLastExtendedAt)
        storyLastExtendedChunkCount = try c.decodeIfPresent(Int.self, forKey: .storyLastExtendedChunkCount) ?? 0
    }
}

// MARK: - Transcript

/// A single segment of transcript. We store these as line-delimited JSON
/// (`transcript.jsonl`) so writes during long meetings can append cheaply.
struct MeetingTranscriptChunk: Codable, Identifiable, Equatable {
    var chunkID: UUID
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var text: String
    /// Engine that produced this chunk, useful for mixed-language meetings.
    var engineRaw: String

    init(
        chunkID: UUID = UUID(),
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        text: String,
        engineRaw: String
    ) {
        self.chunkID = chunkID
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.text = text
        self.engineRaw = engineRaw
    }

    var id: UUID { chunkID }

    var formattedTimestamp: String {
        Self.formatTimestamp(startTimeSeconds)
    }

    static func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hh = total / 3600
        let mm = (total % 3600) / 60
        let ss = total % 60
        if hh > 0 {
            return String(format: "%02d:%02d:%02d", hh, mm, ss)
        }
        return String(format: "%02d:%02d", mm, ss)
    }
}

// MARK: - Summary

struct MeetingActionItem: Codable, Identifiable, Equatable {
    var actionItemID: UUID
    var text: String
    var owner: String?
    var sourceChunkIDs: [UUID]
    var isCompleted: Bool

    init(
        actionItemID: UUID = UUID(),
        text: String,
        owner: String? = nil,
        sourceChunkIDs: [UUID] = [],
        isCompleted: Bool = false
    ) {
        self.actionItemID = actionItemID
        self.text = text
        self.owner = owner
        self.sourceChunkIDs = sourceChunkIDs
        self.isCompleted = isCompleted
    }

    var id: UUID { actionItemID }
}

struct MeetingDecision: Codable, Identifiable, Equatable {
    var decisionID: UUID
    var text: String
    var sourceChunkIDs: [UUID]

    init(
        decisionID: UUID = UUID(),
        text: String,
        sourceChunkIDs: [UUID] = []
    ) {
        self.decisionID = decisionID
        self.text = text
        self.sourceChunkIDs = sourceChunkIDs
    }

    var id: UUID { decisionID }
}

struct MeetingFollowUpQuestion: Codable, Identifiable, Equatable {
    var questionID: UUID
    var text: String
    var sourceChunkIDs: [UUID]

    init(
        questionID: UUID = UUID(),
        text: String,
        sourceChunkIDs: [UUID] = []
    ) {
        self.questionID = questionID
        self.text = text
        self.sourceChunkIDs = sourceChunkIDs
    }

    var id: UUID { questionID }
}

struct MeetingSummary: Codable, Equatable {
    var meetingID: UUID
    var headline: String
    var bullets: [String]
    var decisions: [MeetingDecision]
    var actionItems: [MeetingActionItem]
    var followUpQuestions: [MeetingFollowUpQuestion]
    var rollingNotes: String
    var lastUpdatedAt: Date

    init(
        meetingID: UUID,
        headline: String = "",
        bullets: [String] = [],
        decisions: [MeetingDecision] = [],
        actionItems: [MeetingActionItem] = [],
        followUpQuestions: [MeetingFollowUpQuestion] = [],
        rollingNotes: String = "",
        lastUpdatedAt: Date = Date()
    ) {
        self.meetingID = meetingID
        self.headline = headline
        self.bullets = bullets
        self.decisions = decisions
        self.actionItems = actionItems
        self.followUpQuestions = followUpQuestions
        self.rollingNotes = rollingNotes
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isEmpty: Bool {
        headline.isEmpty
            && bullets.isEmpty
            && decisions.isEmpty
            && actionItems.isEmpty
            && followUpQuestions.isEmpty
            && rollingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Ask the Meeting

struct MeetingAnswerCitation: Codable, Identifiable, Equatable {
    var citationID: UUID
    var chunkID: UUID
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var snippet: String

    init(
        citationID: UUID = UUID(),
        chunkID: UUID,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        snippet: String
    ) {
        self.citationID = citationID
        self.chunkID = chunkID
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.snippet = snippet
    }

    var id: UUID { citationID }

    var formattedRange: String {
        let start = MeetingTranscriptChunk.formatTimestamp(startTimeSeconds)
        let end = MeetingTranscriptChunk.formatTimestamp(endTimeSeconds)
        return "\(start) – \(end)"
    }
}

struct MeetingQuestion: Codable, Identifiable, Equatable {
    var questionID: UUID
    var meetingID: UUID
    var question: String
    var answer: String
    var citations: [MeetingAnswerCitation]
    var askedAt: Date
    var answeredAt: Date?

    init(
        questionID: UUID = UUID(),
        meetingID: UUID,
        question: String,
        answer: String = "",
        citations: [MeetingAnswerCitation] = [],
        askedAt: Date = Date(),
        answeredAt: Date? = nil
    ) {
        self.questionID = questionID
        self.meetingID = meetingID
        self.question = question
        self.answer = answer
        self.citations = citations
        self.askedAt = askedAt
        self.answeredAt = answeredAt
    }

    var id: UUID { questionID }
}

// MARK: - Settings

struct MeetingSettings: Codable, Equatable {
    /// User's preferred default capture language. Surfaces in the new-meeting sheet.
    var defaultLanguage: MeetingLanguage = .auto
    /// Whether finished meetings should be summarized automatically.
    var autoSummarize: Bool = true
    /// Optional preferred mic device unique ID (nil = system default). Shared
    /// shape with `DictationSettings.preferredMicDeviceUID` so both features
    /// pull from the same `AudioInputDeviceManager` device list.
    var preferredMicDeviceUID: String?
    /// Input gain multiplier for meeting mic capture. See the matching field
    /// on `DictationSettings` for the dual-mode semantics — same rules apply.
    var inputGain: Float = 1.0

    init(
        defaultLanguage: MeetingLanguage = .auto,
        autoSummarize: Bool = true,
        preferredMicDeviceUID: String? = nil,
        inputGain: Float = 1.0
    ) {
        self.defaultLanguage = defaultLanguage
        self.autoSummarize = autoSummarize
        self.preferredMicDeviceUID = preferredMicDeviceUID
        self.inputGain = inputGain
    }

    enum CodingKeys: String, CodingKey {
        case defaultLanguage, autoSummarize
        case preferredMicDeviceUID, inputGain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultLanguage = try c.decodeIfPresent(MeetingLanguage.self, forKey: .defaultLanguage) ?? .auto
        self.autoSummarize = try c.decodeIfPresent(Bool.self, forKey: .autoSummarize) ?? true
        self.preferredMicDeviceUID = try c.decodeIfPresent(String.self, forKey: .preferredMicDeviceUID)
        self.inputGain = try c.decodeIfPresent(Float.self, forKey: .inputGain) ?? 1.0
    }
}

// MARK: - Settings helpers

extension MeetingTranscriptionEngine {
    /// Returns the transcription engine that should be used for the given
    /// language. English → Parakeet (faster, more accurate on English).
    /// Everything else → Whisper Small (the only multilingual engine we ship).
    static func recommended(for language: MeetingLanguage) -> MeetingTranscriptionEngine {
        switch language {
        case .english:
            return .parakeetV2
        case .auto, .spanish, .german, .mixed:
            return .whisperSmallMultilingual
        }
    }
}
