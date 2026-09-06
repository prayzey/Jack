import Carbon.HIToolbox
import Foundation
import SwiftUI

// MARK: - Dictation trigger

/// What kind of input fires the dictation overlay.
///
/// We support three flavors of trigger because dictation is fundamentally a
/// fast, frequent action — users want it bound to whatever feels native to
/// their hands. Combos with modifiers go through `GlobalHotKeyEventTap`; pure
/// modifier press-and-hold and modifier double-tap go through our own
/// `DictationHotkeyMonitor` which listens to `.flagsChanged` events.
enum DictationTriggerKind: String, Codable, CaseIterable, Identifiable {
    /// Hold a single key (or a modifier + key combo) to record; release to stop.
    case pushToTalk = "push-to-talk"
    /// Tap once to start, tap again to stop.
    case toggle
    /// Press a modifier key (Right Option, Fn, etc.) twice quickly to toggle.
    case modifierDoubleTap = "modifier-double-tap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushToTalk: return "Hold to talk"
        case .toggle: return "Tap to start/stop"
        case .modifierDoubleTap: return "Double-tap"
        }
    }

    var subtitle: String {
        switch self {
        case .pushToTalk:
            return "Hold the key while you speak. Release to transcribe."
        case .toggle:
            return "Tap once to start recording. Tap again to stop."
        case .modifierDoubleTap:
            return "Tap the modifier twice quickly to toggle recording."
        }
    }
}

/// A single dictation hotkey binding. Combines key + modifiers + trigger style.
/// `keyCode == 0` with a modifier flag set means "hold this modifier alone."
struct DictationShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var trigger: DictationTriggerKind

    /// Default: hold Right Option to dictate. Single-modifier, easy to reach,
    /// doesn't conflict with system shortcuts on a standard keyboard.
    static let `default` = DictationShortcut(
        keyCode: UInt32(kVK_RightOption),
        modifiers: 0,
        trigger: .pushToTalk
    )

    /// Whether this binding represents a bare modifier press (no other key).
    /// Used by the hotkey monitor to pick `flagsChanged` vs `keyDown` paths.
    var isBareModifier: Bool {
        return modifiers == 0 && DictationKeyNames.isModifierKeyCode(keyCode)
    }

    /// Just the key (or modifier+key combo). The trigger style — hold vs tap
    /// vs double-tap — is conveyed by the segmented picker next to the
    /// recorder field, so duplicating it as a `(toggle)` or `×2` suffix here
    /// is noise.
    var displayString: String {
        let key = DictationKeyNames.displayName(for: keyCode)
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        parts.append(key)
        return parts.joined(separator: " + ")
    }
}

// MARK: - Custom vocabulary

/// How aggressively the vocabulary matcher tries to substitute a custom term
/// back into the transcript. Three rungs so users can dial each term to taste.
///
/// - `.off`: term is parked but ignored. Useful when a term over-corrects and
///   the user wants to disable it without forgetting it.
/// - `.normal`: today's behavior — exact string match plus spelled-out /
///   camelCase / separator-flattened variants. Safe; doesn't touch words the
///   user didn't literally say.
/// - `.strong`: `.normal` plus per-word phonetic matching (Soundex). Catches
///   mishearings like "clawed" → "claude" where Parakeet's acoustic guess is
///   a homophone-ish English word. Can have false positives (e.g. "cloud" →
///   "claude") — that's the trade-off, dial back to `.normal` if it bites.
enum VocabularyStrength: String, Codable, CaseIterable, Identifiable {
    case off
    case normal
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:    return "Off"
        case .normal: return "Normal"
        case .strong: return "Strong"
        }
    }

    var subtitle: String {
        switch self {
        case .off:    return "Disabled. Jack ignores this term."
        case .normal: return "Exact spelling and spelled-out forms (\"a p i\" → \"API\")."
        case .strong: return "Also fixes mishearings that sound similar (\"clawed\" → \"claude\")."
        }
    }
}

/// One user-added vocabulary term plus its per-term strength. Replaces the
/// old flat-`String` storage on `DictationSettings.customVocabulary`. The
/// decoder still accepts the legacy `[String]` shape so existing users don't
/// lose their terms on first launch after upgrading.
struct CustomVocabularyTerm: Codable, Equatable, Hashable, Identifiable {
    var text: String
    var strength: VocabularyStrength

    init(text: String, strength: VocabularyStrength = .strong) {
        self.text = text
        self.strength = strength
    }

    /// Stable identity by canonical text — lets SwiftUI ForEach key on the
    /// term without flicker when the strength changes.
    var id: String { text.lowercased() }
}

// MARK: - Dictation mode

