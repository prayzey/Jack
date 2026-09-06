import Foundation
import Sparkle

@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    let isConfigured: Bool

    private let updaterController: SPUStandardUpdaterController?

    private init() {
        if AppUpdateConfiguration.current != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            isConfigured = true
        } else {
            updaterController = nil
            isConfigured = false
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
