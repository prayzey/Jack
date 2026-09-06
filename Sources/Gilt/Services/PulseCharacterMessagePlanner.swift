import Foundation

struct PulseCharacterMessageConfiguration: Equatable {
    var mode: PulseCharacterMessageMode
    var customMessage: String
    var reminders: [PulseReminder]
}

struct PulseCharacterAmbientMessage: Equatable {
    enum Source: Equatable {
        case reminder(UUID)
        case recurringReminder
        case custom
        case inspiration
    }

    var text: String
    var expandedText: String
    var source: Source

    init(text: String, expandedText: String? = nil, source: Source) {
        self.text = text
        self.expandedText = expandedText ?? text
        self.source = source
    }
}

struct PulseCharacterMessagePlanner {
    static let maxBubbleCharacters = 96

    func ambientMessage(
        configuration: PulseCharacterMessageConfiguration,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> PulseCharacterAmbientMessage? {
        if configuration.mode == .remindersAndInspiration,
           let reminder = dueReminder(from: configuration.reminders, now: now) {
            return PulseCharacterAmbientMessage(
                text: Self.bubbleText(reminder.message),
                expandedText: Self.expandedMessageText(reminder.message),
                source: .reminder(reminder.id)
            )
        }

        switch configuration.mode {
        case .usageOnly:
            return nil
        case .custom:
            guard let message = Self.nonEmptyMessage(configuration.customMessage) else { return nil }
            return PulseCharacterAmbientMessage(
                text: Self.bubbleText(message),
                expandedText: message,
                source: .custom
            )
        case .dailyInspiration:
            let message = inspirationMessage(for: now, calendar: calendar, locale: locale)
            return PulseCharacterAmbientMessage(
                text: message.bubble,
                expandedText: message.expanded,
                source: .inspiration
            )
        case .remindersAndInspiration:
            if let message = Self.nonEmptyMessage(configuration.customMessage) {
                return PulseCharacterAmbientMessage(
                    text: Self.bubbleText(message),
                    expandedText: message,
                    source: .recurringReminder
                )
            }
            let message = inspirationMessage(for: now, calendar: calendar, locale: locale)
            return PulseCharacterAmbientMessage(
                text: message.bubble,
                expandedText: message.expanded,
                source: .inspiration
            )
        }
    }

    func shouldPreferAmbientMessage(
        configuration: PulseCharacterMessageConfiguration,
        overRoutineUsage triggerMode: PulseCharacterTriggerMode
    ) -> Bool {
        triggerMode == .interval && configuration.mode != .usageOnly
    }

    private func dueReminder(from reminders: [PulseReminder], now: Date) -> PulseReminder? {
        reminders
            .filter { $0.isDue(at: now) }
            .sorted {
                ($0.dueAt ?? $0.createdAt, $0.createdAt) < ($1.dueAt ?? $1.createdAt, $1.createdAt)
            }
            .first
    }

    private func inspirationMessage(for date: Date, calendar: Calendar, locale: Locale) -> PulseInspirationMessage {
        PulseInspirationMessageCatalog.message(for: date, locale: locale, calendar: calendar)
    }

    static func nonEmptyMessage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return expandedMessageText(trimmed)
    }

    static func expandedMessageText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: \.isNewline)
            .map { $0.split(separator: " ").joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func bubbleText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        guard normalized.count > Self.maxBubbleCharacters else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: Self.maxBubbleCharacters - 3)
        return String(normalized[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
