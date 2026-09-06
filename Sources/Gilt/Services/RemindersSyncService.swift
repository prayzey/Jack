import EventKit
import Foundation
import OSLog

/// One-way bridge that mirrors Jack's in-app `PulseReminder`s into the user's
/// real Apple Reminders database via EventKit.
///
/// "One-way" means: when Jack creates a reminder, we also create a matching
/// item in Apple Reminders so it syncs to the user's iPhone/iPad and fires on
/// the lock screen even when Jack is closed. We never read changes back from
/// Apple Reminders into Jack, and we never delete the user's Apple reminders on
/// their behalf. Jack stays the source of truth on its side; Apple Reminders is
/// a downstream mirror.
///
/// Why a dedicated service instead of inlining EventKit calls: EventKit needs a
/// single long-lived `EKEventStore`, an explicit permission handshake, and a
/// stable mapping so the same Jack reminder is never mirrored twice. Keeping all
/// of that in one place means the rest of the app only ever sees `mirror(_:)`.
@MainActor
final class RemindersSyncService {
    static let shared = RemindersSyncService()

    private let store = EKEventStore()
    private let log = Logger(subsystem: AppBrand.logSubsystem, category: "RemindersSync")

    /// Title of the dedicated Apple Reminders list we create and write into.
    /// We never write into the user's existing lists so our mirror is easy to
    /// find, mute, or delete without disturbing their own reminders.
    private let listTitle = AppBrand.displayName

    /// Maps a `PulseReminder.id` -> the EventKit `calendarItemIdentifier` of the
    /// reminder we created for it. This is what makes the mirror idempotent:
    /// re-mirroring an already-synced reminder is a no-op. Stored separately from
    /// `AppSettings` so it does not have to round-trip through the settings model.
    private let mappingDefaultsKey = "JackRemindersSyncMap"

    /// Cached identifier of the dedicated Jack reminders list once resolved/created.
    private let calendarIDDefaultsKey = "JackRemindersSyncCalendarID"

    /// User opt-in flag. Kept in UserDefaults (not `AppSettings`) so toggling it
    /// does not have to round-trip through the settings Codable, and so the
    /// service can answer "should I mirror?" without a reference to the store.
    private let syncEnabledKey = "JackRemindersSyncEnabled"
    private let listPreferenceKey = "JackRemindersListPreference"

    private init() {}

