import AVFoundation
import XCTest
@testable import Gilt

final class MicrophonePermissionServiceTests: XCTestCase {
    func testAuthorizationStatusMapping() {
        XCTAssertEqual(MicrophonePermissionStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(MicrophonePermissionStatus(.authorized), .authorized)
        XCTAssertEqual(MicrophonePermissionStatus(.denied), .denied)
        XCTAssertEqual(MicrophonePermissionStatus(.restricted), .restricted)
    }

    func testOnlyAuthorizedIsGranted() {
        XCTAssertTrue(MicrophonePermissionStatus.authorized.isGranted)
        XCTAssertFalse(MicrophonePermissionStatus.notDetermined.isGranted)
        XCTAssertFalse(MicrophonePermissionStatus.denied.isGranted)
        XCTAssertFalse(MicrophonePermissionStatus.restricted.isGranted)
        XCTAssertFalse(MicrophonePermissionStatus.unknown.isGranted)
    }
}
