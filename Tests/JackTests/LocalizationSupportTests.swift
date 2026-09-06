import XCTest
@testable import Gilt

final class LocalizationSupportTests: XCTestCase {
    func testBundleAwareLocalizationLoadsSpanishString() {
        let value = L10n.string(
            "systemFolder.clipboard.name",
            default: "Clipboard",
            locale: Locale(identifier: "es")
        )

        XCTAssertEqual(value, "Portapapeles")
    }

    func testBundleAwareLocalizationLoadsGermanString() {
        let value = L10n.string(
            "systemFolder.clipboard.name",
            default: "Clipboard",
            locale: Locale(identifier: "de")
        )

        XCTAssertEqual(value, "Zwischenablage")
    }

    func testKnownLocalizedValuesIncludesAllSupportedBuiltInNames() {
        let values = L10n.knownLocalizedValues(
            "systemFolder.clipboard.name",
            default: "Clipboard",
            localeIdentifiers: ["en", "es", "de"]
        )

        XCTAssertTrue(values.contains("Clipboard"))
        XCTAssertTrue(values.contains("Portapapeles"))
        XCTAssertTrue(values.contains("Zwischenablage"))
    }

    func testCommonAndMenuCopyLocalizeToSpanish() {
        XCTAssertEqual(
            CommonCopy.copy(locale: Locale(identifier: "es")),
            "Copiar"
        )
        XCTAssertEqual(
            AppMenuCopy.commandPalette(locale: Locale(identifier: "es")),
            "Paleta de comandos"
        )
        XCTAssertEqual(
            AppMenuCopy.openMeetings(locale: Locale(identifier: "de")),
            "Meetings öffnen"
        )
    }

    func testAIAndBoardKeysPresentInSpanishAndGerman() {
        XCTAssertEqual(
            L10n.string("ai.action.summarize", default: "Summarize", locale: Locale(identifier: "es")),
            "Resumir"
        )
        XCTAssertEqual(
            L10n.string("workspace.boards.sectionTitle", default: "Boards", locale: Locale(identifier: "de")),
            "Boards"
        )
        XCTAssertEqual(
            L10n.string("settings.tab.ai", default: "AI", locale: Locale(identifier: "es")),
            "IA"
        )
    }
}
