import Foundation

enum ClipRelativeTimeFormatter {
    static func string(from date: Date, relativeTo now: Date = .now, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