/// What the current dictation session is for.
///
/// `.polish` is the default and unchanged — the user dictates and Jack
/// cleans + pastes the transcript.
///
/// `.askScreen` reuses the same record-transcribe pipeline but treats the
/// transcript as a *question*, captures the frontmost window's full text,
/// and asks the local Qwen model to answer it. The pill renders with a
/// different aura color + an eye glyph so the user can tell at a glance
/// which mode they triggered.
enum DictationMode: String, Codable, Equatable {
    case polish
    case askScreen
    /// Dictation runs the full polish pipeline but, instead of pasting into
    /// the frontmost app, hands the finished text to the open compose window
    /// (via `DictationCoordinator.onComposeText`) which inserts it at the
    /// caret. Lets the user dictate into Jack's own editor and drop copied
    /// links/clips into the middle of what they're saying.
    case compose
    /// The transcript is treated as a spoken command for native Mac apps
    /// (Apple Reminders, Spotify, etc.) instead of text to paste.
    case actions
}

// MARK: - Dictation style + level

/// Two macro "voices" the post-processor can write in. Ported from Openwhisp's
/// Style picker. The level enum below controls how aggressive the edit is.
enum DictationStyle: String, Codable, CaseIterable, Identifiable {
    case conversation
    case developer
    case professional
    case notes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conversation: return "Conversation"
        case .developer:    return "Developer"
        case .professional: return "Professional"
        case .notes:        return "Notes"
        }
    }

    var description: String {
        switch self {
        case .conversation:
            return "Natural conversation style. Perfect for messages, notes, and everyday writing."
        case .developer:
            return "Software developer style. Uses proper engineering terms: APIs, services, modules, refactor."
        case .professional:
            return "Workplace tone. Clear and polite: work email, project updates, stakeholder messages."
        case .notes:
            return "Terse notes for your future self. Fragments allowed. Strips fluff, keeps facts and todos."
        }
    }
}

/// How much the post-processor is allowed to rewrite. None ≈ raw transcript.
/// High ≈ Openwhisp "expand into professional prose."
enum DictationLevel: String, Codable, CaseIterable, Identifiable {
    case none
    case soft
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No filter"
        case .soft: return "Soft"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var tagline: String {
        switch self {
        case .none: return "Minimal touch. Fix typos only."
        case .soft: return "Light grammar and clarity polish."
        case .medium: return "Rewrite for natural, clear prose."
        case .high: return "Professional polish and expansion."
        }
    }

    /// Sample preview text — what a raw transcript would look like after this
    /// level, in the selected voice. Drives the preview cards in Settings.
    func sample(for style: DictationStyle) -> String {
        switch style {
        case .conversation:
            switch self {
            case .none:   return "I went to the store and bought some stuff for the project."
            case .soft:   return "I went to the store and picked up some things for the project."
            case .medium: return "I stopped by the store and picked up supplies for the project."
            case .high:   return "I visited the store to procure the necessary supplies for our project."
            }
        case .developer:
            switch self {
            case .none:   return "We need to fix the API thing so it doesn't break."
            case .soft:   return "We need to fix the API issue so it stops failing."
            case .medium: return "We should refactor the API endpoint to stop returning errors."
            case .high:   return "We need to refactor the API endpoint to handle failure modes gracefully and return structured errors instead of 500s."
            }
        case .professional:
            switch self {
            case .none:   return "I went to the store and bought some stuff for the project."
            case .soft:   return "I went to the store and picked up materials for the project."
            case .medium: return "I stopped by the store to pick up the materials we need for the project."
            case .high:   return "I stopped by the store this afternoon to gather the materials required for the project."
            }
        case .notes:
            switch self {
            case .none:   return "went to the store and bought some stuff for the project"
            case .soft:   return "Store run. Picked up stuff for project."
            case .medium: return "Store run. Project materials picked up."
            case .high:   return "Store run: project materials acquired."
            }
        }
    }

    /// Returns how many of the four "level dots" should be filled when
    /// rendering this level as a swatch.
    var dotCount: Int {
        switch self {
        case .none: return 1
        case .soft: return 2
        case .medium: return 3
        case .high: return 4
        }
    }
}

// MARK: - Dictation overlay phase

/// What the listening pill is doing right now. Drives both the grid animation
/// and the label text. Aligns with Openwhisp's `status.phase`.
enum DictationPhase: Equatable {
    case idle
    case listening
    case transcribing
    case rewriting
    /// Running a parsed voice command (create reminder, Spotify control, etc.).
    case executing
    case pasting
    case done
    case failed(reason: String)
}

// MARK: - Voice actions connectors

/// A native Mac capability the voice-actions mode can drive. Kept as stable
/// string-backed IDs so settings JSON stays readable.
enum VoiceActionConnector: String, Codable, CaseIterable, Identifiable {
    case reminders
    case spotify

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reminders: return "Apple Reminders"
        case .spotify: return "Spotify"
        }
    }

    var subtitle: String {
        switch self {
        case .reminders:
            return "Say “remind me to…” and it appears in Reminders right away."
        case .spotify:
            return "Say “play”, “pause”, or “skip” when Spotify is installed."
        }
    }

    var icon: String {
        switch self {
        case .reminders: return "checklist"
        case .spotify: return "music.note"
        }
    }
}

// MARK: - Dictation settings + history

