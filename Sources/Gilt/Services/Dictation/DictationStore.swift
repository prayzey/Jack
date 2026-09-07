import Foundation
import OSLog
import SwiftUI

/// Persists dictation settings + a capped history of recent dictations.
///
/// Settings live in UserDefaults under `DictationSettings` (JSON). History
/// lives on disk under `Application Support/Jack/Dictation/history.json` —
/// kept separate from clipboard history so the user can clear one without
/// touching the other.
@MainActor
final class DictationStore: ObservableObject {
    @Published var settings: DictationSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
        }
    }
    @Published private(set) var history: [DictationHistoryEntry] = []

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "DictationStore")
    private let settingsKey = "GiltDictationSettings"
    private let historyURL: URL
    private let cacheRootURL: URL
    private let defaults: UserDefaults
    /// Cap so the history file never balloons. 100 entries × ~200 chars = ~20KB.
    private let maxHistoryEntries = 100

    init(defaults: UserDefaults = .standard, rootURL: URL? = nil) {
        self.defaults = defaults
        let root = rootURL ?? AppSupportLocator.giltDirectory().appendingPathComponent("Dictation", isDirectory: true)
        self.cacheRootURL = root
        self.historyURL = root.appendingPathComponent("history.json")

        try? FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(DictationSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = DictationSettings()
        }
        loadHistory()
    }

    // MARK: - Settings

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
        // Force the write to disk immediately. Settings changes are rare,
        // deliberate user actions, but the app is frequently relaunched via
        // `jack restart` / a hard kill — without an explicit flush a just-
        // changed shortcut can be lost before UserDefaults' lazy periodic
        // sync runs, which reads to the user as "it reverted to the default."
        defaults.synchronize()
    }

    // MARK: - History

    func appendHistory(_ entry: DictationHistoryEntry) {
        guard settings.saveDictationHistory else { return }
        history.insert(entry, at: 0)
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func deleteHistoryEntry(_ id: UUID) {
        history.removeAll { $0.entryID == id }
        persistHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        if let decoded = try? JSONDecoder().decode([DictationHistoryEntry].self, from: data) {
            self.history = decoded
        }
    }

    private func persistHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch {
            logger.error("Failed to persist dictation history: \(error.localizedDescription)")
        }
    }

    // MARK: - Storage roots

    /// Where the Qwen GGUF lives. Shared with the meeting summarizer so we
    /// never download the same multi-GB model twice.
    var qwenCacheURL: URL {
        AppSupportLocator.giltDirectory()
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("qwen3.5-4b-q4", isDirectory: true)
    }
}
