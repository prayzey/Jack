import Foundation

extension ClipboardStore {
    var preferredAppLocale: Locale {
        guard let identifier = settings.appLanguage.localeIdentifier else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    func setAppLanguage(_ appLanguage: AppLanguage) {
        guard settings.appLanguage != appLanguage else { return }
        settings.appLanguage = appLanguage
    }

    func applyPreferredAppLanguage() {
        L10n.setPreferredLocaleIdentifier(settings.appLanguage.localeIdentifier)
    }

    func migrateLocalizedSystemFolderNamesIfNeeded() {
        var mutatedAnyFolder = false

        for folder in folders {
            if folder.migrateLocalizedSystemNameMetadataIfNeeded() {
                mutatedAnyFolder = true
            }
        }

        guard mutatedAnyFolder else { return }
        save()
        refreshFolders()
    }
}
