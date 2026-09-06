import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CryptoKit
import Foundation
import OSLog
import ServiceManagement
import SwiftData

@MainActor
final class ClipboardStore: ObservableObject {
    enum SeparatorMoveDirection: String {
        case left
        case right
    }

    struct TrialStartStorageResolution: Equatable {
        let effectiveTrialStartedAt: String?
        let shouldPersistToKeychain: Bool
        let shouldClearLegacySettingsValue: Bool
    }

    @Published var clips: [ClipItemModel] = [] {
        didSet {
            clearSearchBackfill()
            invalidateFilteredClips()
        }
    }
    @Published var folders: [ClipFolderModel] = []
    @Published var selectedFolderID: UUID = ClipFolderModel.clipboardID {
        didSet {
            guard selectedFolderID != oldValue else { return }
            logState("selectedFolderID \(oldValue.uuidString) -> \(selectedFolderID.uuidString)")
            previewingClipID = nil
            selectedClipIDs.removeAll()
            clearSearchBackfill()
            invalidateFilteredClips()
        }
    }
    @Published var searchText = "" {
        didSet {
            if !searchText.isEmpty && oldValue.isEmpty { Analytics.searchUsed() }
            scheduleSearchInvalidation()
        }
    }
    @Published var selectedClipIDs: Set<UUID> = []
    /// Cached filtered + sorted clips — invalidated when clips, selectedFolderID, or searchText change.
    @Published private(set) var filteredClips: [ClipItemModel] = []
    /// Clips + separators merged for the current folder, ready for strip rendering.
    @Published private(set) var stripItems: [ClipStripItem] = []
    /// Stable ID list for `stripItems`, recomputed only when `stripItems` changes.
    /// Views use this as the value for `.animation(value:)` so the strip animation
    /// doesn't allocate a fresh `[UUID]` on every SwiftUI body evaluation.
    @Published private(set) var stripItemIDs: [UUID] = []
    @Published var previewingClipID: UUID?
    /// Clip currently being edited inline (directly in the card). Nil = no inline editing.
    @Published var inlineEditingClipID: UUID?
    @Published var notes: [NoteItem] = []
    @Published var noteFolders: [NoteFolder] = []
    @Published var selectedNoteFolderID: UUID = NoteFolder.scratchpadsID
    @Published var workspaceSession = WorkspaceSession()
    @Published var workspaceSearchText = ""
    @Published var quickNoteActiveNoteID: UUID?

    // MARK: - On-device AI (transient UI state)
    /// Clip IDs with an AI action in flight — cards show a spinner while set.
    @Published var aiBusyClipIDs: Set<UUID> = []
    /// Note IDs with an AI action in flight — the note's AI control shows a spinner while set.
    @Published var aiBusyNoteIDs: Set<UUID> = []
    /// True while a natural-language search query is being interpreted by the model.
    @Published var aiSearchInterpreting = false
    /// Transient confirmation / error banner shown after an AI action. Auto-dismisses.
    @Published var aiToast: AIToast?

    // Double-tap detection (not published — UI timing state only)
    var lastCardTapTime: Date?
    var lastCardTapID: UUID?
    @Published var globalShortcutError: String?
    @Published var launchAtLoginError: String?
    /// Live opacity override during slider drag — avoids disk writes on every frame
    @Published var liveBackgroundOpacity: Double?
    let wallpaperPreview = WallpaperPreviewState()
    let quickNoteWallpaperPreview = WallpaperPreviewState()
    let workspaceWallpaperPreview = WallpaperPreviewState()

    /// Lifetime dictation + meeting stats. Owned here so the workspace views
    /// can observe it through the shared `ClipboardStore` env object without
    /// every view having to wire up its own `@StateObject`.
    let transcriptionStatsStore = TranscriptionStatsStore()

    // MARK: - Licensing
    @Published var licenseState: LicenseState = .unknown
    @Published var trialState: TrialState = .notStarted
    @Published var isLicenseBusy = false
    @Published var licenseErrorMessage: String?
    @Published var settings = AppSettings() {
        didSet {
            logSettingsDiff(previous: oldValue, current: settings)
            applyPreferredAppLanguage()
            guard Self.shouldApplySettingsSideEffects(isHydratingSettings: isHydratingSettings) else {
                return
            }
            persistSettings()
            if oldValue.enableImageTextRecognition && !settings.enableImageTextRecognition {
                cancelAllImageOCRTasks()
            }
            if Self.didEnableImageOCR(previous: oldValue, current: settings) {
                scheduleOCRForExistingImages(forceRefresh: false)
            } else if Self.didChangeImageOCRConfiguration(previous: oldValue, current: settings) {
                scheduleOCRForExistingImages(forceRefresh: true)
            }
            if oldValue.smartCategories != settings.smartCategories {
                reconcileSmartCategorySettings(previous: oldValue.smartCategories, current: settings.smartCategories)
                if Self.didChangeSensitiveHandling(previous: oldValue.smartCategories, current: settings.smartCategories) {
                    applySensitiveExpiryPolicyToExistingClips()
                }
            }
            if oldValue.viewMode != settings.viewMode {
                Analytics.viewModeSwitched(to: settings.viewMode.rawValue)
                AppWindowManager.shared.switchMode(to: settings.viewMode, store: self)
            }
            if oldValue.drawerSide != settings.drawerSide {
                AppWindowManager.shared.setDrawerSide(settings.drawerSide, store: self)
            }
            if oldValue.hideFromDock != settings.hideFromDock {
                NSApp.setActivationPolicy(settings.hideFromDock ? .accessory : .regular)
            }
            if oldValue.trackpadRevealBottomEdgeSwipeEnabled != settings.trackpadRevealBottomEdgeSwipeEnabled
                || oldValue.trackpadRevealBottomCenterSwipeEnabled != settings.trackpadRevealBottomCenterSwipeEnabled {
                TrackpadRevealGestureMonitor.shared.apply(settings: settings)
            }
            if oldValue.hiddenCustomFolderIDs != settings.hiddenCustomFolderIDs {
                reconcileFolderSelectionWithVisibility()
            }
            if oldValue.jackSettings.presenceMode != settings.jackSettings.presenceMode
                || oldValue.jackSettings.look != settings.jackSettings.look {
                jackPresenceController.apply(
                    presenceMode: settings.jackSettings.presenceMode,
                    look: settings.jackSettings.look
                )
            }
        }
    }

