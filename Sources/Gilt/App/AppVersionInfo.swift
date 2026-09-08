import Foundation

struct AppVersionInfo: Equatable {
    let marketingVersion: String?
    let buildNumber: String?
    let configuration: String?
    let revision: String?

    static func from(bundleInfo: [String: Any]) -> AppVersionInfo {
        AppVersionInfo(
            marketingVersion: normalizedString(bundleInfo["CFBundleShortVersionString"]),
            buildNumber: normalizedString(bundleInfo["CFBundleVersion"]),
            configuration: normalizedString(bundleInfo["JackBuildConfiguration"]),
            revision: normalizedString(bundleInfo["JackGitRevision"])
        )
    }

    static var current: AppVersionInfo {
        from(bundleInfo: Bundle.main.infoDictionary ?? [:])
    }

    var sidebarLabel: String {
        if let marketingVersion {
            return "v\(marketingVersion)" + (configuration == "debug" ? " · DEV" : "")
        }
        return "dev"
    }

    var settingsLabel: String {
        let version: String
        switch (marketingVersion, buildNumber) {
        case let (.some(marketing), .some(build)):
            version = "\(marketing) (build \(build))"
        case let (.some(marketing), .none):
            version = marketing
        case let (.none, .some(build)):
            version = "Build \(build)"
        case (.none, .none):
            version = "Development build"
        }
        return version + buildDetails
    }

    private var buildDetails: String {
        let kind = configuration == "debug" ? "DEV" : configuration == "release" ? "Release" : nil
        let details = [kind, revision].compactMap { $0 }
        return details.isEmpty ? "" : " · " + details.joined(separator: " · ")
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
