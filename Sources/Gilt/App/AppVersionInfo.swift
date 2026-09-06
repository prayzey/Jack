import Foundation

struct AppVersionInfo: Equatable {
    let marketingVersion: String?
    let buildNumber: String?

    static func from(bundleInfo: [String: Any]) -> AppVersionInfo {
        AppVersionInfo(
            marketingVersion: normalizedString(bundleInfo["CFBundleShortVersionString"]),
            buildNumber: normalizedString(bundleInfo["CFBundleVersion"])
        )
    }

    static var current: AppVersionInfo {
        from(bundleInfo: Bundle.main.infoDictionary ?? [:])
    }

    var sidebarLabel: String {
        if let marketingVersion {
            return "v\(marketingVersion)"
        }
        return "dev"
    }

    var settingsLabel: String {
        switch (marketingVersion, buildNumber) {
        case let (.some(version), .some(build)):
            return "\(version) (build \(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return "Build \(build)"
        case (.none, .none):
            return "Development build"
        }
    }

    var sentryReleaseName: String? {
        guard let marketingVersion, let buildNumber else { return nil }
        return "\(AppBrand.sentryReleasePrefix)@\(marketingVersion)+\(buildNumber)"
    }

    var semanticVersionForUpdateChecks: String {
        marketingVersion ?? "0.0.0"
    }

    private static func normalizedString(_ rawValue: Any?) -> String? {
        guard let string = rawValue as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
