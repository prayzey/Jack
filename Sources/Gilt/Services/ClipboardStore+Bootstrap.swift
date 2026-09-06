import Foundation
import ServiceManagement
import SwiftData

extension ClipboardStore {
    struct ModelContainerBootstrap {
        let container: ModelContainer
        let warningMessage: String?
    }

    // MARK: - Bootstrap

    static func quickElapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    func loadInitialData(appFolder: URL) -> Double {
        let dataLoadStart = DispatchTime.now()
        migrateFromJSONIfNeeded(appFolder: appFolder)
        loadSettings()
        loadNotesLibrary()
        migrateLegacyDefaultShortcutIfNeeded()
        refreshFolders()
        refreshClips()
        return Self.quickElapsedMs(since: dataLoadStart)
    }

    func performInitialMaintenance() -> Double {
        let setupStart = DispatchTime.now()
        ensureSystemFolder()
        ensureSystemNoteFolders()
        ensureAllSmartFolders()
        migrateLocalizedSystemFolderNamesIfNeeded()
        reconcileLinkedSkillFolders()
        migrateURLOnlyTextClipsToLinksIfNeeded()
        migrateFolderColorModeIfNeeded()
        pruneByRetention(force: true)
        rebuildSmartFolderCache()
        sortSmartFoldersOnce()
        removeDisabledSmartFolders()
        backfillContentHashes()
        rebuildContentHashIndex()
        scheduleLegacyImageHashMigration()
        startSensitiveExpiryTimer()
        startSessionHealthTimer()
        installWillTerminateObserver()
        return Self.quickElapsedMs(since: setupStart)
    }

    func syncLaunchAtLoginWithSystemState() {
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAtLoginError = nil
    }

    func registerHotKeyAndStartMonitor() {
        let registeredGlobalShortcut = GlobalHotKeyManager.shared.registerHotKey(shortcut: settings.globalShortcut)
        let registeredQuickNoteShortcut = GlobalHotKeyManager.shared.registerQuickNoteHotKey(shortcut: settings.quickNoteShortcut)
        // Command palette shortcut is best-effort: a conflict here should never
        // block the core paste/quick-note shortcuts from registering.
        _ = GlobalHotKeyManager.shared.registerCommandPaletteHotKey(shortcut: settings.commandPaletteShortcut)
        if registeredGlobalShortcut && registeredQuickNoteShortcut {
            globalShortcutError = nil
        } else if !registeredGlobalShortcut {
            globalShortcutError = "Shortcut is unavailable. Try a different combination."
        } else {
            globalShortcutError = "Quick Note shortcut is unavailable. Try a different combination."
        }
        TrackpadRevealGestureMonitor.shared.apply(settings: settings)
        monitor.start()
    }

    @discardableResult
    func fetchMissingLinkMetadataForExistingClips() -> [ClipItemModel] {
        let linksNeedingMetadata = clips.filter { $0.clipType == .link && !hasHydratedLinkMetadata($0) }
        for clip in linksNeedingMetadata {
            fetchLinkMetadataIfNeeded(for: clip)
        }
        return linksNeedingMetadata
    }

    static func makeModelContainer(schema: Schema, storeURL: URL, appFolder: URL) -> ModelContainerBootstrap {
        let config = ModelConfiguration(
            AppBrand.displayName,
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return ModelContainerBootstrap(container: container, warningMessage: nil)
        } catch {
            // Store open failed — attempt recovery.
        }

        let storeFilePrefix = AppBrand.legacyStoreFileName
        _ = backupStoreFiles(in: appFolder, withPrefix: storeFilePrefix)

        do {
            let freshContainer = try ModelContainer(for: schema, configurations: [config])
            let message = [
                "\(AppBrand.displayName) found a damaged clipboard database and moved the old store aside.",
                "A fresh database was created, so older saved history may be missing.",
                "New clips will save normally from this point on."
            ].joined(separator: " ")
            return ModelContainerBootstrap(container: freshContainer, warningMessage: message)
        } catch {
            // Fresh store creation also failed — fall back to in-memory.
        }

        do {
            let inMemoryConfig = ModelConfiguration(
                "\(AppBrand.displayName)-InMemory",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let inMemoryContainer = try ModelContainer(for: schema, configurations: [inMemoryConfig])
            let message = [
                "\(AppBrand.displayName) could not open or recreate its saved database, so it started in temporary memory-only mode.",
                "Your clipboard history will not persist after you quit until storage is fixed."
            ].joined(separator: " ")
            return ModelContainerBootstrap(container: inMemoryContainer, warningMessage: message)
        } catch {
            fatalError("Failed to initialize any ModelContainer (disk + in-memory): \(error)")
        }
    }

    static func backupStoreFiles(in appFolder: URL, withPrefix filePrefix: String) -> URL? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: appFolder, includingPropertiesForKeys: nil) else {
            return nil
        }

        let storeFiles = contents.filter { $0.lastPathComponent.hasPrefix(filePrefix) }
        guard !storeFiles.isEmpty else { return nil }

        let backupRoot = appFolder.appendingPathComponent("StoreBackups", isDirectory: true)
        let backupFolder = backupRoot.appendingPathComponent(storeBackupFolderName(), isDirectory: true)
        do {
            try fileManager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var movedAny = false
        for file in storeFiles {
            let destination = backupFolder.appendingPathComponent(file.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: file, to: destination)
                movedAny = true
            } catch {
                // Move failed — skip this file.
            }
        }

        return movedAny ? backupFolder : nil
    }

    static func storeBackupFolderName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Persistence

    func refreshClips() {
        let startedAt = DispatchTime.now()
        var descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = clipWindowSize
        clips = (try? modelContext.fetch(descriptor)) ?? []
        hasMoreClips = clips.count >= clipWindowSize
        highestSortOrder = clips.first?.sortOrder ?? 0
        pruneSuggestedActionCache()
        logPerf("refreshClips", startedAt: startedAt, details: "count=\(clips.count) windowed=\(clipWindowSize)")
    }

    /// Load the next page of clips beyond the current window.
    func loadMoreClips() {
        guard hasMoreClips else { return }
        guard let lastClip = clips.last else { return }
        let lastSortOrder = lastClip.sortOrder
        let lastDate = lastClip.createdAt
        let startedAt = DispatchTime.now()

        var descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate<ClipItemModel> { item in
                item.sortOrder < lastSortOrder
                || (item.sortOrder == lastSortOrder && item.createdAt < lastDate)
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = clipWindowSize
        let more = (try? modelContext.fetch(descriptor)) ?? []
        hasMoreClips = more.count >= clipWindowSize
        if !more.isEmpty {
            clips.append(contentsOf: more)
        }
        logPerf("loadMoreClips", startedAt: startedAt, details: "loaded=\(more.count) total=\(clips.count) hasMore=\(hasMoreClips)")
    }

    func refreshFolders() {
        let startedAt = DispatchTime.now()
        let descriptor = FetchDescriptor<ClipFolderModel>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        folders = (try? modelContext.fetch(descriptor)) ?? []
        logPerf("refreshFolders", startedAt: startedAt, details: "count=\(folders.count)")
    }

    func save() {
        let startedAt = DispatchTime.now()
        do {
            try modelContext.save()
            sessionSaveCount += 1
            logPerf("save", startedAt: startedAt)
        } catch {
            sessionSaveFailCount += 1
            logState("save FAILED: \(error)")
            Breadcrumb.record("save FAILED: \(error.localizedDescription)")
        }
    }

    func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return
        }
        isHydratingSettings = true
        defer { isHydratingSettings = false }
        settings = decoded
    }

    func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
