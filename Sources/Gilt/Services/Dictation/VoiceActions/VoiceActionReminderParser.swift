import Foundation

/// Parsed reminder intent from a voice-actions transcript.
enum VoiceReminderParseResult: Equatable {
    case success(title: String, due: JackReminderDue)
    case notAReminder
}

/// Heuristic parser for spoken reminder commands. Pure, deterministic, and
/// fast — no LLM required for the common “remind me to X tomorrow” shapes.
enum VoiceActionReminderParser {
    private static let prefixes: [String] = [
        "remind me to ",
        "remind me ",
        "set a reminder to ",
        "set a reminder for ",
        "set reminder to ",
        "set reminder for ",
        "add a reminder to ",
        "add reminder to ",
        "create a reminder to ",
        "create a reminder for ",
        "reminder to ",
        "remember to ",
    ]

    private static let relativeTimePatterns: [(pattern: String, due: JackReminderDue)] = [
        ("in ten minutes", .inTenMinutes),
        ("in 10 minutes", .inTenMinutes),
        ("in half an hour", .inThirtyMinutes),
        ("in thirty minutes", .inThirtyMinutes),
        ("in 30 minutes", .inThirtyMinutes),
        ("in an hour", .inOneHour),
        ("in one hour", .inOneHour),
        ("in 1 hour", .inOneHour),
        ("in 60 minutes", .inOneHour),
        ("tomorrow morning", .tomorrowMorning),
        ("tomorrow", .tomorrowMorning),
        ("tonight", .thisEvening),
        ("this evening", .thisEvening),
    ]

    static func parse(
        _ transcript: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> VoiceReminderParseResult {
        let cleaned = TranscriptCleaner
            .clean(transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .notAReminder }

        let lowered = cleaned.lowercased()
        guard looksLikeReminder(lowered) else { return .notAReminder }

        let body = stripPrefix(from: cleaned, lowered: lowered)
        guard !body.isEmpty else { return .notAReminder }

        let (title, due) = extractDue(from: body, now: now, calendar: calendar)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .notAReminder }

        return .success(title: trimmedTitle, due: due)
    }

    private static func looksLikeReminder(_ lowered: String) -> Bool {
        if prefixes.contains(where: { lowered.hasPrefix($0) }) { return true }
        let triggers = ["remind me", "set a reminder", "set reminder", "add a reminder", "remember to"]
        return triggers.contains(where: { lowered.contains($0) })
    }

    private static func stripPrefix(from original: String, lowered: String) -> String {
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            return String(original.dropFirst(prefix.count))
        }
        for phrase in ["remind me to ", "remind me ", "remember to "] where lowered.contains(phrase) {
            if let range = lowered.range(of: phrase) {
                return String(original[range.upperBound...])
            }
        }
        return original
    }

    private static func extractDue(
        from body: String,
        now: Date,
        calendar: Calendar
    ) -> (String, JackReminderDue) {
        var text = body
        var lowered = text.lowercased()

        for (pattern, due) in relativeTimePatterns {
            if let range = lowered.range(of: pattern) {
                let start = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: range.lowerBound))
                let end = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: range.upperBound))
                text.removeSubrange(start..<end)
                text = text
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
                return (text, due)
            }
        }

        if let absolute = parseAbsoluteTime(in: lowered, now: now, calendar: calendar) {
            let stripped = stripAbsoluteTimePhrases(from: &text, lowered: &lowered)
            return (stripped, .custom(absolute))
        }

        return (text, .anytime)
    }

    private static func parseAbsoluteTime(
        in lowered: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        guard let match = detector?.firstMatch(in: lowered, options: [], range: range),
              match.resultType == .date,
              let date = match.date else {
            return nil
        }
        if date < now.addingTimeInterval(-60) {
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    private static func stripAbsoluteTimePhrases(from text: inout String, lowered: inout String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        guard let match = detector?.firstMatch(in: lowered, options: [], range: range),
              let swiftRange = Range(match.range, in: lowered) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text.removeSubrange(swiftRange)
        lowered.removeSubrange(swiftRange)
        return text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
    }
}