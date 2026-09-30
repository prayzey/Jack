import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Gilt

final class GlobalShortcutTests: XCTestCase {
    @MainActor
    func testQuickNoteWaitsForAccessibilityInsteadOfReportingConflict() {
        var tapAttempts = 0
        let manager = GlobalHotKeyManager(
            isAccessibilityTrusted: { false },
            registerEventTap: { _, _ in tapAttempts += 1; return false }
        )
        defer { manager.unregister() }

        XCTAssertTrue(manager.registerQuickNoteHotKey(shortcut: .quickNoteDefault))
        XCTAssertNil(manager.registeredShortcuts[.quickNote])
        XCTAssertEqual(tapAttempts, 0)
        XCTAssertEqual(manager.pendingShortcuts[.quickNote], .quickNoteDefault)
    }

    @MainActor
    func testPendingShortcutsRegisterAfterAccessibilityIsGranted() {
        var trusted = false
        var tapAttempts = 0
        let manager = GlobalHotKeyManager(
            isAccessibilityTrusted: { trusted },
            registerEventTap: { _, _ in tapAttempts += 1; return true }
        )
        defer { manager.unregister() }

        XCTAssertTrue(manager.registerQuickNoteHotKey(shortcut: .quickNoteDefault))
        XCTAssertTrue(manager.registerCommandPaletteHotKey(shortcut: .commandPaletteDefault))
        manager.retryPendingHotKeys()
        XCTAssertEqual(tapAttempts, 0)
        XCTAssertEqual(manager.pendingShortcuts.count, 2)

        trusted = true
        manager.retryPendingHotKeys()
        XCTAssertEqual(tapAttempts, 2)
        XCTAssertTrue(manager.pendingShortcuts.isEmpty)
        XCTAssertEqual(manager.registeredShortcuts[.quickNote], .quickNoteDefault)
        XCTAssertEqual(manager.registeredShortcuts[.commandPalette], .commandPaletteDefault)
    }

    @MainActor
    func testUnregisteredPendingShortcutIsNotRetried() {
        var trusted = false
        var tapAttempts = 0
        let manager = GlobalHotKeyManager(
            isAccessibilityTrusted: { trusted },
            registerEventTap: { _, _ in tapAttempts += 1; return true }
        )
        defer { manager.unregister() }

        XCTAssertTrue(manager.registerQuickNoteHotKey(shortcut: .quickNoteDefault))
        manager.unregister(role: .quickNote)
        trusted = true
        manager.retryPendingHotKeys()

        XCTAssertEqual(tapAttempts, 0)
        XCTAssertTrue(manager.pendingShortcuts.isEmpty)
        XCTAssertTrue(manager.registeredShortcuts.isEmpty)
    }

    @MainActor
    func testRegistrationFailureWithPermissionStillReportsUnavailable() {
        let manager = GlobalHotKeyManager(
            isAccessibilityTrusted: { true },
            registerEventTap: { _, _ in false }
        )
        defer { manager.unregister() }

        XCTAssertFalse(manager.registerQuickNoteHotKey(shortcut: .quickNoteDefault))
        XCTAssertTrue(manager.pendingShortcuts.isEmpty)
        XCTAssertNil(manager.registeredShortcuts[.quickNote])
    }

    func testDefaultShortcutUsesControlV() {
        XCTAssertEqual(GlobalShortcut.default.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(GlobalShortcut.default.modifiers, UInt32(controlKey))
        XCTAssertEqual(GlobalShortcut.default.displayString, "Ctrl+V")
    }

    func testLegacyDefaultRemainsCommandShiftV() {
        XCTAssertEqual(GlobalShortcut.legacyDefault.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(GlobalShortcut.legacyDefault.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(GlobalShortcut.legacyDefault.displayString, "Cmd+Shift+V")
    }

    func testPreviousDefaultRemainsControlOptionV() {
        XCTAssertEqual(GlobalShortcut.previousDefault.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(GlobalShortcut.previousDefault.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(GlobalShortcut.previousDefault.displayString, "Option+Ctrl+V")
    }

    func testOptionOnlyShortcutsUseEventTapFallback() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(optionKey)
        )

        XCTAssertTrue(shortcut.requiresEventTapFallback)
    }

    func testControlOptionShortcutsStayOnCarbonPath() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertFalse(shortcut.requiresEventTapFallback)
    }

    func testSingleFunctionKeyShortcutIsAllowedAsModifierlessShortcut() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_F13),
            modifiers: 0
        )

        XCTAssertFalse(shortcut.requiresEventTapFallback)
        XCTAssertEqual(shortcut.displayString, "F13")
    }

    func testEventTapRegistrationMatchesOptionOnlyShortcutExactly() {
        let registration = GlobalHotKeyEventTapRegistration(
            roleRawValue: 1,
            shortcut: GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: UInt32(optionKey)
            )
        )

        XCTAssertTrue(
            registration.matches(
                keyCode: Int64(kVK_ANSI_V),
                flags: [.maskAlternate]
            )
        )
        XCTAssertFalse(
            registration.matches(
                keyCode: Int64(kVK_ANSI_V),
                flags: [.maskAlternate, .maskControl]
            )
        )
    }
}