/// Which model runs the live (while-you-speak) polish passes.
enum LivePolishEngine: String, Codable, CaseIterable, Identifiable {
    /// Qwen when the Mac has memory headroom (>8 GB), otherwise the Apple
    /// Intelligence system model when available, otherwise no live polish.
    case automatic
    /// Always Qwen — the escape hatch for low-memory Macs on macOS below 26
    /// that want live polish anyway and accept the memory pressure.
    case qwen
    /// Always the Apple Intelligence system model; live polish is off when
    /// it's unavailable (macOS below 26, or Apple Intelligence disabled).
    case appleIntelligence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .qwen: return "Qwen"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    var description: String {
        switch self {
        case .automatic:
            return "Picks the best engine for this Mac: Qwen when there's plenty of memory, Apple Intelligence otherwise."
        case .qwen:
            return "Always uses the local Qwen model. On Macs with 8 GB of memory this can slow things down while you dictate."
        case .appleIntelligence:
            return "Uses the built-in Apple Intelligence model. Requires macOS 26 or later with Apple Intelligence turned on."
        }
    }
}

struct DictationSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var shortcut: DictationShortcut = .default
    /// If false, dictation pastes the raw transcript with no LLM pass.
    /// Defaults to false — user explicitly opted into raw at setup.
    var postProcessEnabled: Bool = false
    /// Aqua-style live polish: re-polish completed sentences while the user
    /// is still speaking so the caption visibly heals self-corrections. Only
    /// meaningful when Polish is on and the level rewrites wording. On by
    /// default — the memory gate in `DictationCoordinator` decides whether
    /// Qwen or the Apple Intelligence model (8 GB Macs) actually runs it.
    var livePolishEnabled: Bool = true
    /// Engine preference for live polish. `.automatic` respects the memory
    /// gate; `.qwen` overrides it for users on older macOS who want live
    /// polish regardless.
    var livePolishEngine: LivePolishEngine = .automatic
    var style: DictationStyle = .conversation
    var level: DictationLevel = .soft
    /// Save each dictation as a clip in history so the user can re-grab it
    /// from the Jack window if a paste fails.
    var saveToClipboardHistory: Bool = true
    /// Auto-paste into the frontmost app after transcription.
    var autoPasteIntoActiveApp: Bool = true
    /// Color scheme for the floating dictation pill + caption surface.
    /// `obsidian` is the default — calm dark warm theme that reads on top
    /// of any app. The user can swap to any preset in `DictationPillTheme`
    /// from the Dictate settings tab.
    var pillTheme: DictationPillTheme = .obsidian
    /// When true, the system's output volume is lowered while dictation is
    /// active so background music/videos don't compete with the user's voice.
    /// Off by default — many users dictate in silence already and being
    /// surprised by a sudden volume drop is worse than the small benefit.
    var duckOtherAudio: Bool = false
    /// How aggressively to lower other audio. 0 = no change, 1 = full mute.
    /// 0.6 (60%) is a good default when the toggle is first enabled —
    /// noticeably quieter without killing the audio entirely.
    var duckAmount: Double = 0.6
    /// Vocabulary packs the user has enabled. Each pack contributes a list
    /// of canonical terms the matcher substitutes back into the transcript
    /// when Parakeet has rendered them as spelled-out letters (e.g. "a p i"
    /// → "API") or split words (e.g. "use effect" → "useEffect").
    var enabledVocabPacks: Set<DictationVocabularyPack> = []
    /// User-defined terms that get the same matcher treatment as pack terms.
    /// One canonical spelling per entry — variants are auto-generated. Each
    /// term carries a per-term `VocabularyStrength` so users can dial
    /// individual entries between off / normal / strong (phonetic).
    var customVocabulary: [CustomVocabularyTerm] = []
    /// User-added terms layered on top of each pack's curated list. Keyed by
    /// `DictationVocabularyPack.rawValue` (String keys keep the on-disk JSON
    /// readable — `[Pack: [String]]` would encode as an array of alternating
    /// keys/values). Only consulted when the corresponding pack is enabled.
    var packTermAdditions: [String: [String]] = [:]
    /// User-removed built-in terms per pack. Same string-keyed shape as
    /// `packTermAdditions`. Stored as a *diff* (rather than snapshotting the
    /// whole pack) so future releases can add or fix curated terms without
    /// overwriting the user's edits.
    var packTermRemovals: [String: [String]] = [:]
    /// When on, Qwen receives an extra prompt instruction asking it to
    /// recognize verbal list markers ("number one… number two…", "first…
    /// second…") and emit them as a formatted list. Requires the Qwen
    /// model since it needs intent recognition; silently skipped if Qwen
    /// isn't downloaded.
    var formatLists: Bool = true
    /// When on, Qwen adds paragraph breaks at natural topic shifts in
    /// long dictations. Same Qwen-dependent behavior as `formatLists`.
    var formatParagraphs: Bool = true
    /// Expand spoken punctuation commands ("comma" → ",", "new paragraph"
    /// → "\n\n", "question mark" → "?"). Pure regex — no model needed.
    var formatPunctuationCommands: Bool = true
    /// Curly quotes ("..." → "..."), em dashes (--), apostrophe direction.
    /// Pure character replacement, deterministic.
    var useSmartTypography: Bool = true
    /// Capitalize the first letter of every sentence + standalone "i" → "I".
    /// Compensates for Parakeet's tendency to lowercase pronouns and
    /// post-period sentence starts.
    var capitalizeSentences: Bool = true
    /// Optional preferred mic device unique ID (nil = system default).
    var preferredMicDeviceUID: String?
    /// Input gain multiplier applied to mic audio.
    ///
    /// Dual-mode by design — semantics depend on whether the currently-bound
    /// device exposes settable hardware volume (see
    /// `AudioInputDeviceManager.canSetHardwareGain`):
    ///
    /// - **Hardware-settable device** (most USB mics, audio interfaces):
    ///   `0...1` drives `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`
    ///   directly — same value System Settings would set. Default `1.0`.
    /// - **Hardware-NOT-settable device** (built-in MacBook mic on Apple
    ///   silicon, AirPods, most Bluetooth mics): `1...2` is a software
    ///   multiplier applied in the tap. `1.0` = unmodified, `2.0` = +6 dB.
    ///   Capped at 2.0x because Whisper accuracy drops past that — the
    ///   signal-to-noise ratio gets worse, not better.
    ///
    /// The UI flips between these two ranges based on the bound device's
    /// mode and labels the slider so the user knows which one they're
    /// touching.
    var inputGain: Float = 1.0

    // MARK: - Screen context

    /// Master switch for reading the frontmost window's contents to bias the
    /// transcription. OFF by default — the feature requires Screen Recording
    /// permission (when OCR fallback is enabled) and trades a small latency
    /// hit at session start for materially better accuracy on names, code
    /// symbols, file names, and jargon that happen to be visible on screen.
    var useScreenContext: Bool = false

    /// How aggressively to gather context.
    ///   - `.accessibilityOnly`: walk the AXUIElement tree of the frontmost
    ///     app. No Screen Recording permission needed. Free + fast but fails
    ///     on apps that don't expose AX (some Electron apps, games, fullscreen
    ///     video players).
    ///   - `.accessibilityWithOCRFallback`: try AX first; if it returns too
    ///     few terms, capture the frontmost window via ScreenCaptureKit and
    ///     OCR it with Vision. Needs Screen Recording permission. Recommended.
    ///   - `.ocrOnly`: always OCR. Slowest, but works in apps where AX is
    ///     missing or wrong.
    var screenContextMode: ScreenContextMode = .accessibilityWithOCRFallback

    /// Cap on how many extracted terms get fed to the matcher + LLM. Keeps
    /// the Qwen prompt short and stops the matcher from doing 500 regex
    /// passes on every dictation. 60 fits comfortably in a single LLM
    /// context block while covering everything on a typical screen.
    var screenContextMaxTerms: Int = 60

    /// App bundle IDs to skip entirely — never read context from these. Apps
    /// where reading the screen would be a privacy violation (password
    /// managers, secure browsers) ship as defaults so the user gets a sensible
    /// blocklist out of the box.
    var screenContextExcludedBundleIDs: Set<String> = ScreenContextDefaults.excludedBundleIDs

    /// When the captured text is shorter than this many characters AND we're
    /// in `.accessibilityWithOCRFallback` mode, fall through to OCR. Tuned
    /// for "AX returned something tiny like just the window title."
    var screenContextAXMinimumChars: Int = 80

    // MARK: - Engine idle unload

    /// On-device speech engine for dictation (always the English TDT model).
    var speechEngine: MeetingTranscriptionEngine = .parakeetV2

    /// How long the loaded Parakeet/Whisper/Qwen engines stay in memory after
    /// the last dictation finishes. Inspired by Handy's `model_unload_timeout`:
    /// frees ~1–2 GB of RAM after a quiet stretch, at the cost of a small
    /// re-warm delay on the next press. Default is 5 minutes — the same
    /// sweet-spot Handy ships with.
    var engineIdleUnload: EngineIdleUnload = .min5

    // MARK: - Ask the screen

    /// Master on/off switch for the ask-the-screen feature. Kept separate
    /// from `askScreenShortcut` on purpose: turning the feature off must NOT
    /// erase the key the user picked, so toggling it back on restores their
    /// shortcut instead of snapping back to a default. Off by default so
    /// existing users don't get a surprise second shortcut after upgrading.
    var askScreenEnabled: Bool = false

    /// The hotkey that fires dictation in `.askScreen` mode instead of the
    /// default `.polish` mode. Remembered even while `askScreenEnabled` is
    /// false so the user's choice survives an off/on cycle and app restarts.
    /// nil = the user hasn't picked a key yet. The second event tap is only
    /// installed when the feature is enabled AND a key is bound.
    var askScreenShortcut: DictationShortcut?

    // MARK: - Learn from edits

    /// Master toggle for the "watch what I edit after paste" learning loop.
    /// When on, `CorrectionLearner` watches the focused text field via the
    /// Accessibility API after each polish-mode paste, asks Qwen whether
    /// the user corrected the dictation, and stores accepted corrections
    /// in `CorrectionStore` for future polish runs to draw on.
    ///
    /// Off by default — this is opt-in for privacy reasons. Reading what
    /// the user typed into another app, even briefly and locally, is the
    /// kind of thing users want to choose to enable.
    var learnFromEdits: Bool = false

    // MARK: - Voice actions

    /// Master on/off for voice commands (reminders, Spotify, etc.). Separate
    /// from the bound shortcut so toggling off preserves the user's key.
    var voiceActionsEnabled: Bool = false

    /// Hotkey that fires dictation in `.actions` mode. nil until the user
    /// picks a key — same pattern as `askScreenShortcut`.
    var voiceActionsShortcut: DictationShortcut?

    /// Which native connectors are active. Reminders is on by default when
    /// the feature is enabled; Spotify is opt-in because it needs the app.
    var voiceActionConnectors: Set<VoiceActionConnector> = [.reminders]

    // MARK: - Vocabulary helpers

    /// Effective term list for a single pack with the user's edits applied.
    /// Returns the curated list verbatim when the user hasn't touched the pack.
    func effectiveTerms(for pack: DictationVocabularyPack) -> [String] {
        pack.effectiveTerms(
            additions: packTermAdditions[pack.rawValue] ?? [],
            removals: packTermRemovals[pack.rawValue] ?? []
        )
    }

    /// Flattened term list across every *enabled* pack plus the user's
    /// non-`.off` custom vocabulary, returned as plain strings. Used by any
    /// caller that just wants the canonical list (LLM prompts, history,
    /// debug surfaces). Strength is intentionally not preserved here —
    /// callers that care about per-term strength use
    /// `weightedCustomVocabulary()` instead.
    func allActiveVocabularyTerms() -> [String] {
        let packTerms = enabledVocabPacks.flatMap { effectiveTerms(for: $0) }
        let customStrings = customVocabulary
            .filter { $0.strength != .off }
            .map(\.text)
        return packTerms + customStrings
    }

    /// Just the user's custom vocabulary with per-term strength preserved.
    /// Feeds the weighted matcher path that knows how to do phonetic
    /// substitution for `.strong` terms.
    func weightedCustomVocabulary() -> [CustomVocabularyTerm] {
        customVocabulary.filter { $0.strength != .off }
    }
}

