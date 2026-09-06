import Foundation

/// Singleton bridge for cross-view access to long-lived stores that aren't
/// always reachable via `@EnvironmentObject`. Set during `JackApp.init` and
/// read from views (e.g. `StatsSettingsView`) that need a store before the
/// environment graph is fully wired.
@MainActor
final class AppStoreReferences {
    static let shared = AppStoreReferences()

    weak var statsStore: TranscriptionStatsStore?
    weak var clipboardStore: ClipboardStore?

    private init() {}
}