    /// Which Apple Reminders list new mirrored items are written into.
    var listPreference: AppleRemindersListPreference {
        get {
            guard let data = UserDefaults.standard.data(forKey: listPreferenceKey),
                  let decoded = try? JSONDecoder().decode(AppleRemindersListPreference.self, from: data) else {
                return AppleRemindersListPreference(kind: .jackDedicated)
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: listPreferenceKey)
            }
        }
    }

    /// Reminder lists the user can write to — for the destination picker.
    func modifiableReminderLists() -> [RemindersListOption] {
        guard hasAccess else { return [] }
        return store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { RemindersListOption(calendarIdentifier: $0.calendarIdentifier, title: $0.title) }
    }

    func displayName(for preference: AppleRemindersListPreference) -> String {
        switch preference.kind {
        case .systemDefault:
            return store.defaultCalendarForNewReminders()?.title ?? "Default list"
        case .jackDedicated:
            return listTitle
        case .namedList:
            guard let id = preference.namedListCalendarID,
                  let calendar = store.calendar(withIdentifier: id) else {
                return "Choose a list"
            }
            return calendar.title
        }
    }

    /// Whether the user has turned on Apple Reminders sync. Note this is the
    /// user's *intent*; actual writes still require `hasAccess`.
    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    // MARK: - Permission

    /// Whether the user has granted access to write reminders.
    /// `.fullAccess` is the only granting status EventKit reports for reminders
    /// on macOS 14+ (there is no write-only tier for reminders like there is for
    /// calendar events).
    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .denied || status == .restricted
    }

    /// Triggers the system permission prompt the first time, then returns whether
    /// we can write. Safe to call repeatedly; once decided, the OS answers
    /// without re-prompting.
    @discardableResult
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        do {
            // macOS 14+ / iOS 17+. The project targets macOS 14, so the older
            // `requestAccess(to:)` path is intentionally not used.
            let granted = try await store.requestFullAccessToReminders()
            if !granted {
                log.notice("Reminders access not granted by user")
            }
            return granted
        } catch {
            log.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Mirroring

    /// Mirror a single Jack reminder into Apple Reminders.
    ///
    /// No-ops (without error) if the user has not granted access, so callers can
    /// fire-and-forget without gating every call site on permission state.
    /// Idempotent: a `PulseReminder` already mirrored is skipped.
    func mirror(_ reminder: PulseReminder) async {
        guard hasAccess else {
            log.debug("Skipping mirror; no reminders access")
            return
        }
        guard !isAlreadyMirrored(reminder.id) else { return }

        do {
            let calendar = try resolveTargetCalendar()
            let ekReminder = EKReminder(eventStore: store)
            ekReminder.calendar = calendar
            ekReminder.title = reminder.message

            // Carry the originating context (e.g. the clip title) into the notes
            // so the user has provenance on their phone.
            if let source = reminder.sourceTitle, !source.isEmpty {
                ekReminder.notes = source
            }

            // A reminder with no due date in Jack means "next time you see me",
            // which has no Apple-Reminders equivalent. We still mirror it as an
            // undated reminder so it shows up in the list; only dated reminders
            // get an alarm that actually fires on the user's devices.
            if let due = reminder.dueAt {
                ekReminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: due
                )
                ekReminder.addAlarm(EKAlarm(absoluteDate: due))
            }

            try store.save(ekReminder, commit: true)
            recordMapping(reminderID: reminder.id, externalID: ekReminder.calendarItemIdentifier)
            log.debug("Mirrored reminder \(reminder.id, privacy: .public) to Apple Reminders")
        } catch {
            log.error("Failed to mirror reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Convenience for mirroring a batch (e.g. a one-time backfill of existing
    /// in-app reminders right after the user first grants access).
    func mirrorAll(_ reminders: [PulseReminder]) async {
        guard hasAccess else { return }
        for reminder in reminders {
            await mirror(reminder)
        }
    }

    // MARK: - Calendar (list) resolution

    private func resolveTargetCalendar() throws -> EKCalendar {
        switch listPreference.kind {
        case .systemDefault:
            if let defaultCalendar = store.defaultCalendarForNewReminders(),
               defaultCalendar.allowsContentModifications {
                return defaultCalendar
            }
            if let first = modifiableReminderLists().first,
               let calendar = store.calendar(withIdentifier: first.calendarIdentifier) {
                return calendar
            }
            return try resolveJackCalendar()

        case .jackDedicated:
            return try resolveJackCalendar()

        case .namedList:
            if let id = listPreference.namedListCalendarID,
               let calendar = store.calendar(withIdentifier: id),
               calendar.allowsContentModifications {
                return calendar
            }
            // Stale ID — fall back so voice actions still work after a list delete.
            if let defaultCalendar = store.defaultCalendarForNewReminders(),
               defaultCalendar.allowsContentModifications {
                return defaultCalendar
            }
            return try resolveJackCalendar()
        }
    }

    /// Find or create the dedicated Jack reminders list. We cache its
    /// identifier so we reuse the same list across launches instead of spawning
    /// duplicates.
    private func resolveJackCalendar() throws -> EKCalendar {
        if let cachedID = UserDefaults.standard.string(forKey: calendarIDDefaultsKey),
           let cached = store.calendar(withIdentifier: cachedID),
           cached.allowsContentModifications {
            return cached
        }

        // Reuse an existing Jack list if one is already there (e.g. created on
        // another Mac and synced down via iCloud).
        if let existing = store.calendars(for: .reminder).first(where: {
            $0.title == listTitle && $0.allowsContentModifications
        }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: calendarIDDefaultsKey)
            return existing
        }

        // Pre-rename builds created a "Jack" list. Adopt it in place (renaming to
        // "Jack") rather than spawning a second list, so old and new items never
        // split across two lists. If the rename can't be saved, still USE the
        // legacy list rather than creating a duplicate.
        let legacyListTitle = "Gilt"
        if let legacy = store.calendars(for: .reminder).first(where: {
            $0.title == legacyListTitle && $0.allowsContentModifications
        }) {
            legacy.title = listTitle
            do {
                try store.saveCalendar(legacy, commit: true)
            } catch {
                log.error("Could not rename legacy Gilt list to Jack: \(error.localizedDescription, privacy: .public)")
            }
            UserDefaults.standard.set(legacy.calendarIdentifier, forKey: calendarIDDefaultsKey)
            return legacy
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listTitle
        // Prefer the same source the user's default reminders live in (usually
        // iCloud) so our list syncs across devices too. Fall back to any CalDAV
        // (iCloud) source, then to whatever source exists.
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first

        try store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDDefaultsKey)
        return calendar
    }

    // MARK: - Idempotency map

    private func isAlreadyMirrored(_ reminderID: UUID) -> Bool {
        // Once a Jack reminder has been mirrored we never mirror it again, even
        // if the user later deleted the item in Apple Reminders. Honoring that
        // deletion (rather than resurrecting it) is what keeps this strictly
        // one-way and non-annoying.
        currentMap()[reminderID.uuidString] != nil
    }

    private func recordMapping(reminderID: UUID, externalID: String) {
        var map = currentMap()
        map[reminderID.uuidString] = externalID
        UserDefaults.standard.set(map, forKey: mappingDefaultsKey)
    }

    private func currentMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: mappingDefaultsKey) as? [String: String] ?? [:]
    }
}
