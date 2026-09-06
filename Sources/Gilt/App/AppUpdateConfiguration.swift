import Foundation

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    static func from(bundleInfo: [String: Any]) -> AppUpdateConfiguration? {
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
