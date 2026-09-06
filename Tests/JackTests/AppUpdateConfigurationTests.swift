import Testing
@testable import Gilt

struct AppUpdateConfigurationTests {
    @Test
    func buildsConfigurationWhenRequiredKeysExist() throws {
        let info: [String: Any] = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "abc123"
        ]

        let configuration = try #require(AppUpdateConfiguration.from(bundleInfo: info))

        #expect(configuration.feedURL.absoluteString == "https://example.com/appcast.xml")
        #expect(configuration.publicEDKey == "abc123")
    }

    @Test
    func returnsNilWhenKeysAreMissing() {
        #expect(AppUpdateConfiguration.from(bundleInfo: [:]) == nil)
        #expect(AppUpdateConfiguration.from(bundleInfo: ["SUFeedURL": "https://example.com"]) == nil)
        #expect(AppUpdateConfiguration.from(bundleInfo: ["SUPublicEDKey": "abc123"]) == nil)
    }
}