    let modelContainer: ModelContainer
    let modelContext: ModelContext
    /// Per-word corrections Jack has learned by watching the user edit
    /// pasted dictations. Read on every polish-mode dictation so the
    /// same mistake doesn't keep happening.
    let correctionStore: CorrectionStore
    let settingsKey = "GiltAppSettings"
    let legacyDefaultShortcutMigrationKey = "GiltLegacyDefaultShortcutMigrated"
    let notesFileURL: URL
    let noteImageAttachmentsRoot: URL

    let stateLogger = Logger(subsystem: AppBrand.logSubsystem, category: "StoreState")
    let sessionLogger = Logger(subsystem: AppBrand.logSubsystem, category: "SessionHealth")
    let stateDebugLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"
    var isHydratingSettings = false
    private var isReconcilingLaunchAtLogin = false
    var activeSmartFolderIDs: Set<UUID> = []
    var sensitiveExpiryTimer: Timer?
    var sessionHealthTimer: Timer?
    let appIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        return cache
    }()
    var missingIconBundleIDs: Set<String> = []
    var suggestedActionCache: [UUID: SuggestedActionCacheEntry] = [:]
    var highestSortOrder: Int = 0
    /// Hash → clipID index for O(1) duplicate detection during ingest.
    var contentHashIndex: [String: UUID] = [:]
    private var searchInvalidationWorkItem: DispatchWorkItem?
    private var searchBackfillWorkItem: DispatchWorkItem?
    private var searchBackfillQuery = ""
    private var searchBackfillFolderID: UUID?
    private var searchBackfillResults: [ClipItemModel] = []
    /// Folder-scoped clips cached across search keystrokes. Folder scoping walks
    /// SwiftData relationships (and materializes the full folder contents for
    /// non-Clipboard folders), so recomputing it per keystroke made typing in
    /// large folders sluggish. Cleared on any non-search invalidation.
    private var folderScopeCache: (folderID: UUID, clips: [ClipItemModel])?
    var pendingMetadataSaveWorkItem: DispatchWorkItem?
    var pendingMetadataSaveCount = 0
    var inFlightLinkMetadataClipIDs: Set<UUID> = []
    var inFlightOCRTasks: [UUID: Task<Void, Never>] = [:]
    var pendingIngestSaveWorkItem: DispatchWorkItem?
    var pendingIngestSaveCount = 0
    var pendingIngestBatchStartedAt: DispatchTime?
    var pendingNotesPersistWorkItem: DispatchWorkItem?
    var hasShownAccessibilityPasteAlert = false
    var willTerminateObserver: NSObjectProtocol?
    var lastRetentionPruneAt: Date?
    var pendingPersistenceIssueMessage: String?
    var hasPresentedPersistenceIssue = false
    var trialRefreshTimer: Timer?
    var mirroredNoteClipIDs: [UUID: UUID] = [:]
    /// noteID -> vault sync bookkeeping (Obsidian sync). Loaded/saved with the
    /// notes library; see ClipboardStore+VaultSync.
    var vaultSyncRecords: [UUID: VaultSyncRecord] = [:]
    /// Ordered ids of the notes that are Kanban boards (sidebar order).
    var kanbanBoardNoteIDs: [UUID] = []
    /// Memoized task/column extraction per board note (see +Notes). Board
    /// tasks live inside the note's markdown, so every read used to re-parse
    /// the whole body — and Kanban re-reads once per column per body pass,
    /// on every store change AND every drag-preview tick. Keyed by noteID;
    /// entries revalidate against the note's current body string (COW makes
    /// the unchanged-body comparison effectively free).
    var boardParseCache: [UUID: BoardParseCacheEntry] = [:]
    /// Pending debounced vault sync work, keyed by noteID (see +VaultSync).
    var pendingVaultSyncNoteIDs: Set<UUID> = []
    var pendingVaultSyncWorkItem: DispatchWorkItem?
    /// FSEvents watcher for the active vault (Phase 2). nil when no vault chosen.
    var vaultWatcher: VaultWatcher?
    /// Guards reconcile from overlapping itself while a pass is in flight.
    var isReconcilingVault = false
    var legacyImageHashMigrationTask: Task<Void, Never>?
    let perfSlowOperationThresholdMs = 6.0
    let retentionPruneThrottleSeconds: TimeInterval = 30
    let maxSuggestedActionCacheSize = 500
    /// Pasteboard changeCount for Jack's own most recent clipboard write.
    /// Matching that exact changeCount is safe to ignore; any newer count must be ingested.
    var suppressedPasteboardChangeCount: Int?

    // MARK: - Session Health Tracking
    let sessionStartTime = Date()
    var sessionIngestCount = 0
    var sessionIngestByType: [String: Int] = [:]
    var sessionPasteCount = 0
    var sessionPasteSuccessCount = 0
    var sessionPasteFailCount = 0
    var sessionCopyCount = 0
    var sessionSearchCount = 0
    var sessionDeleteCount = 0
    var sessionSaveCount = 0
    var sessionSaveFailCount = 0

    lazy var monitor = ClipboardMonitor { [weak self] captured, changeCount, hash in
        self?.ingest(captured: captured, changeCount: changeCount, precomputedHash: hash)
    }

    /// Jack's chat thread + Qwen lifecycle. Created with the same model cache
    /// directory the meeting summary pipeline uses so we never download the
    /// multi-GB model twice.
    let jackChatStore: JackChatStore = JackChatStore(
        cacheDirectory: AppSupportLocator
            .giltDirectory()
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("qwen3.5-4b-q4", isDirectory: true)
    )

    /// Owns the on-screen Jack character and parks / hides him based on
    /// `settings.jackSettings`. Lazy because it captures `self` for the
    /// reminders + default-tab providers the click popover reads.
    lazy var jackPresenceController = JackPresenceController(
        chatStore: jackChatStore,
        remindersProvider: { [weak self] in self?.settings.pulseReminders ?? [] },
        defaultTabProvider: { [weak self] in self?.settings.jackSettings.defaultPopoverTab ?? .chat },
        onTurnOff: { [weak self] in self?.settings.jackSettings.presenceMode = .off },
        addReminder: { [weak self] reminder in self?.addPulseReminder(reminder) },
        deleteReminder: { [weak self] id in self?.removePulseReminder(id) }
    )

    var transcriptionStatsCancellable: AnyCancellable?

    struct SuggestedActionCacheEntry {
        let signature: Int
        let actions: [SuggestedAction]
    }

    // MARK: - Init

    init() {
        let initStart = DispatchTime.now()

        let appFolder = AppSupportLocator.giltDirectory()
        notesFileURL = AppSupportLocator.notesFileURL(in: appFolder)
        noteImageAttachmentsRoot = AppSupportLocator.noteImageAttachmentsDirectory(in: appFolder)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: noteImageAttachmentsRoot,
            withIntermediateDirectories: true
        )

        let containerStart = DispatchTime.now()
        // FactModel has no live feature behind it (the MemoryStore service was
        // removed as dead code), but it must stay in the Schema: dropping an
        // entity changes the store schema and existing Gilt.store files would
        // need a migration to open.
        let schema = Schema([ClipItemModel.self, ClipFolderModel.self, FolderSeparatorModel.self, FactModel.self, LearnedCorrectionModel.self])
        let storeURL = AppSupportLocator.storeFileURL()
        let containerResult = Self.makeModelContainer(schema: schema, storeURL: storeURL, appFolder: appFolder)
        modelContainer = containerResult.container
        pendingPersistenceIssueMessage = containerResult.warningMessage
        modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        correctionStore = CorrectionStore(modelContainer: modelContainer)
        let containerMs = Self.quickElapsedMs(since: containerStart)

        let dataLoadMs = loadInitialData(appFolder: appFolder)
        let setupMs = performInitialMaintenance()
        syncLaunchAtLoginWithSystemState()
        registerHotKeyAndStartMonitor()
        let linksNeedingMetadata = fetchMissingLinkMetadataForExistingClips()

        // Populate cached filteredClips (didSet doesn't fire during init)
        invalidateFilteredClips()
        bootstrapLicenseState()
        wireTranscriptionStats()

        let totalMs = Self.quickElapsedMs(since: initStart)
        logState(
            "init clips=\(clips.count) folders=\(folders.count) "
                + "retention=\(settings.historyRetention.rawValue) "
                + "launchAtLogin=\(settings.launchAtLogin)"
        )
        logState(
            "startup container=\(String(format: "%.1f", containerMs))ms "
                + "dataLoad=\(String(format: "%.1f", dataLoadMs))ms "
                + "setup=\(String(format: "%.1f", setupMs))ms "
                + "total=\(String(format: "%.1f", totalMs))ms "
                + "pendingLinks=\(linksNeedingMetadata.count)"
        )
    }

    /// Apply the persisted Jack presence once at launch. Settings are hydrated
    /// with `isHydratingSettings = true`, so the `settings.didSet` side effects
    /// (including the presence apply) are skipped during load — this is the
    /// catch-up call that parks an "Always on" Jack on startup. Driven from a
    /// deferred main-actor task in the app entry point so `NSApp` / screens are
    /// ready before we ask for dock geometry.
    func applyInitialJackPresence() {
        jackPresenceController.apply(
            presenceMode: settings.jackSettings.presenceMode,
            look: settings.jackSettings.look
        )
    }

    let clipWindowSize = 500
    var hasMoreClips = true

    func migrateLegacyDefaultShortcutIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: legacyDefaultShortcutMigrationKey) else { return }
        defer {
            UserDefaults.standard.set(true, forKey: legacyDefaultShortcutMigrationKey)
        }
        guard settings.globalShortcut == .legacyDefault || settings.globalShortcut == .previousDefault else { return }
        settings.globalShortcut = .default
        logState("Migrated default shortcut to product default -> \(settings.globalShortcut.displayString)")
    }

    // MARK: - System Folder

    func ensureSystemFolder() {
        let hasSystem = folders.contains { $0.folderID == ClipFolderModel.clipboardID }
        if !hasSystem {
            let systemFolder = ClipFolderModel(
                folderID: ClipFolderModel.clipboardID,
                name: "Clipboard",
                colorRaw: FolderColorToken.white.rawValue,
                colorModeRaw: FolderColorMode.fill.rawValue,
                fillColorRaw: "grad:#5C6070,#8B909E,135.0",
                isSystem: true,
                sortOrder: 0,
                usesLocalizedSystemName: true
            )
            modelContext.insert(systemFolder)
            save()
            refreshFolders()
        }

        if !visibleFolders.contains(where: { $0.folderID == selectedFolderID }) {
            selectedFolderID = visibleFolders.first?.folderID ?? ClipFolderModel.clipboardID
        }
    }

    /// Create all enabled smart folders eagerly so they appear in the tab bar on first launch.
    func ensureAllSmartFolders() {
        var created = false
        for category in SmartCategory.allCases where settings.smartCategories.isEnabled(category) {
            let alreadyExists = folders.contains { $0.smartCategoryRaw == category.rawValue }
            if !alreadyExists {
                let folder = ClipFolderModel(
                    folderID: category.folderID,
                    name: category.folderName,
                    colorRaw: category.folderColor.rawValue,
                    colorModeRaw: FolderColorMode.fill.rawValue,
                    fillColorRaw: category.defaultFillGradient,
                    isSystem: true,
                    sortOrder: (folders.map(\.sortOrder).max() ?? 0) + 1,
                    smartCategoryRaw: category.rawValue,
                    usesLocalizedSystemName: true
                )
                modelContext.insert(folder)
                created = true
                logState("eagerly created smart folder: \(category.folderName)")
            }
        }
        if created {
            save()
            refreshFolders()
        }
    }

    // MARK: - Migration from state.json

    func migrateFromJSONIfNeeded(appFolder: URL) {
        let jsonURL = appFolder.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        // Check if we already have data — skip if already migrated
        let existingClips = (try? modelContext.fetchCount(FetchDescriptor<ClipItemModel>())) ?? 0
        let existingFolders = (try? modelContext.fetchCount(FetchDescriptor<ClipFolderModel>())) ?? 0
        if existingClips > 0 || existingFolders > 0 {
            logState("migration skipped — SwiftData already has data (clips=\(existingClips) folders=\(existingFolders))")
            return
        }

        guard let data = try? Data(contentsOf: jsonURL),
              let legacy = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            logState("migration FAILED — could not decode state.json")
            return
        }

        logState("migration starting — clips=\(legacy.clips.count) folders=\(legacy.folders.count)")

        // Create folder models first, preserving UUIDs
        var foldersByID: [UUID: ClipFolderModel] = [:]
        for (index, legacyFolder) in legacy.folders.enumerated() {
            let folderModel = ClipFolderModel(
                folderID: legacyFolder.id,
                name: legacyFolder.name,
                colorRaw: legacyFolder.color.rawValue,
                colorModeRaw: legacyFolder.colorMode.rawValue,
                fillColorRaw: legacyFolder.fillColor.rawValue,
                textColorModeRaw: legacyFolder.textColorMode.rawValue,
                customTextColorRaw: legacyFolder.customTextColor?.rawValue,
                isSystem: legacyFolder.isSystem,
                sortOrder: index
            )
            modelContext.insert(folderModel)
            foldersByID[legacyFolder.id] = folderModel
        }

        // Create clip models, linking to folders
        for legacyClip in legacy.clips {
            let imageData: Data?
            if let base64 = legacyClip.imagePNGBase64 {
                imageData = Data(base64Encoded: base64)
            } else {
                imageData = nil
            }

            let clipFolders = legacyClip.folderIDs.compactMap { foldersByID[$0] }

            let clipModel = ClipItemModel(
                clipID: legacyClip.id,
                typeRaw: legacyClip.type.rawValue,
                title: legacyClip.title,
                previewText: legacyClip.previewText,
                textValue: legacyClip.textValue,
                urlValue: legacyClip.urlValue,
                imageData: imageData,
                sourceAppName: legacyClip.sourceAppName,
                sourceBundleID: legacyClip.sourceBundleID,
                createdAt: legacyClip.createdAt,
                folders: clipFolders
            )
            modelContext.insert(clipModel)
        }

        // Migrate settings to UserDefaults
        if let settingsData = try? JSONEncoder().encode(legacy.settings) {
            UserDefaults.standard.set(settingsData, forKey: settingsKey)
        }

        save()

        // Rename old file as safety net
        let migratedURL = appFolder.appendingPathComponent("state.json.migrated")
        try? FileManager.default.moveItem(at: jsonURL, to: migratedURL)

        logState("migration complete — renamed state.json to state.json.migrated")
    }

    // MARK: - Folder Color Mode Migration

    func migrateFolderColorModeIfNeeded() {
        let migrationKey = "AuricFolderColorModeMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        var changed = false
        for folder in folders where folder.colorModeRaw == FolderColorMode.dot.rawValue {
            folder.colorModeRaw = FolderColorMode.dotAndText.rawValue
            changed = true
        }
        if changed {
            save()
            refreshFolders()
            logState("migrated folder color modes from .dot to .dotAndText")
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Derived State

    var selectedFolder: ClipFolderModel? {
        folders.first(where: { $0.folderID == selectedFolderID })
    }

    /// Recompute the cached filteredClips from current state.
    func invalidateFilteredClips(reason: String = "state") {
        if reason != "search" && reason != "search-db" {
            searchInvalidationWorkItem?.cancel()
            searchInvalidationWorkItem = nil
            searchBackfillWorkItem?.cancel()
            searchBackfillWorkItem = nil
            // Any non-search change (clips mutated, folder switched, reorder…)
            // may alter folder membership, so the scoped cache must rebuild.
            folderScopeCache = nil
        }
        let startedAt = DispatchTime.now()
        filteredClips = computeFilteredClips()
        stripItems = computeStripItems()
        stripItemIDs = stripItems.map(\.id)
        logPerf(
            "invalidateFilteredClips",
            startedAt: startedAt,
            details: "reason=\(reason) queryLen=\(searchText.count) results=\(filteredClips.count)",
            thresholdMs: 2.5
        )
    }

    private func scheduleSearchInvalidation() {
        sessionSearchCount += 1
        searchInvalidationWorkItem?.cancel()
        searchBackfillWorkItem?.cancel()
        // Deliberately keep the previous backfill results: while the fresh DB
        // backfill is pending, computeFilteredClips re-checks them against the
        // new query so matching extras stay visible instead of vanishing for
        // 180ms and popping back in. They ARE cleared when clips or the folder
        // change (didSet paths) so stale/deleted models can never linger.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.invalidateFilteredClips(reason: "search")
            self.scheduleSearchBackfillIfNeeded()
        }
        searchInvalidationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
    }

    private func computeFilteredClips() -> [ClipItemModel] {
        let visibleClips: [ClipItemModel]
        if let selectedFolder {
            let scoped: [ClipItemModel]
            if let cache = folderScopeCache, cache.folderID == selectedFolderID {
                scoped = cache.clips
            } else {
                scoped = ClipSearchFilter.folderScopedClips(
                    windowClips: clips,
                    selectedFolder: selectedFolder
                )
                folderScopeCache = (selectedFolderID, scoped)
            }
            visibleClips = ClipSearchFilter.textFilter(clips: scoped, searchText: searchText)
        } else {
            // No resolved folder (transient during folder reloads): unscoped
            // window, matching visibleClips' historical behavior. Backfill can
            // still be scheduled here (Clipboard ID fallback), so fall through
            // to the merge rather than returning early.
            visibleClips = ClipSearchFilter.sort(clips)
        }

        guard !searchBackfillResults.isEmpty, searchBackfillFolderID == selectedFolderID else {
            return visibleClips
        }
        // Exact query match: the landed backfill applies as-is. Query changed
        // since it landed: keep extras that still match the new query until the
        // fresh backfill replaces them, so the result list doesn't
        // shrink-then-regrow on every typed character.
        let extras = shouldUseSearchBackfillResults
            ? searchBackfillResults
            : ClipSearchFilter.provisionalBackfillMatches(searchBackfillResults, query: searchText)
        return ClipSearchFilter.mergeBackfillResults(
            visibleClips: visibleClips,
            backfillClips: extras,
            selectedFolderID: selectedFolderID
        )
    }

    private var shouldUseSearchBackfillResults: Bool {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return searchBackfillQuery == searchText
            && searchBackfillFolderID == selectedFolderID
    }

    private func scheduleSearchBackfillIfNeeded() {
        guard shouldRunSearchBackfill else { return }
        let query = searchText
        let folderID = selectedFolderID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let dbResults = self.searchClipsFromDatabase(query: query, folderID: folderID)
            guard self.searchText == query, self.selectedFolderID == folderID else { return }
            self.searchBackfillQuery = query
            self.searchBackfillFolderID = folderID
            // Folder-scope and sort ONCE at land time. These results are re-read
            // on every subsequent keystroke (provisional matching), so the
            // relationship walk must not happen on the typing path.
            self.searchBackfillResults = ClipSearchFilter.filter(
                clips: dbResults,
                selectedFolderID: folderID,
                searchText: ""
            )
            self.invalidateFilteredClips(reason: "search-db")
        }
        searchBackfillWorkItem = workItem
        // Keep direct typing responsive by letting the quick in-memory filter land first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private var shouldRunSearchBackfill: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isClipboardFolder = selectedFolder?.isClipboardFolder ?? (selectedFolderID == ClipFolderModel.clipboardID)
        return isClipboardFolder && !trimmed.isEmpty && hasMoreClips
    }

    private func clearSearchBackfill() {
        searchBackfillQuery = ""
        searchBackfillFolderID = nil
        searchBackfillResults.removeAll(keepingCapacity: true)
    }

    /// Search SwiftData directly for clips matching a text query beyond the in-memory window.
    private func searchClipsFromDatabase(query: String, folderID: UUID) -> [ClipItemModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        // SwiftData #Predicate supports localizedStandardContains for case-insensitive search.
        // NOTE: ClipSearchFilter.provisionalBackfillMatches mirrors this exact field set
        // (previewText, sourceAppName). If this predicate gains or loses a field, update
        // that function too, or provisional results will churn while backfill is pending.
        var descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate<ClipItemModel> { item in
                item.previewText.localizedStandardContains(trimmed)
                || item.sourceAppName.localizedStandardContains(trimmed)
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func moveFolder(_ draggedID: UUID, relativeTo targetID: UUID, placement: StripReorderPlacement) {
        guard draggedID != targetID else { return }
        let currentOrder = folders.map(\.folderID)
        guard let reorderedIDs = reorderedStripIDs(
            ids: currentOrder,
            draggedID: draggedID,
            targetID: targetID,
            placement: placement
        ) else {
            return
        }

        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.folderID, $0) })
        let reordered = reorderedIDs.compactMap { foldersByID[$0] }
        guard reordered.count == folders.count else { return }

        for (i, folder) in reordered.enumerated() {
            folder.sortOrder = i
        }
        save()
        refreshFolders()
        logState(
            "moveFolder \(draggedID.uuidString.prefix(8)) "
                + "\(placement == .before ? "before" : "after") "
                + "\(targetID.uuidString.prefix(8))"
        )
    }

    func deleteFolder(id: UUID) {
        guard let folder = folders.first(where: { $0.folderID == id }),
              folder.isSystem == false,
              folder.isSmartFolder == false else { return }

        settings.setCustomFolderVisibility(true, for: id)

        // Remove folder from all clips' relationship
        for clip in folder.clips {
            clip.folders.removeAll { $0.folderID == id }
        }

        modelContext.delete(folder)
        save()
        refreshFolders()
        refreshClips()

        if selectedFolderID == id {
            selectedFolderID = visibleFolders.first?.folderID ?? ClipFolderModel.clipboardID
        }
    }

    func setPinned(_ pinned: Bool, for clipIDs: Set<UUID>) {
        guard !clipIDs.isEmpty else { return }
        let targetClips = clips.filter { clipIDs.contains($0.clipID) }
        guard !targetClips.isEmpty else { return }

        var nextSortOrder = nextSortOrder(forPinned: pinned)
        var changedCount = 0
        for clip in targetClips where clip.isPinned != pinned {
            clip.isPinned = pinned
            clip.sortOrder = nextSortOrder
            nextSortOrder += 1
            changedCount += 1
        }

        guard changedCount > 0 else { return }
        save()
        refreshClips()
        logState("setPinned pinned=\(pinned) count=\(changedCount)")
    }

    // MARK: - Clip Operations

    func addClip(_ clipID: UUID, to folderID: UUID) {
        guard let clip = clipForFolderAssignment(clipID),
              let folder = folders.first(where: { $0.folderID == folderID }) else { return }
        if !clip.folders.contains(where: { $0.folderID == folderID }) {
            clip.folders.append(folder)
            save()
            refreshClips()
        }
    }

    private func clipForFolderAssignment(_ clipID: UUID) -> ClipItemModel? {
        if let clip = clips.first(where: { $0.clipID == clipID }) {
            return clip
        }

        var descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate<ClipItemModel> { item in
                item.clipID == clipID
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func eraseHistory() {
        cancelAllImageOCRTasks()
        for clip in clips {
            modelContext.delete(clip)
        }
        contentHashIndex.removeAll()
        save()
        refreshClips()
    }

    /// Delete specific clips by ID. Removes from all folders and SwiftData.
    /// Auto-selects the next clip so the user can chain deletes without re-clicking.
    func deleteClips(_ clipIDs: Set<UUID>) {
        guard !clipIDs.isEmpty else { return }
        Analytics.clipDeleted()

        // Before deleting, find the best "next" clip to auto-select.
        // Use the lowest index among the clips being deleted, then pick whatever
        // lands at that position after removal (i.e. the clip that was to the right).
        let visible = filteredClips
        let deletedIndices = visible.enumerated()
            .filter { clipIDs.contains($0.element.clipID) }
            .map(\.offset)
        let anchorIndex = deletedIndices.min() ?? 0
        let survivorIDs = visible
            .filter { !clipIDs.contains($0.clipID) }
            .map(\.clipID)

        let toDelete = clips.filter { clipIDs.contains($0.clipID) }
        guard !toDelete.isEmpty else { return }
        sessionDeleteCount += toDelete.count
        Breadcrumb.record("deleteClips count=\(toDelete.count) totalDeleted=\(sessionDeleteCount)")
        for clip in toDelete {
            cancelImageOCR(for: clip.clipID)
            removeClipFromHashIndex(clip)
            clip.folders.removeAll()
            modelContext.delete(clip)
        }
        save()
        refreshClips()

        // Auto-select: pick the clip now at the same position, or the last one if we deleted from the end
        if !survivorIDs.isEmpty {
            let nextIndex = min(anchorIndex, survivorIDs.count - 1)
            selectedClipIDs = [survivorIDs[nextIndex]]
        } else {
            selectedClipIDs.removeAll()
        }

        logState("deleteClips removed \(toDelete.count) clips, auto-selected next")
    }

    /// Delete a single clip by ID.
    func deleteClip(_ clipID: UUID) {
        deleteClips([clipID])
    }

    /// Remove a clip from a specific folder (but keep it in others).
    /// If the clip has no remaining folders, delete it entirely.
    func removeClipFromFolder(_ clipID: UUID, folderID: UUID) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        clip.folders.removeAll { $0.folderID == folderID }
        if clip.folders.isEmpty {
            cancelImageOCR(for: clip.clipID)
            removeClipFromHashIndex(clip)
            modelContext.delete(clip)
        }
        save()
        refreshClips()
        logState("removeClipFromFolder clip=\(clipID) folder=\(folderID)")
    }

    /// Remove all clips from a folder. Clips that belong to other folders are unlinked;
    /// clips that only belong to this folder are deleted entirely.
    func clearFolder(id folderID: UUID) {
        guard let folder = folders.first(where: { $0.folderID == folderID }) else { return }
        let clipsInFolder = clips.filter { $0.folders.contains(where: { $0.folderID == folderID }) }
        guard !clipsInFolder.isEmpty else { return }

        for clip in clipsInFolder {
            clip.folders.removeAll { $0.folderID == folderID }
            if clip.folders.isEmpty {
                cancelImageOCR(for: clip.clipID)
                removeClipFromHashIndex(clip)
                modelContext.delete(clip)
            }
        }
        selectedClipIDs.removeAll()
        save()
        refreshClips()
        logState("clearFolder \(folder.name) removed \(clipsInFolder.count) clips")
    }

    func setRetention(_ retention: HistoryRetention) {
        settings.historyRetention = retention
        pruneByRetention(force: true)
    }

    func setGlobalShortcut(_ shortcut: GlobalShortcut) {
        let startNanoseconds = DispatchTime.now().uptimeNanoseconds
        let previous = settings.globalShortcut
        guard shortcut != previous else { return }
        logState("setGlobalShortcut requested \(previous.displayString) -> \(shortcut.displayString)")

        if GlobalHotKeyManager.shared.registerHotKey(shortcut: shortcut) {
            settings.globalShortcut = shortcut
            globalShortcutError = nil
            logState("setGlobalShortcut success active=\(shortcut.displayString)")
        } else {
            _ = GlobalHotKeyManager.shared.registerHotKey(shortcut: previous)
            globalShortcutError = "Shortcut is unavailable. Try a different combination."
            logState("setGlobalShortcut failed requested=\(shortcut.displayString) restored=\(previous.displayString)")
        }

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNanoseconds) / 1_000_000
        logState("setGlobalShortcut duration=\(String(format: "%.2f", elapsedMs))ms")
    }

    func setQuickNoteShortcut(_ shortcut: GlobalShortcut) {
        let previous = settings.quickNoteShortcut
        guard shortcut != previous else { return }
        logState("setQuickNoteShortcut requested \(previous.displayString) -> \(shortcut.displayString)")

        if GlobalHotKeyManager.shared.registerQuickNoteHotKey(shortcut: shortcut) {
            settings.quickNoteShortcut = shortcut
            logState("setQuickNoteShortcut success active=\(shortcut.displayString)")
        } else {
            _ = GlobalHotKeyManager.shared.registerQuickNoteHotKey(shortcut: previous)
            globalShortcutError = "Quick Note shortcut is unavailable. Try a different combination."
            logState("setQuickNoteShortcut failed requested=\(shortcut.displayString) restored=\(previous.displayString)")
        }
    }

    func setCommandPaletteShortcut(_ shortcut: GlobalShortcut) {
        let previous = settings.commandPaletteShortcut
        guard shortcut != previous else { return }
        logState("setCommandPaletteShortcut requested \(previous.displayString) -> \(shortcut.displayString)")

        if GlobalHotKeyManager.shared.registerCommandPaletteHotKey(shortcut: shortcut) {
            settings.commandPaletteShortcut = shortcut
            logState("setCommandPaletteShortcut success active=\(shortcut.displayString)")
        } else {
            _ = GlobalHotKeyManager.shared.registerCommandPaletteHotKey(shortcut: previous)
            globalShortcutError = "Command palette shortcut is unavailable. Try a different combination."
            logState("setCommandPaletteShortcut failed requested=\(shortcut.displayString) restored=\(previous.displayString)")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard isReconcilingLaunchAtLogin == false else {
            logState("setLaunchAtLogin ignored (re-entrant) requested=\(enabled)")
            return
        }
        isReconcilingLaunchAtLogin = true
        defer { isReconcilingLaunchAtLogin = false }
        logState("setLaunchAtLogin requested=\(enabled)")
        launchAtLoginError = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
            logState("setLaunchAtLogin success enabled=\(enabled)")
        } catch {
            let message = "Failed to \(enabled ? "register" : "unregister"): \(error)"
            logState("setLaunchAtLogin \(message)")
            launchAtLoginError = Self.launchAtLoginFailureMessage(
                enabling: enabled,
                isAppBundle: Self.isMainAppBundle,
                appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? AppBrand.displayName
            )
            settings.launchAtLogin = !enabled
        }
    }

    nonisolated static var isMainAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    nonisolated static func shouldApplySettingsSideEffects(isHydratingSettings: Bool) -> Bool {
        !isHydratingSettings
    }

    nonisolated static func didEnableImageOCR(previous: AppSettings, current: AppSettings) -> Bool {
        !previous.enableImageTextRecognition && current.enableImageTextRecognition
    }

    nonisolated static func didChangeImageOCRConfiguration(previous: AppSettings, current: AppSettings) -> Bool {
        guard previous.enableImageTextRecognition, current.enableImageTextRecognition else { return false }
        return previous.ocrRecognitionLevelRaw != current.ocrRecognitionLevelRaw
            || previous.ocrMinimumTextHeight != current.ocrMinimumTextHeight
            || previous.ocrMaxImageMegapixels != current.ocrMaxImageMegapixels
            || previous.ocrMaxImageBytes != current.ocrMaxImageBytes
            || previous.ocrRecognitionLanguages != current.ocrRecognitionLanguages
    }

    nonisolated static func didChangeSensitiveHandling(
        previous: SmartCategorySettings,
        current: SmartCategorySettings
    ) -> Bool {
        previous.sensitiveEnabled != current.sensitiveEnabled
            || previous.autoExpireSensitive != current.autoExpireSensitive
            || previous.sensitiveExpiry != current.sensitiveExpiry
    }

    nonisolated static func launchAtLoginFailureMessage(
        enabling: Bool,
        isAppBundle: Bool,
        appName: String
    ) -> String {
        if enabling && !isAppBundle {
            return "Launch at login isn't available right now. Install \(appName) in Applications and try again."
        }

        if enabling {
            return "Couldn't turn on Launch at Login. Try moving \(appName) to Applications and try again."
        }

        return "Couldn't turn off Launch at Login. You can remove \(appName) in System Settings if needed."
    }

    // MARK: - Selection & Paste

    func quickPaste(index: Int) {
        let current = filteredClips
        guard index < current.count else { return }
        copyToClipboard(clips: [current[index]])
    }

    /// Replace the entire selection with a single clip (standard click behavior).
    func selectSingle(_ clipID: UUID) {
        // Dismiss inline editing if selecting a different clip
        if inlineEditingClipID != nil && inlineEditingClipID != clipID {
            inlineEditingClipID = nil
        }
        selectedClipIDs = [clipID]
    }

    func toggleSelection(_ clipID: UUID) {
        if selectedClipIDs.contains(clipID) {
            selectedClipIDs.remove(clipID)
        } else {
            selectedClipIDs.insert(clipID)
        }
        // Dismiss inline editing on selection changes
        if inlineEditingClipID != nil {
            inlineEditingClipID = nil
        }
    }

    func clearSelection() {
        if selectedClipIDs.isEmpty == false {
            logState("clearSelection count=\(selectedClipIDs.count)")
        }
        selectedClipIDs.removeAll()
        inlineEditingClipID = nil
    }

    /// Select every clip currently visible in the active folder/search context.
    func selectAllVisibleClips() {
        let visibleIDs = Set(filteredClips.map(\.clipID))
        guard visibleIDs.isEmpty == false else { return }
        selectedClipIDs = visibleIDs
        logState("selectAllVisibleClips count=\(visibleIDs.count)")
    }

    /// Move keyboard focus one step left (direction = -1) or right (direction = +1).
    func navigateSelection(direction: Int) {
        let current = filteredClips
        guard !current.isEmpty else { return }

        if selectedClipIDs.count == 1,
           let selected = selectedClipIDs.first,
           let index = current.firstIndex(where: { $0.clipID == selected }) {
            let newIndex = max(0, min(current.count - 1, index + direction))
            selectedClipIDs = [current[newIndex].clipID]
        } else if selectedClipIDs.isEmpty {
            // Nothing selected — pick the edge clip in the direction of travel
            selectedClipIDs = [current[direction > 0 ? 0 : current.count - 1].clipID]
        } else {
            // Multi-select → collapse to the edge item then step
            let indices = current.enumerated()
                .filter { selectedClipIDs.contains($0.element.clipID) }
                .map(\.offset)
            if let edge = direction < 0 ? indices.first : indices.last {
                let stepped = max(0, min(current.count - 1, edge + direction))
                selectedClipIDs = [current[stepped].clipID]
            }
        }
    }

    /// Toggle the preview overlay for the currently selected clip.
    func togglePreview() {
        if previewingClipID != nil {
            previewingClipID = nil
        } else if selectedClipIDs.count == 1 {
            previewingClipID = selectedClipIDs.first
        }
    }

    /// Open selected clip in macOS Quick Look when possible, fallback to inline overlay.
    func openPreviewForSelection() {
        guard selectedClipIDs.count == 1,
              let selectedID = selectedClipIDs.first,
              let clip = filteredClips.first(where: { $0.clipID == selectedID })
        else {
            togglePreview()
            return
        }

        if QuickLookPreviewService.shared.preview(clip: clip) {
            previewingClipID = nil
        } else {
            togglePreview()
        }
    }

    /// Open a specific clip in macOS Quick Look, falling back to inline preview.
    func openPreview(for clipID: UUID) {
        selectSingle(clipID)
        guard let clip = filteredClips.first(where: { $0.clipID == clipID }) else {
            previewingClipID = clipID
            return
        }

        if QuickLookPreviewService.shared.preview(clip: clip) {
            previewingClipID = nil
        } else {
            previewingClipID = clipID
        }
    }

    /// Begin inline editing directly inside the card (no overlay).
    func startInlineEdit(for clipID: UUID) {
        guard let clip = filteredClips.first(where: { $0.clipID == clipID }),
              Self.canInlineEdit(clip.clipType)
        else { return }
        selectSingle(clipID)
        inlineEditingClipID = clipID
    }

    nonisolated static func canInlineEdit(_ clipType: ClipType) -> Bool {
        clipType == .text || clipType == .link || clipType == .color
    }

    private struct EditedClipContent {
        let type: ClipType
        let previewText: String
        let textValue: String?
        let urlValue: String?
    }

    private nonisolated static func editedContent(for rawText: String, existingType: ClipType) -> EditedClipContent {
        if let normalizedURL = ClipActionService.normalizeWebURL(rawText),
           existingType == .link || rawText.contains(".") {
            return EditedClipContent(
                type: .link,
                previewText: normalizedURL.host ?? normalizedURL.absoluteString,
                textValue: normalizedURL.absoluteString,
                urlValue: normalizedURL.absoluteString
            )
        }

        return EditedClipContent(
            type: .text,
            previewText: String(rawText.prefix(500)),
            textValue: rawText,
            urlValue: nil
        )
    }

    func clearLinkMetadata(for clip: ClipItemModel) {
        clip.linkPageTitle = nil
        clip.linkFaviconURLString = nil
        clip.linkThumbnailURLString = nil
        clip.linkThumbnailData = nil
        clip.linkDescriptionText = nil
        clip.linkPlatformRaw = nil
        clip.linkVideoDuration = nil
    }

    private func removeUnlockedSmartFolderMemberships(from clip: ClipItemModel) {
        clip.folders.removeAll { folder in
            folder.isSmartFolder && folder.isAutoCategorizationLocked == false
        }
    }

    private func applyClassification(_ classification: ContentClassification, to clip: ClipItemModel) {
        removeUnlockedSmartFolderMemberships(from: clip)
        clip.contentTags = classification.contentTags
        clip.isSensitive = classification.isSensitive
        clip.detectedLanguage = classification.detectedLanguage
        clip.sensitiveExpiresAt = nil

        if clip.clipType != .link {
            if classification.contentTags.contains(.colorValue),
               let text = clip.textValue ?? clip.previewText as String?,
               text.trimmingCharacters(in: .whitespacesAndNewlines).count < 100 {
                clip.typeRaw = ClipType.color.rawValue
            } else {
                clip.typeRaw = ClipType.text.rawValue
            }
        }

        if classification.isSensitive,
           settings.smartCategories.autoExpireSensitive,
           let seconds = settings.smartCategories.sensitiveExpiry.seconds {
            clip.sensitiveExpiresAt = Date().addingTimeInterval(seconds)
        }

        for category in classification.matchedCategories where settings.smartCategories.isEnabled(category) {
            let smartFolder = ensureSmartFolderExists(for: category)
            guard smartFolder.isAutoCategorizationLocked == false else { continue }
            if !clip.folders.contains(where: { $0.folderID == smartFolder.folderID }) {
                clip.folders.append(smartFolder)
            }
        }
    }

    func refreshDerivedState(for clip: ClipItemModel, previousType: ClipType, previousURL: String?) {
        let classification = ContentClassifier.classify(item: clip)
        applyClassification(classification, to: clip)

        if clip.clipType == .link {
            let didChangeURL = previousType != .link || previousURL != clip.urlValue
            if didChangeURL {
                clearLinkMetadata(for: clip)
            }
            fetchLinkMetadataIfNeeded(for: clip)
        } else if previousType == .link {
            clearLinkMetadata(for: clip)
        }
    }

    /// Update the text content of a clip (for inline editing).
    func updateClipText(_ clipID: UUID, newText: String) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previousType = clip.clipType
        let previousURL = clip.urlValue

        // Remove old hash from index before content changes.
        removeClipFromHashIndex(clip)

        let editedContent = Self.editedContent(for: trimmed, existingType: clip.clipType)
        clip.typeRaw = editedContent.type.rawValue
        clip.textValue = editedContent.textValue
        clip.previewText = editedContent.previewText
        clip.urlValue = editedContent.urlValue
        refreshDerivedState(for: clip, previousType: previousType, previousURL: previousURL)

        // Recompute hash for the new content
        let newHash = ContentFingerprint.fingerprint(for: clip)
        clip.contentHash = newHash
        registerClipInHashIndex(clip)

        save()
        refreshClips()
        logState("updateClipText clip=\(clipID) length=\(trimmed.count)")
    }

    /// Apply a text transform to a single clip's text content.
    func transformClipText(_ clipID: UUID, transform: TextTransform) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        let original = clip.textValue ?? clip.urlValue ?? clip.previewText
        let transformed = transform.apply(to: original)
        guard transformed != original else { return }
        updateClipText(clipID, newText: transformed)
        logState("transformClipText clip=\(clipID) transform=\(transform.rawValue)")
    }

    func loadSelectedOrSingleToClipboard(primaryID: UUID, autoPaste: Bool, forcePlainText: Bool = false) {
        let hadSelection = !selectedClipIDs.isEmpty
        let selection = clipsForContextAction(primaryID: primaryID)
        copyToClipboard(clips: selection, autoPaste: autoPaste, forcePlainText: forcePlainText)

        if hadSelection {
            DispatchQueue.main.async { self.clearSelection() }
        }
    }

    /// Resolve the clips targeted by a context action.
    /// If there is an active multi/single selection, prefer that set; otherwise use the primary clip.
    func clipsForContextAction(primaryID: UUID) -> [ClipItemModel] {
        let current = filteredClips
        if !selectedClipIDs.isEmpty {
            let selected = current.filter { selectedClipIDs.contains($0.clipID) }
            if !selected.isEmpty {
                return selected
            }
        }
        return current.filter { $0.clipID == primaryID }
    }

    func suggestedActionSignature(for item: ClipItemModel) -> Int {
        var hasher = Hasher()
        hasher.combine(item.typeRaw)
        hasher.combine(item.contentTagsRaw)
        hasher.combine(item.detectedLanguageRaw ?? "")
        hasher.combine(item.urlValue ?? "")
        hasher.combine(item.textValue ?? item.previewText)
        return hasher.finalize()
    }

    func pruneSuggestedActionCache() {
        let liveIDs = Set(clips.map(\.clipID))
        suggestedActionCache = suggestedActionCache.filter { liveIDs.contains($0.key) }
    }

}
