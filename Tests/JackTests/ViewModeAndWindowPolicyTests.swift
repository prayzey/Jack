import AppKit
import XCTest
@testable import Gilt

@MainActor
final class ViewModeAndWindowPolicyTests: XCTestCase {
    func testViewModeMetadataCoversAllSixModes() {
        XCTAssertEqual(ViewMode.allCases, [.tray, .drawer, .panel, .grid, .radial, .workspace])
        XCTAssertEqual(ViewMode.tray.label, "Tray")
        XCTAssertEqual(ViewMode.drawer.label, "Drawer")
        XCTAssertEqual(ViewMode.panel.label, "Panel")
        XCTAssertEqual(ViewMode.grid.label, "Grid")
        XCTAssertEqual(ViewMode.radial.label, "Radial")
        XCTAssertEqual(ViewMode.workspace.label, "Workspace")
    }

    func testViewModeDescriptionsMatchUXIntent() {
        XCTAssertEqual(ViewMode.tray.description, "Bottom shelf with horizontal scroll")
        XCTAssertEqual(ViewMode.drawer.description, "Side panel with vertical list")
        XCTAssertEqual(ViewMode.panel.description, "Compact pop-up list at your cursor")
        XCTAssertEqual(ViewMode.grid.description, "Floating window with card grid")
        XCTAssertEqual(ViewMode.radial.description, "Quick-access ring at cursor")
        XCTAssertEqual(
            ViewMode.workspace.description,
            "Large workspace with tabs for clipboard, tasks, pulse, and meetings"
        )
    }

    func testModeWindowLevelUsesDockPlusOne() {
        let expected = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        XCTAssertEqual(AppWindowManager.modeWindowLevel.rawValue, expected.rawValue)
    }

    func testClickOutsideMonitorPolicyDisablesDuringSettingsPreview() {
        XCTAssertTrue(AppWindowManager.shouldInstallClickOutsideMonitors(settingsPreviewActive: false))
        XCTAssertFalse(AppWindowManager.shouldInstallClickOutsideMonitors(settingsPreviewActive: true))
    }

    func testFocusForInputThrottleReturnsTrueWhenRequestsAreTooCloseTogether() {
        XCTAssertTrue(
            AppWindowManager.shouldThrottleFocusForInput(
                lastRequestAt: 10.0,
                now: 10.05,
                minimumInterval: 0.12
            )
        )
    }

    func testFocusForInputThrottleReturnsFalseAfterMinimumInterval() {
        XCTAssertFalse(
            AppWindowManager.shouldThrottleFocusForInput(
                lastRequestAt: 10.0,
                now: 10.20,
                minimumInterval: 0.12
            )
        )
    }

    func testTrayAnimationSpeedPreservesCurrentTimingByDefault() {
        XCTAssertEqual(
            AppWindowManager.adjustedAnimationDuration(base: 0.30, speed: 0, reduceMotion: false),
            0.30,
            accuracy: 0.001
        )
    }

    func testTrayAnimationSpeedCanMakeTogglesInstant() {
        XCTAssertEqual(
            AppWindowManager.adjustedAnimationDuration(base: 0.30, speed: 0.999, reduceMotion: false),
            0
        )
    }

    func testReducedMotionMakesTrayTogglesInstant() {
        XCTAssertEqual(
            AppWindowManager.adjustedAnimationDuration(base: 0.30, speed: 0, reduceMotion: true),
            0,
            accuracy: 0.001
        )
    }

    func testBoundTrayWindowIsSuppressedWhileLaunchStillRoutingToOnboarding() {
        XCTAssertTrue(
            AppWindowManager.shouldSuppressBoundTrayWindow(
                suppressInitialTrayUntilLaunchDecision: true,
                onboardingVisible: false,
                activeViewMode: .tray
            )
        )
    }

    func testInitialTrayWindowIsSuppressedOnLaunchWhenOnboardingWillAppear() {
        XCTAssertTrue(
            AppWindowManager.shouldSuppressInitialTrayWindowOnLaunch(
                shouldShowOnboarding: true,
                savedViewMode: .tray
            )
        )
    }

    func testInitialTrayWindowIsSuppressedOnLaunchWhenSavedViewModeIsNonTray() {
        XCTAssertTrue(
            AppWindowManager.shouldSuppressInitialTrayWindowOnLaunch(
                shouldShowOnboarding: false,
                savedViewMode: .grid
            )
        )
    }

