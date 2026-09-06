import Foundation
import XCTest
@testable import Gilt

final class AppLanguageTests: XCTestCase {
    func testLocalizedLabelsMatchSupportedLanguages() {
        XCTAssertEqual(AppLanguage.system.localizedLabel(locale: Locale(identifier: "en")), "System Default")
        XCTAssertEqual(AppLanguage.system.localizedLabel(locale: Locale(identifier: "es")), "Idioma del sistema")
        XCTAssertEqual(AppLanguage.german.localizedLabel(locale: Locale(identifier: "de")), "Deutsch")
    }

    func testSettingsDecodeDefaultsAppLanguageToSystem() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.appLanguage, .system)
    }

    func testLocalizationHonorsPreferredAppLanguageOverride() {
        let value = L10n.withPreferredLocaleIdentifier("es") {
            L10n.string("onboarding.tab.ready", default: "Ready")
        }

        XCTAssertEqual(value, "Listo")
    }
}
