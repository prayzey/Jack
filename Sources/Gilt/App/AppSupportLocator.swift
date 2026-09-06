import Foundation
import OSLog

enum AppSupportLocator {
    private static let logger = Logger(subsystem: AppBrand.logSubsystem, category: "AppSupportLocator")

    /// Migrated data directory for the running app. The `static let` closure runs
    /// the Gilt→Jack migration ladder exactly once per launch, thread-safely,
    /// before any caller creates subdirectories.
    ///
    /// Guarded against XCTest: unit tests must never touch the developer's real
    /// `~/Library/Application Support`, so under tests we return the legacy path
    /// unchanged and let migration tests exercise `resolveDataDirectory(base:)`
    /// against a temp directory instead.
    private static let migratedDataDirectory: URL = {
        let base = directory()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return base.appendingPathComponent(AppBrand.legacyDataDirectoryName, isDirectory: true)
        }
        return resolveDataDirectory(base: base)
    }()

    /// Resolves the on-disk data directory, migrating the legacy `Gilt` folder to
    /// `Jack` if needed. Injectable `base` so unit tests run the ladder against a
    /// temp directory. Idempotent and side-effect-safe to call repeatedly.
    static func resolveDataDirectory(base: URL, fileManager: FileManager = .default) -> URL {
        let jack = base.appendingPathComponent(AppBrand.dataDirectoryName, isDirectory: true)
        let gilt = base.appendingPathComponent(AppBrand.legacyDataDirectoryName, isDirectory: true)

        let jackExists = isDirectory(jack, fileManager: fileManager)
        let giltExists = isDirectory(gilt, fileManager: fileManager)

        // Jack already populated → use it. Never merge or delete a stale Gilt.
        if jackExists, !isEmptyDirectory(jack, fileManager: fileManager) {
            if giltExists {
                logger.warning("Both Jack and legacy Gilt data folders exist; using Jack, leaving Gilt untouched.")
            }
            return jack
        }

        // Empty Jack shell next to a real Gilt → drop the shell so the rename can proceed.
        if jackExists, giltExists {
            try? fileManager.removeItem(at: jack)
        }

        // Gilt exists → atomic same-volume rename. On any failure keep using Gilt.
        if giltExists {
            do {
                try fileManager.moveItem(at: gilt, to: jack)
                return jack
            } catch {
                logger.warning("Gilt→Jack data folder migration failed (\(error.localizedDescription)); using legacy Gilt.")
                return gilt
            }
        }

        // Fresh install (or empty Jack, no Gilt) → use Jack.
        try? fileManager.createDirectory(at: jack, withIntermediateDirectories: true)
        return jack
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isEmptyDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        // Finder droppings must not count as data: a Jack folder holding only a
        // .DS_Store would otherwise block the Gilt migration and strand real data.
        let contents = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.filter { $0 != ".DS_Store" }.isEmpty
    }

    static func directory(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> URL {
        let candidates = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return resolve(
            candidates: candidates,
            homeDirectory: homeDirectory ?? fileManager.homeDirectoryForCurrentUser,
            temporaryDirectory: temporaryDirectory ?? fileManager.temporaryDirectory
        )
    }

    static func resolve(candidates: [URL], homeDirectory: URL, temporaryDirectory: URL) -> URL {
        if let firstCandidate = candidates.first {
            return firstCandidate
        }

        let libraryAppSupport = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        if !libraryAppSupport.path.isEmpty {
            return libraryAppSupport
        }

        return temporaryDirectory
    }

    /// Shared app container path (`.../Jack`) so persistence, Finder actions, and
    /// Settings stay in sync. Production callers pass no arguments and get the
    /// once-per-launch migrated directory; passing a custom home/temp resolves the
    /// migration ladder against that base instead (used for isolated scopes).
    static func giltDirectory(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> URL {
        if homeDirectory == nil, temporaryDirectory == nil {
            return migratedDataDirectory
        }
        return resolveDataDirectory(
            base: directory(
                fileManager: fileManager,
                homeDirectory: homeDirectory,
                temporaryDirectory: temporaryDirectory
            ),
            fileManager: fileManager
        )
    }

    /// Pure path join to the legacy `Gilt` folder for a given base. Retained for
    /// callers that only need the un-migrated path without side effects (e.g.
    /// tests). Production paths go through `giltDirectory()` / the migrated path.
    static func giltDirectory(in appSupportDirectory: URL) -> URL {
        appSupportDirectory.appendingPathComponent(AppBrand.legacyDataDirectoryName, isDirectory: true)
    }

    static func storeFileURL(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> URL {
        storeFileURL(
            in: giltDirectory(
                fileManager: fileManager,
                homeDirectory: homeDirectory,
                temporaryDirectory: temporaryDirectory
            )
        )
    }

    static func storeFileURL(in giltDirectory: URL) -> URL {
        giltDirectory.appendingPathComponent(AppBrand.legacyStoreFileName)
    }

    static func notesFileURL(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> URL {
        notesFileURL(
            in: giltDirectory(
                fileManager: fileManager,
                homeDirectory: homeDirectory,
                temporaryDirectory: temporaryDirectory
            )
        )
    }

    static func notesFileURL(in giltDirectory: URL) -> URL {
        giltDirectory.appendingPathComponent("Notes.store.json")
    }

    static func noteImageAttachmentsDirectory(in giltDirectory: URL) -> URL {
        giltDirectory.appendingPathComponent("NoteAttachments", isDirectory: true)
    }
}
