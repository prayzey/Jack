import Foundation

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    static func from(bundleInfo: [String: Any]) -> AppUpdateConfiguration? {
        // A packaged debug app has real version keys too. Never let Sparkle
        // replace its local changes with a numerically newer public build.
        guard AppVersionInfo.from(bundleInfo: bundleInfo).configuration != "debug" else { return nil }
        guard
            let feedURLString = bundleInfo["SUFeedURL"] as? String,
            !feedURLString.isEmpty,
            let feedURL = URL(string: feedURLString),
            let publicEDKey = bundleInfo["SUPublicEDKey"] as? String,
            !publicEDKey.isEmpty
        else {
            return nil
        }

        return AppUpdateConfiguration(feedURL: feedURL, publicEDKey: publicEDKey)
    }

    static var current: AppUpdateConfiguration? {
        from(bundleInfo: Bundle.main.infoDictionary ?? [:])
    }
}
