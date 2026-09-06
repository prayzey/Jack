import XCTest
@testable import Gilt

@MainActor
final class OnboardingMusicFadeTests: XCTestCase {
    func testOnboardingMusicFadeVolumeClampsProgress() {
        XCTAssertEqual(AppWindowManager.onboardingMusicFadeVolume(startVolume: 0.7, progress: -0.3), 0.7, accuracy: 0.0001)
        XCTAssertEqual(AppWindowManager.onboardingMusicFadeVolume(startVolume: 0.7, progress: 1.4), 0.0, accuracy: 0.0001)
    }

    func testOnboardingMusicFadeVolumeDecreasesLinearly() {
        XCTAssertEqual(AppWindowManager.onboardingMusicFadeVolume(startVolume: 0.8, progress: 0.25), 0.6, accuracy: 0.0001)
        XCTAssertEqual(AppWindowManager.onboardingMusicFadeVolume(startVolume: 0.8, progress: 0.5), 0.4, accuracy: 0.0001)
        XCTAssertEqual(AppWindowManager.onboardingMusicFadeVolume(startVolume: 0.8, progress: 1.0), 0.0, accuracy: 0.0001)
    }
}
