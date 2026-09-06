import AppKit
import Foundation
import OSLog

/// Top-level entry point for the screen-context-aware dictation feature.
///
/// Wraps `ScreenContextReader` (raw capture) and `ScreenContextExtractor`
/// (term mining) behind a single `capture()` call. Also handles short-lived
/// caching so that two dictations fired back-to-back in the same window
/// don't double the OCR cost.
@MainActor
final class ScreenContextService {
    static let shared = ScreenContextService()

    private let reader = ScreenContextReader()
    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "ScreenContextService")

    /// Per-window cache. The key is "<bundleID>|<windowTitleHash>" so two
    /// dictations in the same Cursor window reuse the same context; two
    /// dictations in different Slack channels do not.
    /// 4-second TTL — long enough to cover an "oops, take 2" retry, short
    /// enough that switching tabs invalidates.
    // Cached value is just the extracted terms list — that's all the
    // coordinator reads. Earlier we cached a rich Snapshot (source, app name,
    // timestamps) but nothing downstream ever consumed those fields.
    private var cache: [String: (terms: [String], expiresAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 4

    // MARK: - Public

    /// Capture context for the frontmost app right now and return the mined
    /// terms. Returns nil if the feature is disabled, the app is excluded, or
    /// capture failed. `existingVocabulary` is the user's custom-vocab + pack
    /// terms — used to suppress duplicates so screen terms don't crowd them out.
    func capture(
        settings: DictationSettings,
        existingVocabulary: [String]
    ) async -> [String]? {
        guard settings.useScreenContext else { return nil }

        let started = Date()
        let cacheKey = await cacheKeyForFrontmost()

        if let cacheKey, let cached = cache[cacheKey], cached.expiresAt > Date() {
            logger.debug("Screen context cache hit for \(cacheKey)")
            return cached.terms
        }

        guard let raw = await reader.capture(
            mode: settings.screenContextMode,
            excludedBundleIDs: settings.screenContextExcludedBundleIDs,
            axMinimumChars: settings.screenContextAXMinimumChars
        ) else {
            logger.debug("Screen context capture returned nil")
            return nil
        }

        let knownSet = Set(existingVocabulary)
        let terms = ScreenContextExtractor.extract(
            from: raw.text,
            excluding: knownSet,
            maxTerms: settings.screenContextMaxTerms
        )

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)

        logger.info("""
        Screen context captured: source=\(raw.source.rawValue) terms=\(terms.count) \
        chars=\(raw.text.count) elapsed=\(elapsed)ms app=\(raw.frontmostName ?? "?")
        """)

        if let cacheKey {
            cache[cacheKey] = (terms: terms, expiresAt: Date().addingTimeInterval(cacheTTL))
            pruneCache()
        }
        return terms
    }

    /// Block the way through to the system Screen Recording prompt — used
    /// by the Settings UI when the user flips the master toggle on.
    func ensurePermissionIfNeeded(mode: ScreenContextMode) {
        if mode.needsScreenRecording, !ScreenContextReader.hasScreenRecordingPermission() {
            _ = ScreenContextReader.requestScreenRecordingPermission()
        }
    }

    // MARK: - Internals

    private func cacheKeyForFrontmost() async -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        let pid = app.processIdentifier
        // Quick AX title fetch — much cheaper than walking the whole tree.
        // Wrapped in a Task so a slow AX-IPC call can't stall here.
        let title = await Task.detached(priority: .userInitiated) {
            ScreenContextService.fetchFrontWindowTitle(pid: pid)
        }.value
        return "\(bundleID)|\(title.hashValue)"
    }

    nonisolated private static func fetchFrontWindowTitle(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focused
        ) == .success, let value = focused else {
            return ""
        }
        // swiftlint:disable:next force_cast
        let window = value as! AXUIElement
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
           let str = title as? String {
            return str
        }
        return ""
    }

    private func pruneCache() {
        let now = Date()
        cache = cache.filter { $0.value.expiresAt > now }
        // Belt-and-suspenders cap — pathological window-switching shouldn't
        // grow the cache unboundedly.
        // Cap to 8 — snapshots are tiny now (a list of terms), but there's no
        // upside to growing the dictionary beyond a handful of recently-used
        // windows. Anything stale gets recaptured on next use.
        while cache.count > 8 {
            guard let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt }) else { break }
            cache.removeValue(forKey: oldest.key)
        }
    }
}
