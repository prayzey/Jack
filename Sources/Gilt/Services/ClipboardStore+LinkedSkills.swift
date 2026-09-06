import CryptoKit
import Foundation

extension ClipboardStore {
    // MARK: - Linked Skill Folders

    /// Keep AI skill ingestion together so the main store file can focus on core clipboard flow.
    /// This is a file split only; behavior stays the same.

    /// Deterministic UUID for a provider's linked folder — survives re-scans.
    private func skillFolderID(for providerID: String) -> UUID {
        let namespace = "E1E2E3E4-AAAA-4000-8000-000000000000"
        let digest = SHA256.hash(data: Data((namespace + ":" + providerID).utf8))
        var bytes = Array(digest.prefix(16))
        // Mark the UUID as name-derived so it stays stable across launches.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func skillFolderIdentity(for providerID: String) -> (displayName: String, iconRaw: String)? {
        if let provider = AIProvider.provider(for: providerID) {
            return (
                displayName: provider.displayName,
                iconRaw: FolderIcon.symbol(provider.iconSymbol).rawValue
            )
        }

        guard providerID.hasPrefix("custom:") else { return nil }
        let path = String(providerID.dropFirst("custom:".count))
        let name = URL(fileURLWithPath: path).lastPathComponent.localizedCapitalized
        return (
            displayName: name,
            iconRaw: FolderIcon.symbol("folder").rawValue
        )
    }

    private func existingSkillFolders(
        displayName: String,
        iconRaw: String,
        canonicalFolderID: UUID
    ) -> [ClipFolderModel] {
        folders.filter { folder in
            if folder.folderID == canonicalFolderID {
                return true
            }

            guard folder.isSystem, folder.name == displayName else {
                return false
            }

            if folder.folderIconRaw == iconRaw {
                return true
            }

            return !folder.clips.isEmpty && folder.clips.allSatisfy { $0.sourceAppName == displayName }
        }
    }

    private func normalizeLinkedSkillSettings() {
        let uniqueProviders = Array(NSOrderedSet(array: settings.linkedSkillProviders)) as? [String] ?? []
        if uniqueProviders != settings.linkedSkillProviders {
            settings.linkedSkillProviders = uniqueProviders
        }

        let uniqueCustomPaths = Array(NSOrderedSet(array: settings.customSkillPaths)) as? [String] ?? []
        if uniqueCustomPaths != settings.customSkillPaths {
            settings.customSkillPaths = uniqueCustomPaths
        }
    }

    func reconcileLinkedSkillFolders() {
        normalizeLinkedSkillSettings()

        if settings.linkedSkillProviders.isEmpty && settings.customSkillPaths.isEmpty {
            return
        }

        let scanResults = Dictionary(
            uniqueKeysWithValues: SkillScanner.scanAll().map { ($0.provider.id, $0) }
        )

        for providerID in settings.linkedSkillProviders {
            guard let result = scanResults[providerID] else { continue }
            importSkillProvider(result)
        }

        for path in settings.customSkillPaths {
            let url = URL(fileURLWithPath: path)
            guard let result = SkillScanner.scanCustomDirectory(url) else { continue }
            importSkillProvider(result)
        }
    }

    /// Import skills from a scan result, creating a folder and populating it with skill clips.
    func importSkillProvider(_ result: ProviderScanResult) {
        let folderID = skillFolderID(for: result.provider.id)
        let iconRaw = FolderIcon.symbol(result.provider.iconSymbol).rawValue
        let matchingFolders = existingSkillFolders(
            displayName: result.provider.displayName,
            iconRaw: iconRaw,
            canonicalFolderID: folderID
        )

        // Create or reuse the folder
        let folder: ClipFolderModel
        if let existing = matchingFolders.first {
            folder = existing
            folder.folderID = folderID
            folder.name = result.provider.displayName
            folder.folderIconRaw = iconRaw
            folder.isSystem = true
            // Remove existing clips so we can re-import fresh
            for clip in Array(folder.clips) {
                modelContext.delete(clip)
            }
        } else {
            folder = ClipFolderModel(
                folderID: folderID,
                name: result.provider.displayName,
                folderIconRaw: iconRaw,
                colorRaw: result.provider.color,
                colorModeRaw: FolderColorMode.dotAndText.rawValue,
                isSystem: true,
                sortOrder: folders.count
            )
            modelContext.insert(folder)
        }

        for duplicate in matchingFolders.dropFirst() {
            for clip in Array(duplicate.clips) {
                modelContext.delete(clip)
            }
            modelContext.delete(duplicate)
        }

        // Import each skill file as a text clip
        for (index, skill) in result.skills.enumerated() {
            let preview = if skill.description.isEmpty {
                String(skill.content.prefix(200))
            } else {
                skill.description
            }

            let clip = ClipItemModel(
                clipID: UUID(),
                typeRaw: ClipType.text.rawValue,
                title: skill.name,
                previewText: preview,
                textValue: skill.content,
                sourceAppName: result.provider.displayName,
                createdAt: Date(),
                sortOrder: result.skills.count - index,
                folders: [folder]
            )
            modelContext.insert(clip)
        }

        // Track the linked provider
        if !settings.linkedSkillProviders.contains(result.provider.id) {
            settings.linkedSkillProviders.append(result.provider.id)
        }

        save()
        refreshFolders()
        refreshClips()
    }