// Codable customization lives in an extension on purpose: an init in the main
// declaration would suppress the compiler-synthesized memberwise initializer,
// and every caller relies on `DictationSettings()` picking up the inline
// property defaults. Synthesized `encode(to:)` still uses this CodingKeys.
extension DictationSettings {
    // Custom decoder — uses `decodeIfPresent` for every key so adding a new
    // field (like `pillTheme`) doesn't drop a user's saved settings. The auto-
    // synthesized decoder would throw on a missing key and wipe everything.
    enum CodingKeys: String, CodingKey {
        case isEnabled, shortcut, postProcessEnabled, livePolishEnabled, livePolishEngine, style, level
        case saveToClipboardHistory, autoPasteIntoActiveApp
        case pillTheme, duckOtherAudio, duckAmount
        case enabledVocabPacks, customVocabulary
        case packTermAdditions, packTermRemovals
        case formatLists, formatParagraphs, formatPunctuationCommands
        case useSmartTypography, capitalizeSentences
        case preferredMicDeviceUID
        case inputGain
        case useScreenContext, screenContextMode, screenContextMaxTerms
        case screenContextExcludedBundleIDs, screenContextAXMinimumChars
        case speechEngine, engineIdleUnload
        case askScreenEnabled, askScreenShortcut
        case learnFromEdits
        case voiceActionsEnabled, voiceActionsShortcut, voiceActionConnectors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.shortcut = try c.decodeIfPresent(DictationShortcut.self, forKey: .shortcut) ?? .default
        self.postProcessEnabled = try c.decodeIfPresent(Bool.self, forKey: .postProcessEnabled) ?? false
        self.livePolishEnabled = try c.decodeIfPresent(Bool.self, forKey: .livePolishEnabled) ?? true
        self.livePolishEngine = try c.decodeIfPresent(LivePolishEngine.self, forKey: .livePolishEngine) ?? .automatic
        self.style = try c.decodeIfPresent(DictationStyle.self, forKey: .style) ?? .conversation
        self.level = try c.decodeIfPresent(DictationLevel.self, forKey: .level) ?? .soft
        self.saveToClipboardHistory = try c.decodeIfPresent(Bool.self, forKey: .saveToClipboardHistory) ?? true
        self.autoPasteIntoActiveApp = try c.decodeIfPresent(Bool.self, forKey: .autoPasteIntoActiveApp) ?? true
        self.pillTheme = try c.decodeIfPresent(DictationPillTheme.self, forKey: .pillTheme) ?? .obsidian
        self.duckOtherAudio = try c.decodeIfPresent(Bool.self, forKey: .duckOtherAudio) ?? false
        self.duckAmount = try c.decodeIfPresent(Double.self, forKey: .duckAmount) ?? 0.6
        self.enabledVocabPacks = try c.decodeIfPresent(Set<DictationVocabularyPack>.self, forKey: .enabledVocabPacks) ?? []
        // customVocabulary: accept either the new [CustomVocabularyTerm]
        // shape or the legacy [String] shape so users upgrading from a
        // build that stored bare strings don't lose their terms. Legacy
        // strings lift to `.strong` — that's the "fixes mishearings"
        // setting the new feature is meant to give them, and it's the
        // most useful default on first encounter.
        if let weighted = try? c.decode([CustomVocabularyTerm].self, forKey: .customVocabulary) {
            self.customVocabulary = weighted
        } else if let legacy = try? c.decode([String].self, forKey: .customVocabulary) {
            self.customVocabulary = legacy.map { CustomVocabularyTerm(text: $0, strength: .strong) }
        } else {
            self.customVocabulary = []
        }
        self.packTermAdditions = try c.decodeIfPresent([String: [String]].self, forKey: .packTermAdditions) ?? [:]
        self.packTermRemovals = try c.decodeIfPresent([String: [String]].self, forKey: .packTermRemovals) ?? [:]
        self.formatLists = try c.decodeIfPresent(Bool.self, forKey: .formatLists) ?? true
        self.formatParagraphs = try c.decodeIfPresent(Bool.self, forKey: .formatParagraphs) ?? true
        self.formatPunctuationCommands = try c.decodeIfPresent(Bool.self, forKey: .formatPunctuationCommands) ?? true
        self.useSmartTypography = try c.decodeIfPresent(Bool.self, forKey: .useSmartTypography) ?? true
        self.capitalizeSentences = try c.decodeIfPresent(Bool.self, forKey: .capitalizeSentences) ?? true
        self.preferredMicDeviceUID = try c.decodeIfPresent(String.self, forKey: .preferredMicDeviceUID)
        self.inputGain = try c.decodeIfPresent(Float.self, forKey: .inputGain) ?? 1.0
        self.useScreenContext = try c.decodeIfPresent(Bool.self, forKey: .useScreenContext) ?? false
        self.screenContextMode = try c.decodeIfPresent(ScreenContextMode.self, forKey: .screenContextMode) ?? .accessibilityWithOCRFallback
        self.screenContextMaxTerms = try c.decodeIfPresent(Int.self, forKey: .screenContextMaxTerms) ?? 60
        self.screenContextExcludedBundleIDs = try c.decodeIfPresent(Set<String>.self, forKey: .screenContextExcludedBundleIDs) ?? ScreenContextDefaults.excludedBundleIDs
        self.screenContextAXMinimumChars = try c.decodeIfPresent(Int.self, forKey: .screenContextAXMinimumChars) ?? 80
        let decodedEngine = try c.decodeIfPresent(MeetingTranscriptionEngine.self, forKey: .speechEngine)
            ?? MeetingTranscriptionEngine.dictationEngine
        self.speechEngine = MeetingTranscriptionEngine.normalizedDictationEngine(decodedEngine)
        self.engineIdleUnload = try c.decodeIfPresent(EngineIdleUnload.self, forKey: .engineIdleUnload) ?? .min5
        self.askScreenShortcut = try c.decodeIfPresent(DictationShortcut.self, forKey: .askScreenShortcut)
        // Migration: older settings files predate the explicit enable flag and
        // used "shortcut present" to mean "feature on". Preserve that intent so
        // upgrading users keep their ask-screen shortcut working.
        self.askScreenEnabled = try c.decodeIfPresent(Bool.self, forKey: .askScreenEnabled) ?? (self.askScreenShortcut != nil)
        self.learnFromEdits = try c.decodeIfPresent(Bool.self, forKey: .learnFromEdits) ?? false
        self.voiceActionsShortcut = try c.decodeIfPresent(DictationShortcut.self, forKey: .voiceActionsShortcut)
        self.voiceActionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceActionsEnabled)
            ?? (self.voiceActionsShortcut != nil)
        self.voiceActionConnectors = try c.decodeIfPresent(Set<VoiceActionConnector>.self, forKey: .voiceActionConnectors)
            ?? [.reminders]
    }
}

