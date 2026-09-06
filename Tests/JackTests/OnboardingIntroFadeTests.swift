import XCTest
@testable import Gilt

@MainActor
final class OnboardingIntroFadeTests: XCTestCase {
    func testIntroContentOpacityIsClampedToUnitInterval() {
        XCTAssertEqual(OnboardingView.introContentOpacity(for: -0.2), 0)
        XCTAssertEqual(OnboardingView.introContentOpacity(for: 0.4), 0.4)
        XCTAssertEqual(OnboardingView.introContentOpacity(for: 1.3), 1)
    }

    func testIntroFocusOverlayOpacityTracksInverseProgress() {
        XCTAssertEqual(OnboardingView.introFocusOverlayOpacity(for: 0), 0.45, accuracy: 0.0001)
        XCTAssertEqual(OnboardingView.introFocusOverlayOpacity(for: 0.5), 0.225, accuracy: 0.0001)
        XCTAssertEqual(OnboardingView.introFocusOverlayOpacity(for: 1), 0, accuracy: 0.0001)
    }
}
