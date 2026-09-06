import Foundation

struct PulseInspirationMessage: Codable, Equatable, Identifiable {
    let id: String
    let bubble: String
    let expanded: String
}

struct PulseInspirationMessageCatalog {
    static let minimumMessageCount = 2_000

    private static let fallbackLocaleIdentifier = "en"

    static func messages(locale: Locale = .autoupdatingCurrent) -> [PulseInspirationMessage] {
        messages(localeIdentifier: locale.identifier)
    }

    static func messages(localeIdentifier: String) -> [PulseInspirationMessage] {
        let preferred = normalizedLanguageCode(from: localeIdentifier)
        if let messages = loadMessages(for: preferred), !messages.isEmpty {
            return messages
        }
        if preferred != fallbackLocaleIdentifier,
           let fallback = loadMessages(for: fallbackLocaleIdentifier),
           !fallback.isEmpty {
            return fallback
        }
        return builtInFallbackMessages
    }

    static func message(for date: Date, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) -> PulseInspirationMessage {
        message(for: date, localeIdentifier: locale.identifier, calendar: calendar)
    }

    static func message(for date: Date, localeIdentifier: String, calendar: Calendar = .current) -> PulseInspirationMessage {
        let messages = messages(localeIdentifier: localeIdentifier)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let seconds = calendar.component(.hour, from: date) * 3_600
            + calendar.component(.minute, from: date) * 60
            + calendar.component(.second, from: date)
        let slot = seconds / max(1, PulseRefreshInterval.fiveMinutes.secondsInt)
        let index = abs(((day - 1) * 288) + slot) % messages.count
        return messages[index]
    }

    private static func normalizedLanguageCode(from localeIdentifier: String) -> String {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier
            ?? localeIdentifier.split(separator: "_").first.map(String.init)
            ?? fallbackLocaleIdentifier
    }

    private static func loadMessages(for languageCode: String) -> [PulseInspirationMessage]? {
        guard let url = AppResourceLocator.url(
            forResource: languageCode,
            withExtension: "json",
            subdirectory: "Resources/PulseMessages"
        ) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([PulseInspirationMessage].self, from: data)
        } catch {
            return nil
        }
    }

    private static var builtInFallbackMessages: [PulseInspirationMessage] {
        [
            PulseInspirationMessage(
                id: "fallback-001",
                bubble: "Build the next inch; small progress still counts.",
                expanded: "Build the next inch. Small progress still counts, and today only needs one honest next move."
            )
        ]
    }
}

private extension PulseRefreshInterval {
    var secondsInt: Int {
        Int(seconds)
    }
}
