import Foundation

enum LocalizedSystemFolderIdentity: Equatable {
    case clipboard
    case smartCategory(SmartCategory)

    var localizationKey: String {
        switch self {
        case .clipboard:
            return "systemFolder.clipboard.name"
        case .smartCategory(let category):
            switch category {
            case .code: return "smartCategory.code.name"
            case .images: return "smartCategory.images.name"
            case .links: return "smartCategory.links.name"
            case .contacts: return "smartCategory.contacts.name"
            case .colors: return "smartCategory.colors.name"
            case .addresses: return "smartCategory.addresses.name"
            case .sensitive: return "smartCategory.sensitive.name"
            }
        }
    }

    var defaultStoredName: String {
        switch self {
        case .clipboard:
            return "Clipboard"
        case .smartCategory(let category):
            switch category {
            case .code: return "Code"
            case .images: return "Images"
            case .links: return "Links"
            case .contacts: return "Contacts"
            case .colors: return "Colors"
            case .addresses: return "Addresses"
            case .sensitive: return "Sensitive"
            }
        }
    }

    var localizedDisplayName: String {
        L10n.string(
            localizationKey,
            default: defaultStoredName
        )
    }

    func matchesKnownDefaultName(_ candidate: String) -> Bool {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        return allKnownDefaultNames.contains(normalized)
    }

    private var allKnownDefaultNames: Set<String> {
        L10n.knownLocalizedValues(
            localizationKey,
            default: defaultStoredName,
            localeIdentifiers: ["en", "es", "de"]
        )
    }
}