// MARK: - Engine idle unload

/// Inactivity window after which loaded transcription / post-process engines
/// (Parakeet, Whisper, Qwen) get released to free memory. Mirrors Handy's
/// `ModelUnloadTimeout` enum so the settings UX feels familiar to power
/// users coming from that app.
///
/// `.never` keeps the original behavior: warm models forever, snappiest
/// re-press, biggest steady-state RAM cost. Everything else trades a
/// one-time re-warm (multi-second on cold cache, ~150ms on a populated
/// FluidAudio cache) for a smaller idle footprint.
enum EngineIdleUnload: String, Codable, CaseIterable, Identifiable {
    case never
    case immediately
    case min2
    case min5
    case min10
    case min15
    case hour1

    var id: String { rawValue }

    /// Seconds of idleness after which the unload fires. `nil` means "never
    /// based on time" — `.never` keeps models warm; `.immediately` is the
    /// post-each-session hot path and never uses the idle timer.
    var idleSeconds: TimeInterval? {
        switch self {
        case .never, .immediately: return nil
        case .min2: return 2 * 60
        case .min5: return 5 * 60
        case .min10: return 10 * 60
        case .min15: return 15 * 60
        case .hour1: return 60 * 60
        }
    }

    var displayName: String {
        switch self {
        case .never:        return "Never"
        case .immediately:  return "After every dictation"
        case .min2:         return "2 minutes"
        case .min5:         return "5 minutes"
        case .min10:        return "10 minutes"
        case .min15:        return "15 minutes"
        case .hour1:        return "1 hour"
        }
    }

