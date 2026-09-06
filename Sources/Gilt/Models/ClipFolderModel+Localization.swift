import Foundation

extension ClipFolderModel {
    var localizedSystemFolderIdentity: LocalizedSystemFolderIdentity? {
        if let smartCategory {
            return .smartCategory(smartCategory)
        }

        if folderID == Self.clipboardID {
            return .clipboard
        }

        return nil
    }

    var displayName: String {
        guard let localizedSystemFolderIdentity else { return name }
        guard usesLocalizedSystemName == true else { return name }
        return localizedSystemFolderIdentity.localizedDisplayName
    }

    @discardableResult
    func migrateLocalizedSystemNameMetadataIfNeeded() -> Bool {
        guard let localizedSystemFolderIdentity,
              usesLocalizedSystemName == nil
        else {
            return false
        }

        // AI note:
        // We normalize built-in default names back to one stable stored fallback
        // before rendering a localized display label. That keeps language switching
        // deterministic and prevents the persisted store from getting "stuck" in
        // whichever locale happened to be active during an earlier migration.
        if localizedSystemFolderIdentity.matchesKnownDefaultName(name) {
            name = localizedSystemFolderIdentity.defaultStoredName
            usesLocalizedSystemName = true
        } else {
            usesLocalizedSystemName = false
        }

        return true
    }

    @discardableResult
    func applyDisplayNameOverride(_ candidateName: String) -> Bool {
        let trimmed = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let localizedSystemFolderIdentity else {
            let changed = name != trimmed
            name = trimmed
            return changed
        }

        if localizedSystemFolderIdentity.matchesKnownDefaultName(trimmed) {
            let changed = name != localizedSystemFolderIdentity.defaultStoredName
                || usesLocalizedSystemName != true
            name = localizedSystemFolderIdentity.defaultStoredName
            usesLocalizedSystemName = true
            return changed
        }

        let changed = name != trimmed || usesLocalizedSystemName != false
        name = trimmed
        usesLocalizedSystemName = false
        return changed
    }
}