    func testInitialTrayWindowStaysAvailableOnNormalTrayLaunch() {
        XCTAssertFalse(
            AppWindowManager.shouldSuppressInitialTrayWindowOnLaunch(
                shouldShowOnboarding: false,
                savedViewMode: .tray
            )
        )
    }

    func testBoundTrayWindowIsSuppressedWhenOnboardingIsAlreadyVisible() {
        XCTAssertTrue(
            AppWindowManager.shouldSuppressBoundTrayWindow(
                suppressInitialTrayUntilLaunchDecision: false,
                onboardingVisible: true,
                activeViewMode: .tray
            )
        )
    }

    func testBoundTrayWindowIsSuppressedForNonTrayModes() {
        XCTAssertTrue(
            AppWindowManager.shouldSuppressBoundTrayWindow(
                suppressInitialTrayUntilLaunchDecision: false,
                onboardingVisible: false,
                activeViewMode: .grid
            )
        )
    }

    func testBoundTrayWindowRemainsAvailableForNormalTrayLaunch() {
        XCTAssertFalse(
            AppWindowManager.shouldSuppressBoundTrayWindow(
                suppressInitialTrayUntilLaunchDecision: false,
                onboardingVisible: false,
                activeViewMode: .tray
            )
        )
    }

    func testMissingTrayWindowRecoversToSavedWorkspaceMode() {
        XCTAssertEqual(
            AppWindowManager.recoveryModeForMissingToggleWindow(
                activeViewMode: .tray,
                savedViewMode: .workspace,
                hasTrayWindow: false,
                hasActiveModeWindow: false
            ),
            .workspace
        )
    }

    func testMissingTrayWindowRecoversToTrayWhenTrayIsSavedMode() {
        XCTAssertEqual(
            AppWindowManager.recoveryModeForMissingToggleWindow(
                activeViewMode: .tray,
                savedViewMode: .tray,
                hasTrayWindow: false,
                hasActiveModeWindow: false
            ),
            .tray
        )
    }

    func testExistingTrayWindowDoesNotNeedRecovery() {
        XCTAssertNil(
            AppWindowManager.recoveryModeForMissingToggleWindow(
                activeViewMode: .tray,
                savedViewMode: .workspace,
                hasTrayWindow: true,
                hasActiveModeWindow: false
            )
        )
    }

    func testMissingNonTrayModeWindowRecoversToActiveMode() {
        XCTAssertEqual(
            AppWindowManager.recoveryModeForMissingToggleWindow(
                activeViewMode: .workspace,
                savedViewMode: .workspace,
                hasTrayWindow: false,
                hasActiveModeWindow: false
            ),
            .workspace
        )
    }

    func testExistingNonTrayModeWindowDoesNotNeedRecovery() {
        XCTAssertNil(
            AppWindowManager.recoveryModeForMissingToggleWindow(
                activeViewMode: .workspace,
                savedViewMode: .workspace,
                hasTrayWindow: false,
                hasActiveModeWindow: true
            )
        )
    }

    func testWorkspaceFrameUsesPreferredSizeWhenItFits() {
        let visibleFrame = NSRect(x: 40, y: 24, width: 1600, height: 1000)

        let frame = AppWindowManager.workspaceFrame(
            preferredWidth: 1400,
            preferredHeight: 820,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.width, 1400)
        XCTAssertEqual(frame.height, 820)
        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(frame.midY, visibleFrame.midY)
    }

    func testWorkspaceFrameClampsOversizedPreferencesToWorkspaceMaximums() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 2200, height: 1600)

        let frame = AppWindowManager.workspaceFrame(
            preferredWidth: 2400,
            preferredHeight: 1800,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.width, AppWindowManager.workspaceMaximumWindowSize.width)
        XCTAssertEqual(frame.height, AppWindowManager.workspaceMaximumWindowSize.height)
    }

    func testWorkspaceFrameShrinksToFitSmallerDisplays() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1100, height: 760)

        let frame = AppWindowManager.workspaceFrame(
            preferredWidth: 1600,
            preferredHeight: 1000,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.width, 1020)
        XCTAssertEqual(frame.height, 680)
    }
}
