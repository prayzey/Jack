import Foundation
import OSLog
import Security
import Sentry

/// Stores license credentials in the macOS Keychain.
///
/// Keychain items are keyed by `kSecAttrService` = "com.praisedev.gilt.license"
/// and `kSecAttrAccount` = per-item account name. This keeps license data secure
/// and persistent across app updates.
///
/// Keychain reads are cached in memory after the first access to avoid blocking
/// the main thread on repeated `SecItemCopyMatching` calls (which wait on the
/// Security daemon via Mach IPC and can hang for 2s+).
enum LicenseVault {
    private static let logger = Logger(subsystem: AppBrand.logSubsystem, category: "LicenseVault")
    private static let defaultService = "com.praisedev.gilt.license"
    nonisolated(unsafe) static var serviceOverride: String?
    private static var service: String { serviceOverride ?? defaultService }

    // In-memory cache — populated on first read, invalidated on write/delete.
    // This prevents repeated SecItemCopyMatching calls from blocking the main thread
    // during SwiftUI view body evaluation.
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    // Account keys for individual secrets
    private static let licenseKeyAccount = "license-key"
    private static let activationIDAccount = "activation-id"
    private static let installationIDAccount = "installation-id"
    private static let trialStartedAtAccount = "trial-started-at"

    // MARK: - License Key

    static var licenseKey: String? {
        get { cachedRead(account: licenseKeyAccount) }
        set {
            if let newValue {
                save(account: licenseKeyAccount, value: newValue)
            } else {
                delete(account: licenseKeyAccount)
            }
        }
    }

    // MARK: - Activation ID

    static var activationID: String? {
        get { cachedRead(account: activationIDAccount) }
        set {
            if let newValue {
                save(account: activationIDAccount, value: newValue)
            } else {
                delete(account: activationIDAccount)
            }
        }
    }

    // MARK: - Installation ID

    /// Stable per-machine identifier. Generated once, reused across activations.
    static var installationID: String {
        if let existing = cachedRead(account: installationIDAccount) {
            return existing
        }
        let newID = UUID().uuidString
        save(account: installationIDAccount, value: newID)
        return newID
    }

    // MARK: - Trial Start

    /// ISO 8601 timestamp of when the local trial began.
    static var trialStartedAt: String? {
        get { cachedRead(account: trialStartedAtAccount) }
        set {
            if let newValue {
                save(account: trialStartedAtAccount, value: newValue)
            } else {
                delete(account: trialStartedAtAccount)
            }
        }
    }

    // MARK: - Bulk Clear

    /// Removes all license-related Keychain items (used on deactivation).
    static func clearAll() {
        delete(account: licenseKeyAccount)
        delete(account: activationIDAccount)
    }

    static func clearTrialStartDate() {
        delete(account: trialStartedAtAccount)
    }

    // MARK: - Machine Label

    /// Human-readable label for this Mac, sent as the activation label to Polar.
    static var machineLabel: String {
        let name = Host.current().localizedName ?? "Mac"
        let shortID = String(installationID.prefix(8))
        return "\(name) (\(shortID))"
    }

    // MARK: - Keychain Helpers

    /// Returns a cached value if available, otherwise reads from Keychain once
    /// and caches the result. This avoids repeated `SecItemCopyMatching` calls
    /// that block the main thread waiting on the Security daemon.
    private static func cachedRead(account: String) -> String? {
        if let cached = cache[account] {
            return cached
        }
        let value = read(account: account)
        cache[account] = value
        return value
    }

    private static func save(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Invalidate cache before writing
        cache[account] = value

        // Delete any existing item first
        deleteFromKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed with status \(status, privacy: .public)")
        }

        let crumb = Sentry.Breadcrumb(level: .info, category: "keychain")
        crumb.message = "Saved \(account)"
        SentrySDK.addBreadcrumb(crumb)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        cache.removeValue(forKey: account)
        deleteFromKeychain(account: account)
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
