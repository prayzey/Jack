import XCTest
@testable import Gilt

/// Phase 1 of the Jack rebrand introduces `JackSettings` as an additive
/// nested struct on `AppSettings`. These tests pin down the migration
/// behavior so a future change can't silently downgrade returning users.
final class JackSettingsMigrationTests: XCTestCase {

    // MARK: - Migration from legacy JSON (no jackSettings key)

    func testMigratesFromLegacyWithCharactersEnabled() throws {
        // Settings JSON written by a pre-Jack build: no `jackSettings` key,
        // but `pulseCharactersEnabled` was true.
        let legacyJSON = """
        {
            "pulseCharactersEnabled": true,
            "pulseCharacterTriggerMode": "interval",
            "pulseCharacterMessageMode": "usageOnly"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        XCTAssertEqual(
            settings.jackSettings.presenceMode,
            .onTriggers,
            "Returning users with Pulse characters on should land in 'on triggers' mode, not 'alwaysOn' (we never opt anyone into the new permanent-presence mode without consent)"
        )
        XCTAssertEqual(settings.jackSettings.look, .bruce)
        XCTAssertEqual(
            settings.jackSettings.jobs,
            [.reminders, .chat],
            "Reminders and chat jobs default on so users discover the chat feature"
        )
        XCTAssertEqual(settings.jackSettings.defaultPopoverTab, .chat)
    }

    func testMigratesFromLegacyWithCharactersDisabled() throws {
        let legacyJSON = """
        {
            "pulseCharactersEnabled": false
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        XCTAssertEqual(
            settings.jackSettings.presenceMode,
            .off,
            "Legacy users who had Pulse characters off must stay off after the migration"
        )
    }

    func testMigratesFromCompletelyEmptyJSON() throws {
        // No keys at all — brand new install or wiped settings.
        let emptyJSON = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: emptyJSON)

        XCTAssertEqual(
            settings.jackSettings.presenceMode,
            .off,
            "Fresh installs default to Jack off — user has to explicitly enable from settings"
        )
    }

    // MARK: - Roundtrip (encode → decode preserves user choices)

    func testRoundtripPreservesAllJackFields() throws {
        var settings = AppSettings()
        settings.jackSettings = JackSettings(
            presenceMode: .alwaysOn,
            look: .bruce,
            jobs: [.chat],
            defaultPopoverTab: .reminders
        )

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.jackSettings.presenceMode, .alwaysOn)
        XCTAssertEqual(decoded.jackSettings.look, .bruce)
        XCTAssertEqual(decoded.jackSettings.jobs, [.chat])
        XCTAssertEqual(decoded.jackSettings.defaultPopoverTab, .reminders)
    }

    func testStoredJackSettingsTakePrecedenceOverLegacyFlag() throws {
        // If the JSON has BOTH a `jackSettings` block and the legacy flag,
        // the explicit `jackSettings` wins. This guards against an accidental
        // re-migration after the new struct has already been persisted.
        let mixedJSON = """
        {
            "pulseCharactersEnabled": true,
            "jackSettings": {
                "presenceMode": "off",
                "look": "bruce",
                "jobs": [],
                "defaultPopoverTab": "chat"
            }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: mixedJSON)
        XCTAssertEqual(settings.jackSettings.presenceMode, .off)
    }

    // MARK: - Forward-compat: unknown job strings are dropped silently

    func testUnknownJobValuesAreIgnored() throws {
        // A future Jack build might add new JackJob cases. If that build
        // writes settings then the user downgrades, we should ignore the
        // unknown job values instead of failing the whole settings decode.
        let futureJSON = """
        {
            "jackSettings": {
                "presenceMode": "alwaysOn",
                "look": "bruce",
                "jobs": ["chat", "futureTimeTravelJob", "reminders"],
                "defaultPopoverTab": "chat"
            }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: futureJSON)
        XCTAssertEqual(settings.jackSettings.jobs, [.chat, .reminders])
        XCTAssertEqual(settings.jackSettings.presenceMode, .alwaysOn)
    }

    // MARK: - Convenience helpers

    func testIsVisibleHelper() {
        XCTAssertFalse(JackSettings(presenceMode: .off).isVisible)
        XCTAssertTrue(JackSettings(presenceMode: .onTriggers).isVisible)
        XCTAssertTrue(JackSettings(presenceMode: .alwaysOn).isVisible)
    }

    func testPerformsHelper() {
        let chatOnly = JackSettings(jobs: [.chat])
        XCTAssertTrue(chatOnly.performs(.chat))
        XCTAssertFalse(chatOnly.performs(.reminders))
    }
}
