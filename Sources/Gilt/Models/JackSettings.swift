import Foundation

/// "Jack" is the user-facing name for the on-screen character that used to be
/// called a "Pulse character." Jack is one companion (single character at a
/// time) with multiple jobs: usage alerts, reminders, and chat with the local
/// Qwen model.
///
/// `JackSettings` is *additive* on top of the legacy `pulseCharacter*` fields
/// on `AppSettings`. The legacy fields remain canonical for things they
/// already cover (enabled flag, trigger mode, message mode, reminders).
/// `JackSettings` only stores the new concepts introduced by the rebrand:
///
/// - `presenceMode` — including the new "alwaysOn" state where Jack stays
///   parked above the dock instead of only appearing on triggers.
/// - `look` — which character variant Jack wears today.
/// - `jobs` — which of the three jobs Jack performs.
/// - `defaultPopoverTab` — which tab opens first when the user clicks Jack.
///
/// Keeping these separate from the legacy fields lets Phase 1 ship without
/// touching any of the existing Pulse code paths. Later phases can migrate
/// call sites over to read from `JackSettings` directly.

/// Where Jack lives on screen.
enum JackPresenceMode: String, Codable, CaseIterable {
    /// Jack never appears.
    case off
    /// Jack walks on screen only when something (a usage refresh, a
    /// threshold crossing, a reminder) triggers him. This matches the
    /// legacy Pulse character behavior.
    case onTriggers
    /// Jack is permanently visible — parked above the dock, occasionally
    /// idling or walking a short distance. New in the Jack rebrand.
    case alwaysOn
}

/// Visual variant for Jack. The underlying video assets ship in
/// `Resources/PulseCharacters/`. Adding a new look means dropping a new
/// `walk-<name>-01.mov` and extending this enum.
enum JackLook: String, Codable, CaseIterable {
    case bruce
}

/// One of Jack's responsibilities. The set of active jobs is user-configurable
/// in the Jack settings tab.
enum JackJob: String, Codable, CaseIterable {
    /// Surface scheduled reminders to the user.
    case reminders
    /// Power the chat tab in the Jack popover (talks to local Qwen).
    case chat
}

/// Which tab opens first when the user clicks Jack and the popover appears.
enum JackPopoverTab: String, Codable, CaseIterable {
    case chat
    case reminders
}

/// Settings owned by the Jack rebrand. Stored as a nested struct on
/// `AppSettings` under key `jackSettings`.
///
/// `JackSettings` is `Codable` with explicit `init(from:)` / `encode(to:)`
/// that tolerate missing keys — required so settings JSON files written by
/// older Gilt builds still decode cleanly.
struct JackSettings: Codable, Equatable {
    var presenceMode: JackPresenceMode
    var look: JackLook
    /// Which jobs Jack performs. Stored as a `Set` for easy contains-checks
    /// in UI code; encoded as a sorted array in JSON so the on-disk shape is
    /// stable across writes.
    var jobs: Set<JackJob>
    var defaultPopoverTab: JackPopoverTab

    init(
        presenceMode: JackPresenceMode = .off,
        look: JackLook = .bruce,
        jobs: Set<JackJob> = [.reminders, .chat],
        defaultPopoverTab: JackPopoverTab = .chat
    ) {
        self.presenceMode = presenceMode
        self.look = look
        self.jobs = jobs
        self.defaultPopoverTab = defaultPopoverTab
    }

    /// Convenience: is Jack visible at all right now?
    var isVisible: Bool {
        presenceMode != .off
    }

    func performs(_ job: JackJob) -> Bool {
        jobs.contains(job)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case presenceMode
        case look
        case jobs
        case defaultPopoverTab
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presenceMode = try container.decodeIfPresent(JackPresenceMode.self, forKey: .presenceMode) ?? .off
        // Decode look via its raw string and map manually so a retired look
        // (e.g. the removed "jazz" variant) stored by an older build falls back
        // to .bruce instead of failing the whole settings decode.
        let lookRaw = try container.decodeIfPresent(String.self, forKey: .look)
        look = lookRaw.flatMap(JackLook.init(rawValue:)) ?? .bruce
        // Decode jobs as an array of raw strings, then build the Set. This way
        // unknown future job values are silently dropped instead of failing
        // the whole settings decode for forward-compat with older app builds.
        let jobsArray = try container.decodeIfPresent([String].self, forKey: .jobs) ?? []
        if jobsArray.isEmpty {
            jobs = [.reminders, .chat]
        } else {
            jobs = Set(jobsArray.compactMap(JackJob.init(rawValue:)))
        }
        defaultPopoverTab = try container.decodeIfPresent(JackPopoverTab.self, forKey: .defaultPopoverTab) ?? .chat
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presenceMode, forKey: .presenceMode)
        try container.encode(look, forKey: .look)
        // Encode jobs as a sorted array of raw strings for a stable on-disk
        // representation (Sets have no guaranteed iteration order).
        let sortedJobs = jobs.map(\.rawValue).sorted()
        try container.encode(sortedJobs, forKey: .jobs)
        try container.encode(defaultPopoverTab, forKey: .defaultPopoverTab)
    }
}

extension JackSettings {
    /// First-launch migration: build a `JackSettings` from the legacy
    /// `pulseCharacter*` fields of `AppSettings`. Used when decoding settings
    /// JSON written by an older Gilt build that has no `jackSettings` key.
    ///
    /// The mapping is intentionally conservative:
    /// - `presenceMode` reflects the legacy `pulseCharactersEnabled` bool.
    ///   We never opt a returning user into "alwaysOn" — that's a deliberate
    ///   choice they have to make from the new settings tab.
    /// - `jobs` defaults to all three on, regardless of legacy message mode.
    ///   Users can disable jobs from the new tab; this avoids accidentally
    ///   hiding the new chat feature behind a legacy preference.
    /// - `look` and `defaultPopoverTab` use plain defaults — there's no
    ///   legacy preference for either.
    static func migrating(
        fromLegacyPulseCharactersEnabled enabled: Bool
    ) -> JackSettings {
        JackSettings(
            presenceMode: enabled ? .onTriggers : .off,
            look: .bruce,
            jobs: [.reminders, .chat],
            defaultPopoverTab: .chat
        )
    }
}
