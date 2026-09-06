import Foundation
import XCTest

final class AppEntitlementsTests: XCTestCase {
    func testHardenedRuntimeEntitlementsIncludeMeetingAudioInput() throws {
        let entitlements = try NSDictionary(contentsOf: Self.entitlementsURL())
            .unwrap("Could not read Jack.entitlements")

        XCTAssertEqual(entitlements["com.apple.security.automation.apple-events"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
    }

    private static func entitlementsURL() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("Jack.entitlements")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Jack.entitlements")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw XCTSkip(message) }
        return value
    }
}
