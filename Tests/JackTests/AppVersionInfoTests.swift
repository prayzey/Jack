import Testing
@testable import Gilt

struct AppVersionInfoTests {
    @Test
    func buildsDisplayStringsFromBundleInfo() {
        let version = AppVersionInfo.from(bundleInfo: [
            "CFBundleShortVersionString": "1.0.2",
            "CFBundleVersion": "47"
        ])

        #expect(version.sidebarLabel == "v1.0.2")
        #expect(version.settingsLabel == "1.0.2 (build 47)")
        #expect(version.semanticVersionForUpdateChecks == "1.0.2")
        #expect(version.sentryReleaseName == "\(AppBrand.bundleIdentifier)@1.0.2+47")
    }

    @Test
    func fallsBackCleanlyWhenBundleInfoIsMissing() {
        let version = AppVersionInfo.from(bundleInfo: [:])

        #expect(version.sidebarLabel == "dev")
        #expect(version.settingsLabel == "Development build")
        #expect(version.semanticVersionForUpdateChecks == "0.0.0")
        #expect(version.sentryReleaseName == nil)
    }

    @Test
    func trimsWhitespaceAndTreatsEmptyStringsAsMissing() {
        let version = AppVersionInfo.from(bundleInfo: [
            "CFBundleShortVersionString": " 1.0.2 \n",
            "CFBundleVersion": " "
        ])

        #expect(version.sidebarLabel == "v1.0.2")
        #expect(version.settingsLabel == "1.0.2")
        #expect(version.sentryReleaseName == nil)
    }
}
