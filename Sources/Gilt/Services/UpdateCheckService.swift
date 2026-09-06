import Foundation
import OSLog

/// Fetches a remote version manifest and determines whether the running app
/// is outdated (soft nudge) or below the minimum supported version (force update).
///
/// The manifest is a JSON file hosted at a known URL:
/// ```json
/// {
///   "latestVersion": "2.0.0",
///   "minimumVersion": "1.0.0",
///   "updateURL": "https://gilt.novor.dev",
///   "message": "Optional message to show users"
/// }
/// ```
@MainActor
final class UpdateCheckService: ObservableObject {
    static let shared = UpdateCheckService()

    /// What the user should see based on the version check.
    enum UpdateState: Equatable {
        /// App is up to date (or check hasn't run / failed silently).
        case current
        /// A newer version exists but the current version still works.
        case updateAvailable(latestVersion: String, message: String, updateURL: String)
        /// The current version is below the minimum — app should be blocked.
        case forceUpdate(latestVersion: String, message: String, updateURL: String)
    }

    @Published private(set) var state: UpdateState = .current

    /// User dismissed the soft banner for this session.
    @Published var softBannerDismissed = false

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "UpdateCheck")

    private static let defaultManifestURL = "https://downloads.gilt.novor.dev/version.json"

    private init() {}

    /// Check for updates. Called once on app launch.
    func checkOnLaunch() {
        Task {
            await check()
        }
    }

    private func check() async {
        let urlString = ProcessInfo.processInfo.environment["GILT_VERSION_URL"]
            ?? Self.defaultManifestURL

        guard let url = URL(string: urlString) else {
            logger.error("Invalid version manifest URL: \(urlString)")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode)
            {
                logger.warning("Version check returned HTTP \(httpResponse.statusCode)")
                return
            }

            let manifest = try JSONDecoder().decode(VersionManifest.self, from: data)
            let currentVersion = currentAppVersion()

            // Dev builds (swift run / Xcode play) have no Info.plist, so version
            // falls back to "0.0.0". Skip the check to avoid false force-update prompts.
            if currentVersion == "0.0.0" {
                logger.info("Skipping version check in dev build (no bundle version)")
                return
            }

            logger.info(
                "Version check: current=\(currentVersion) latest=\(manifest.latestVersion) minimum=\(manifest.minimumVersion)"
            )

            if compare(currentVersion, isLessThan: manifest.minimumVersion) {
                state = .forceUpdate(
                    latestVersion: manifest.latestVersion,
                    message: manifest.message.isEmpty
                        ? "This version of \(AppBrand.displayName) is no longer supported. Please update to continue."
                        : manifest.message,
                    updateURL: manifest.updateURL
                )
            } else if compare(currentVersion, isLessThan: manifest.latestVersion) {
                state = .updateAvailable(
                    latestVersion: manifest.latestVersion,
                    message: manifest.message.isEmpty
                        ? "\(AppBrand.displayName) \(manifest.latestVersion) is available."
                        : manifest.message,
                    updateURL: manifest.updateURL
                )
            } else {
                state = .current
            }
        } catch {
            // Fail silently — never block the app because of a network issue.
            logger.warning("Version check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Version helpers

    private func currentAppVersion() -> String {
        AppVersionInfo.current.semanticVersionForUpdateChecks
    }

    /// Semantic version comparison: returns true if `lhs` < `rhs`.
    /// ponytail: numeric string compare; manifest versions are consistently 3-part (e.g. 1.4.2)
    private func compare(_ lhs: String, isLessThan rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedAscending
    }
}

// MARK: - Manifest model

private struct VersionManifest: Decodable {
    let latestVersion: String
    let minimumVersion: String
    let updateURL: String
    let message: String
}
