import Foundation

enum L10n {
    private static let tableName = "Localizable"
    private static let preferredLocaleLock = NSLock()
    // AI note:
    // Swift 6 flags mutable statics even when we guard them with a lock. Marking
    // this as `nonisolated(unsafe)` keeps the compiler honest about the escape hatch
    // while preserving the lock-based synchronization used by tests and app settings.
    nonisolated(unsafe) private static var preferredLocaleIdentifier: String?
    static let bundle = AppResourceLocator.resourceBundle()

    static func setPreferredLocaleIdentifier(_ localeIdentifier: String?) {
        preferredLocaleLock.lock()
        preferredLocaleIdentifier = localeIdentifier
        preferredLocaleLock.unlock()
    }

    static func withPreferredLocaleIdentifier<T>(_ localeIdentifier: String?, perform: () throws -> T) rethrows -> T {
        let previous = currentPreferredLocaleIdentifier()
        setPreferredLocaleIdentifier(localeIdentifier)
        defer { setPreferredLocaleIdentifier(previous) }
        return try perform()
    }

    static func string(
        _ key: String,
        default defaultValue: String,
        locale: Locale? = nil,
        comment: String = ""
    ) -> String {
        localizedBundle(for: locale ?? preferredLocale()).localizedString(
            forKey: key,
            value: defaultValue,
            table: tableName
        )
    }

    static func knownLocalizedValues(
        _ key: String,
        default defaultValue: String,
        localeIdentifiers: [String]
    ) -> Set<String> {
        var values = Set([defaultValue])
        for localeIdentifier in localeIdentifiers {
            values.insert(
                string(
                    key,
                    default: defaultValue,
                    locale: Locale(identifier: localeIdentifier)
                )
            )
        }
        return values
    }

    // AI note:
    // This helper intentionally resolves locale-specific bundles by hand for tests
    // and migration code. Relying on implicit bundle selection makes it easy to ship
    // code that "works on my machine" but silently reads the wrong language in the
    // packaged SwiftPM app.
    private static func localizedBundle(for locale: Locale?) -> Bundle {
        guard let locale else { return bundle }

        for candidate in localeCandidates(for: locale) {
            guard let path = bundle.path(forResource: candidate, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path)
            else {
                continue
            }
            return localizedBundle
        }

        return bundle
    }

    private static func preferredLocale() -> Locale? {
        guard let identifier = currentPreferredLocaleIdentifier() else { return nil }
        return Locale(identifier: identifier)
    }

    private static func currentPreferredLocaleIdentifier() -> String? {
        preferredLocaleLock.lock()
        defer { preferredLocaleLock.unlock() }
        return preferredLocaleIdentifier
    }

    private static func localeCandidates(for locale: Locale) -> [String] {
        let normalized = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let languageCode = normalized.split(separator: "-").first.map(String.init)

        var candidates = [normalized]
        if let languageCode, languageCode != normalized {
            candidates.append(languageCode)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
