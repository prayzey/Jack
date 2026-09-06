import Foundation
import XCTest
@testable import Gilt

final class SettingsCopyTests: XCTestCase {
    func testSettingsTabRawValuesStayStableForNavigation() {
        XCTAssertEqual(SettingsTab.folders.rawValue, "folders")
        XCTAssertEqual(SettingsTab.license.rawValue, "license")
        XCTAssertEqual(SettingsNavigation.foldersTabRawValue, "folders")
        XCTAssertEqual(SettingsTab(navigationRawValue: "Folders"), .folders)
    }

    func testSettingsTabLabelsLocalizeToSpanish() {
        let label = SettingsTab.folders.localizedLabel(locale: Locale(identifier: "es"))

        XCTAssertEqual(label, "Carpetas")
    }

    func testGreetingUsesLocalizedTimeOfDayAndFirstName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 9))!

        let greeting = SettingsCopy.greeting(
            for: date,
            fullName: "Ada Lovelace",
            calendar: calendar,
            locale: Locale(identifier: "de")
        )

        XCTAssertEqual(greeting, "Guten Morgen, Ada")
    }

    func testDeleteFolderAlertMessageInterpolatesLocalizedTemplate() {
        let message = SettingsCopy.deleteFolderAlertMessage(
            folderName: "Ideas",
            locale: Locale(identifier: "es")
        )

        XCTAssertEqual(message, "¿Eliminar \"Ideas\" y quitarla de cualquier clip que la use?")
    }
}
