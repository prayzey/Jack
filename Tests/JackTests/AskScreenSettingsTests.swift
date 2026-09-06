import XCTest
@testable import Gilt

/// Guards the ask-the-screen enable flag and shortcut persistence.
///
/// Background: the ask-screen feature used to be "on" implicitly whenever a
/// shortcut was bound, and turning it off meant clearing the shortcut (which
/// erased the user's chosen key). It now has an explicit `askScreenEnabled`
/// flag that is independent of `askScreenShortcut`, so toggling the feature
/// off must keep the key for next time. These tests pin that contract plus
/// the migration path for settings files written before the flag existed.
final class AskScreenSettingsTests: XCTestCase {

    /// A custom dictation + ask-screen shortcut must survive an encode/decode
    /// round-trip — this is the "it reverts to the default after restart"
    /// regression in test form.
    func testShortcutsRoundTrip() throws {
        var settings = DictationSettings()
        settings.shortcut = DictationShortcut(keyCode: 96, modifiers: 0, trigger: .toggle) // F5
        settings.askScreenEnabled = true
        settings.askScreenShortcut = DictationShortcut(keyCode: 97, modifiers: 0, trigger: .pushToTalk) // F6

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: data)

        XCTAssertEqual(decoded.shortcut, settings.shortcut)
        XCTAssertTrue(decoded.askScreenEnabled)
        XCTAssertEqual(decoded.askScreenShortcut, settings.askScreenShortcut)
    }

    /// Turning the feature off keeps the bound key so flipping it back on
    /// restores the user's choice instead of snapping to a default.
    func testDisablingKeepsShortcut() throws {
        var settings = DictationSettings()
        settings.askScreenEnabled = true
        settings.askScreenShortcut = DictationShortcut(keyCode: 97, modifiers: 0, trigger: .toggle)

        settings.askScreenEnabled = false
        let decoded = try JSONDecoder().decode(
            DictationSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertFalse(decoded.askScreenEnabled)
        XCTAssertNotNil(decoded.askScreenShortcut)
        XCTAssertEqual(decoded.askScreenShortcut?.keyCode, 97)
    }

    /// Legacy files (written before `askScreenEnabled` existed) that have a
    /// bound shortcut should come back enabled, preserving the old "shortcut
    /// present means feature on" behaviour.
    func testLegacyBoundShortcutMigratesToEnabled() throws {
        let json = #"""
        {
            "askScreenShortcut": { "keyCode": 97, "modifiers": 0, "trigger": "toggle" }
        }
        """#
        let settings = try JSONDecoder().decode(DictationSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.askScreenEnabled)
        XCTAssertEqual(settings.askScreenShortcut?.keyCode, 97)
    }

    /// Legacy files with no ask-screen shortcut stay disabled — the feature is
    /// opt-in and must not surprise upgrading users with a new hotkey.
    func testLegacyNoShortcutMigratesToDisabled() throws {
        let json = #"{ "isEnabled": true }"#
        let settings = try JSONDecoder().decode(DictationSettings.self, from: Data(json.utf8))

        XCTAssertFalse(settings.askScreenEnabled)
        XCTAssertNil(settings.askScreenShortcut)
    }
}
