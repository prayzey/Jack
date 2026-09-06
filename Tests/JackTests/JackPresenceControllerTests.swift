import XCTest
@testable import Gilt

/// Covers the pure presence-transition decision that drives whether Jack parks
/// above the dock, hides, or stays put. This is the logic that was missing — the
/// "Always on" setting saved fine but nothing acted on it — so these tests pin
/// the wiring so the regression can't come back.
final class JackPresenceControllerTests: XCTestCase {

    // MARK: - Always on

    func testTurningAlwaysOnParks() {
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .off,
                newMode: .alwaysOn,
                lookChanged: false,
                hasPerformer: false
            ),
            .park
        )
    }

    func testLaunchWithSavedAlwaysOnParks() {
        // Launch: controller's currentMode defaults to .off, saved mode is
        // alwaysOn, and no performer exists yet. Must park.
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .off,
                newMode: .alwaysOn,
                lookChanged: false,
                hasPerformer: false
            ),
            .park
        )
    }

    func testAlreadyAlwaysOnWithNoChangeDoesNothing() {
        // An unrelated settings save must not restart the walk-in animation.
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .alwaysOn,
                newMode: .alwaysOn,
                lookChanged: false,
                hasPerformer: true
            ),
            .none
        )
    }

    func testLookSwapWhileAlwaysOnReparks() {
        // A look change tears the performer down (hasPerformer: false) and must
        // re-park so the new character walks in.
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .alwaysOn,
                newMode: .alwaysOn,
                lookChanged: true,
                hasPerformer: false
            ),
            .park
        )
    }

    func testAlwaysOnWithoutPerformerReparks() {
        // Defensive: if the mode is unchanged but the performer somehow went
        // away, rebuild it rather than leaving Jack invisible.
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .alwaysOn,
                newMode: .alwaysOn,
                lookChanged: false,
                hasPerformer: false
            ),
            .park
        )
    }

    // MARK: - Off / triggers

    func testTurningOffHides() {
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .alwaysOn,
                newMode: .off,
                lookChanged: false,
                hasPerformer: true
            ),
            .hide
        )
    }

    func testOnTriggersHidesSinceTriggerPipelineRemoved() {
        // The trigger walk relied on the deleted usage pipeline, so onTriggers
        // currently keeps Jack hidden rather than parked.
        XCTAssertEqual(
            JackPresenceController.resolveAction(
                previousMode: .alwaysOn,
                newMode: .onTriggers,
                lookChanged: false,
                hasPerformer: true
            ),
            .hide
        )
    }

    // MARK: - Look → asset mapping

    func testVideoNameMapping() {
        XCTAssertEqual(JackPresenceController.videoName(for: .bruce), "walk-bruce-01")
    }

    func testWalkProfileMatchesCharacter() {
        XCTAssertEqual(
            JackPresenceController.walkProfile(for: .bruce).startDelay,
            PulseCharacterPerformer.WalkProfile.bruce.startDelay
        )
    }
}