    /// Remove a linked skill provider folder and all its clips.
    func unlinkSkillProvider(_ providerID: String) {
        let folderID = skillFolderID(for: providerID)
        let linkedFolders: [ClipFolderModel]
        if let identity = skillFolderIdentity(for: providerID) {
            linkedFolders = existingSkillFolders(
                displayName: identity.displayName,
                iconRaw: identity.iconRaw,
                canonicalFolderID: folderID
            )
        } else if let folder = folders.first(where: { $0.folderID == folderID }) {
            linkedFolders = [folder]
        } else {
            linkedFolders = []
        }

        guard !linkedFolders.isEmpty else { return }

        for folder in linkedFolders {
            for clip in Array(folder.clips) {
                modelContext.delete(clip)
            }
            modelContext.delete(folder)
        }

        settings.linkedSkillProviders.removeAll { $0 == providerID }
        // Drop any stale hidden-tab flag so a future re-link starts visible
        // (the deterministic folder ID is reused, so it would otherwise stay hidden).
        settings.setCustomFolderVisibility(true, for: folderID)
        save()
        refreshFolders()
        refreshClips()
    }

    /// Re-scan and refresh all linked skill provider folders.
    func rescanLinkedSkills(scanResults: [ProviderScanResult]? = nil) {
        let results = scanResults ?? SkillScanner.scanAll()
        for result in Self.linkedSkillResults(from: results, linkedProviderIDs: settings.linkedSkillProviders) {
            importSkillProvider(result)
        }

        for path in settings.customSkillPaths {
            let url = URL(fileURLWithPath: path)
            guard let result = SkillScanner.scanCustomDirectory(url) else { continue }
            importSkillProvider(result)
        }
    }

    static func linkedSkillResults(
        from scanResults: [ProviderScanResult],
        linkedProviderIDs: [String]
    ) -> [ProviderScanResult] {
        let resultsByProviderID = Dictionary(
            uniqueKeysWithValues: scanResults.map { ($0.provider.id, $0) }
        )
        return linkedProviderIDs.compactMap { resultsByProviderID[$0] }
    }

    /// Check if a provider is currently linked.
    func isProviderLinked(_ providerID: String) -> Bool {
        settings.linkedSkillProviders.contains(providerID)
    }

    /// Folder IDs for every linked skill provider (built-in providers + custom paths).
    /// Used to recognize and bulk-hide skill folders from the tab bar.
    func linkedSkillFolderIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        for providerID in settings.linkedSkillProviders {
            ids.insert(skillFolderID(for: providerID))
        }
        for path in settings.customSkillPaths {
            ids.insert(skillFolderID(for: "custom:\(path)"))
        }
        return ids
    }

    /// Whether a folder is a linked AI skill folder (as opposed to a custom or system folder).
    func isSkillFolder(_ folder: ClipFolderModel) -> Bool {
        linkedSkillFolderIDs().contains(folder.folderID)
    }

    /// Hide every linked skill folder from the tab bar in one action — they tend
    /// to pile up and clutter the bar. Folders stay linked and reappear via Settings.
    func hideAllSkillFolders() {
        for id in linkedSkillFolderIDs() {
            settings.setCustomFolderVisibility(false, for: id)
        }
    }

    /// Import a custom folder chosen by the user via folder picker.
    func importCustomSkillFolder(_ url: URL) {
        guard let result = SkillScanner.scanCustomDirectory(url) else { return }
        importSkillProvider(result)
        if !settings.customSkillPaths.contains(url.path) {
            settings.customSkillPaths.append(url.path)
        }
    }

    /// Remove a custom skill folder.
    func unlinkCustomSkillFolder(_ path: String) {
        let providerID = "custom:\(path)"
        unlinkSkillProvider(providerID)
        settings.customSkillPaths.removeAll { $0 == path }
    }
}