    var subtitle: String {
        switch self {
        case .never:
            return "Keep speech and AI models in memory until you quit Jack. Snappiest next press, highest idle RAM."
        case .immediately:
            return "Release models the moment each dictation finishes. Lowest idle RAM, every press pays a re-warm cost."
        case .min2, .min5, .min10, .min15, .hour1:
            return "Hold the loaded models for this long after your last dictation, then release. A burst of back-to-back dictations stays warm."
        }
    }
}

// MARK: - Screen context mode + defaults

/// Capture strategy for the "read my screen" dictation feature.
enum ScreenContextMode: String, Codable, CaseIterable, Identifiable {
    case accessibilityOnly = "ax-only"
    case accessibilityWithOCRFallback = "ax-with-ocr"
    case ocrOnly = "ocr-only"

    var id: String { rawValue }

    /// True if this mode ever needs a Screen Recording grant.
    var needsScreenRecording: Bool {
        switch self {
        case .accessibilityOnly: return false
        case .accessibilityWithOCRFallback, .ocrOnly: return true
        }
    }
}

enum ScreenContextDefaults {
    /// Sensible blocklist of apps where reading the screen would be either
    /// privacy-hostile (password managers) or pointless (security agents,
    /// the system Keychain). Users can add or remove from this list in
    /// Settings. Kept conservative — we don't preemptively block every
    /// browser because users often dictate into web apps.
    static let excludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "com.apple.keychainaccess"
    ]
}

