import XCTest
@testable import Gilt

final class MeetingAudioSourceTests: XCTestCase {
    func testMicrophoneOnlyRequiresMicrophonePermission() {
        XCTAssertTrue(MeetingAudioSource.microphone.requiresMicrophone)
        XCTAssertFalse(MeetingAudioSource.microphone.requiresSystemAudio)
        XCTAssertEqual(MeetingAudioSource.microphone.captureSubtitle, "From your mic")
    }

    func testSystemAudioOnlyRequiresSystemAudioPermission() {
        XCTAssertFalse(MeetingAudioSource.systemAudio.requiresMicrophone)
        XCTAssertTrue(MeetingAudioSource.systemAudio.requiresSystemAudio)
        XCTAssertEqual(MeetingAudioSource.systemAudio.captureSubtitle, "Apps and calls")
    }

    func testCombinedAudioRequiresBothCapturePipelines() {
        XCTAssertTrue(MeetingAudioSource.microphonePlusSystemAudio.requiresMicrophone)
        XCTAssertTrue(MeetingAudioSource.microphonePlusSystemAudio.requiresSystemAudio)
        XCTAssertEqual(MeetingAudioSource.microphonePlusSystemAudio.captureSubtitle, "Your voice + apps")
    }
}
