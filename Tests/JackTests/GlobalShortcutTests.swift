import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Gilt

final class GlobalShortcutTests: XCTestCase {
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