/// A single completed dictation. Stored briefly so the user can re-copy from
/// the dictation history panel if a paste failed or they want to revisit
/// something they just dictated.
struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    var entryID: UUID
    var text: String
    var rawTranscript: String
    var style: DictationStyle
    var level: DictationLevel
    var durationSeconds: Double
    var createdAt: Date

    init(
        entryID: UUID = UUID(),
        text: String,
        rawTranscript: String,
        style: DictationStyle,
        level: DictationLevel,
        durationSeconds: Double,
        createdAt: Date = Date()
    ) {
        self.entryID = entryID
        self.text = text
        self.rawTranscript = rawTranscript
        self.style = style
        self.level = level
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
    }

    var id: UUID { entryID }
}

// MARK: - Key name catalog (Mac extended keys)

/// Display names + virtual keycodes for keys the dictation hotkey recorder
/// accepts. Broader than `GlobalShortcut.displayName(for:)` because dictation
/// allows naked keys (no modifier) and the user explicitly asked for the
/// "miscellaneous keys near Delete" (Help, Home, End, PgUp, PgDn, F13–F20,
/// arrows, function row).
enum DictationKeyNames {
    /// Virtual keycodes for the modifier keys, including left/right variants.
    /// macOS emits distinct keycodes in `.flagsChanged` events so we can bind
    /// "Right Option" without affecting Left Option.
    static let rightOption: UInt32 = UInt32(kVK_RightOption)        // 61
    static let leftOption: UInt32 = UInt32(kVK_Option)              // 58
    static let rightCommand: UInt32 = UInt32(kVK_RightCommand)      // 54
    static let leftCommand: UInt32 = UInt32(kVK_Command)            // 55
    static let rightControl: UInt32 = UInt32(kVK_RightControl)      // 62
    static let leftControl: UInt32 = UInt32(kVK_Control)            // 59
    static let rightShift: UInt32 = UInt32(kVK_RightShift)          // 60
    static let leftShift: UInt32 = UInt32(kVK_Shift)                // 56
    static let capsLock: UInt32 = UInt32(kVK_CapsLock)              // 57
    static let function: UInt32 = UInt32(kVK_Function)              // 63 — Fn / Globe

    static let modifierKeyCodes: Set<UInt32> = [
        rightOption, leftOption,
        rightCommand, leftCommand,
        rightControl, leftControl,
        rightShift, leftShift,
        capsLock, function
    ]

    static func isModifierKeyCode(_ code: UInt32) -> Bool {
        modifierKeyCodes.contains(code)
    }

    /// Long-form display name. Used in Settings.
    static func displayName(for code: UInt32) -> String {
        if let modifier = modifierName(for: code) { return modifier }
        if let extended = extendedKeyName(for: code) { return extended }
        if let function = functionKeyName(for: code) { return function }
        if let arrow = arrowKeyName(for: code) { return arrow }
        if let letter = letterKeyName(for: code) { return letter }
        if let number = numberKeyName(for: code) { return number }
        if let symbol = symbolKeyName(for: code) { return symbol }
        if let keypad = keypadKeyName(for: code) { return keypad }
        return "Key \(code)"
    }

