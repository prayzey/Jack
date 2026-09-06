import Foundation

/// Where mirrored reminders land in Apple Reminders. Stored by
/// `RemindersSyncService` — not in `AppSettings` — so toggling sync does not
/// require a full settings round-trip.
struct AppleRemindersListPreference: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// The list Reminders uses for new items (usually the user's main list).
        case systemDefault
        /// Jack's dedicated reminders list — easy to find or mute separately.
        case jackDedicated
        /// A specific list the user picked from their Reminders account.
        case namedList

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .systemDefault: return "Default list"
            case .jackDedicated: return "Jack list"
            case .namedList: return "Choose a list…"
            }
        }

        var subtitle: String {
            switch self {
            case .systemDefault:
                return "Same place as reminders you create in the Reminders app."
            case .jackDedicated:
                return "Keeps Jack reminders in a separate \"Jack\" list."
            case .namedList:
                return "Pick one of your existing Reminders lists."
            }
        }
    }

    var kind: Kind = .systemDefault
    /// Set when `kind == .namedList`. Stable EventKit `calendarIdentifier`.
    var namedListCalendarID: String?

    static let `default` = AppleRemindersListPreference(kind: .systemDefault)
}

/// Lightweight row for a picker — title for display, identifier for persistence.
struct RemindersListOption: Identifiable, Equatable {
    var id: String { calendarIdentifier }
    let calendarIdentifier: String
    let title: String
}