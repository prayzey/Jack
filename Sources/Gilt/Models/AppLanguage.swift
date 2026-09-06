import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case system
    case english
    case spanish
    case german

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .spanish:
            return "es"
        case .german:
            return "de"
        }
    }

    var label: String { localizedLabel() }

    func localizedLabel(locale: Locale? = nil) -> String {
        switch self {
        case .system:
            return L10n.string("appLanguage.system.label", default: "System Default", locale: locale)
        case .english:
            return L10n.string("appLanguage.english.label", default: "English", locale: locale)
        case .spanish:
            return L10n.string("appLanguage.spanish.label", default: "Espanol", locale: locale)
        case .german:
            return L10n.string("appLanguage.german.label", default: "Deutsch", locale: locale)
        }
    }
}
