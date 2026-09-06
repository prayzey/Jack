import Foundation

/// Central naming policy for the Gilt → Jack rebrand.
///
/// **Jack** is the public product name. **Gilt** survives only where changing it
/// would break upgrades, permissions, or on-disk data for shipped installs.
enum AppBrand {
    /// Public-facing product name (menu bar, windows, copy, privacy strings).
    static let displayName = "Jack"

    /// Public feedback destinations shared by every app menu.
    static let feedbackURL = URL(string: "https://gilt.novor.dev/feedback")!
    static let bugReportURL = URL(string: "https://gilt.novor.dev/feedback?type=bug")!
    static let featureRequestURL = URL(string: "https://gilt.novor.dev/feedback?type=feature")!

    /// Legacy bundle identifier — do not change without treating it as a new app.
    /// macOS ties Accessibility, Keychain, Sparkle deltas, and code signing to this ID.
    static let bundleIdentifier = "com.praisedev.gilt"

    /// SwiftPM executable target name and `@testable import` module name.
    static let targetName = "Gilt"

    /// SwiftPM-generated resource bundle inside the packaged `.app`.
    static let resourceBundleName = "Gilt_Gilt.bundle"

    /// OSLog subsystem string (`log show --predicate 'subsystem == "Jack"'`).
    static let logSubsystem = "Jack"

    /// Sentry release tags use the bundle ID prefix, not the display name.
    static let sentryReleasePrefix = bundleIdentifier

    /// Application Support folder name on disk (`~/Library/Application Support/Jack/`).
    /// `AppSupportLocator` migrates the legacy `Gilt` folder to this name once at
    /// launch (atomic same-volume rename), so existing users keep clips, notes,
    /// and settings while seeing the current brand on disk.
    static let dataDirectoryName = "Jack"

    /// Previous Application Support folder name. Now used only as the migration
    /// source (renamed to `dataDirectoryName` at launch) and as the fallback the
    /// app keeps using if that rename ever fails. A downgrade to a pre-migration
    /// build would find an empty `Gilt` folder — acceptable, since Sparkle never
    /// downgrades.
    static let legacyDataDirectoryName = "Gilt"

    /// Primary on-disk store filename inside the data directory. Unchanged by the
    /// folder rename — the SwiftData store and its `-shm`/`-wal` sidecars keep
    /// this name; renaming them buys nothing and risks the database.
    static let legacyStoreFileName = "Gilt.store"
}