    private static func modifierName(for code: UInt32) -> String? {
        switch code {
        case rightOption: return "Right Option"
        case leftOption: return "Left Option"
        case rightCommand: return "Right Cmd"
        case leftCommand: return "Left Cmd"
        case rightControl: return "Right Ctrl"
        case leftControl: return "Left Ctrl"
        case rightShift: return "Right Shift"
        case leftShift: return "Left Shift"
        case capsLock: return "Caps Lock"
        case function: return "Fn"
        default: return nil
        }
    }

    /// Keys the user specifically asked about — Help / Home / End / PgUp / PgDn /
    /// ForwardDelete cluster near the main Delete key on extended keyboards.
    private static func extendedKeyName(for code: UInt32) -> String? {
        switch code {
        case UInt32(kVK_Help): return "Help"
        case UInt32(kVK_Home): return "Home"
        case UInt32(kVK_End): return "End"
        case UInt32(kVK_PageUp): return "Page Up"
        case UInt32(kVK_PageDown): return "Page Down"
        case UInt32(kVK_ForwardDelete): return "Fwd Delete"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Escape): return "Esc"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Space): return "Space"
        case 105: return "Print Screen"
        case 113: return "Scroll Lock"
        case 114: return "Pause"
        default: return nil
        }
    }

    private static func functionKeyName(for code: UInt32) -> String? {
        let mapping: [UInt32: Int] = [
            UInt32(kVK_F1): 1, UInt32(kVK_F2): 2, UInt32(kVK_F3): 3, UInt32(kVK_F4): 4,
            UInt32(kVK_F5): 5, UInt32(kVK_F6): 6, UInt32(kVK_F7): 7, UInt32(kVK_F8): 8,
            UInt32(kVK_F9): 9, UInt32(kVK_F10): 10, UInt32(kVK_F11): 11, UInt32(kVK_F12): 12,
            UInt32(kVK_F13): 13, UInt32(kVK_F14): 14, UInt32(kVK_F15): 15, UInt32(kVK_F16): 16,
            UInt32(kVK_F17): 17, UInt32(kVK_F18): 18, UInt32(kVK_F19): 19, UInt32(kVK_F20): 20
        ]
        return mapping[code].map { "F\($0)" }
    }

    private static func arrowKeyName(for code: UInt32) -> String? {
        switch code {
        case UInt32(kVK_LeftArrow): return "Left Arrow"
        case UInt32(kVK_RightArrow): return "Right Arrow"
        case UInt32(kVK_UpArrow): return "Up Arrow"
        case UInt32(kVK_DownArrow): return "Down Arrow"
        default: return nil
        }
    }

    private static func letterKeyName(for code: UInt32) -> String? {
        let mapping: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z"
        ]
        return mapping[code]
    }

    private static func numberKeyName(for code: UInt32) -> String? {
        let mapping: [UInt32: String] = [
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9"
        ]
        return mapping[code]
    }

    /// Punctuation + symbol keys on the main keyboard. These are the
    /// keycodes that were showing as raw "Key 30", "Key 42", etc. before.
    private static func symbolKeyName(for code: UInt32) -> String? {
        let mapping: [UInt32: String] = [
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Grave): "`"
        ]
        return mapping[code]
    }

    /// Numeric keypad on extended keyboards.
    private static func keypadKeyName(for code: UInt32) -> String? {
        let mapping: [UInt32: String] = [
            UInt32(kVK_ANSI_Keypad0): "Keypad 0",
            UInt32(kVK_ANSI_Keypad1): "Keypad 1",
            UInt32(kVK_ANSI_Keypad2): "Keypad 2",
            UInt32(kVK_ANSI_Keypad3): "Keypad 3",
            UInt32(kVK_ANSI_Keypad4): "Keypad 4",
            UInt32(kVK_ANSI_Keypad5): "Keypad 5",
            UInt32(kVK_ANSI_Keypad6): "Keypad 6",
            UInt32(kVK_ANSI_Keypad7): "Keypad 7",
            UInt32(kVK_ANSI_Keypad8): "Keypad 8",
            UInt32(kVK_ANSI_Keypad9): "Keypad 9",
            UInt32(kVK_ANSI_KeypadDecimal): "Keypad .",
            UInt32(kVK_ANSI_KeypadMultiply): "Keypad ×",
            UInt32(kVK_ANSI_KeypadPlus): "Keypad +",
            UInt32(kVK_ANSI_KeypadMinus): "Keypad −",
            UInt32(kVK_ANSI_KeypadDivide): "Keypad ÷",
            UInt32(kVK_ANSI_KeypadEquals): "Keypad =",
            UInt32(kVK_ANSI_KeypadEnter): "Keypad Enter",
            UInt32(kVK_ANSI_KeypadClear): "Keypad Clear"
        ]
        return mapping[code]
    }
}
