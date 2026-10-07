import Foundation
import XCTest
@testable import Gilt

final class PolarLicenseServiceTests: XCTestCase {
    func testAllLicenseRequestsPinTheTestedAPIContract() async throws {
        let service = PolarLicenseService.shared
        let requests = [
            try await service.buildRequest(path: "/activate", body: PolarActivateRequest(
                key: "QA-versioning-key", organizationId: PolarConstants.organizationID,
                label: "QA versioning test"
            )),
            try await service.buildRequest(path: "/validate", body: PolarValidateRequest(
                key: "QA-versioning-key", organizationId: PolarConstants.organizationID,
                activationId: "QA-activation", benefitId: PolarConstants.benefitID
            )),
            try await service.buildRequest(path: "/deactivate", body: PolarDeactivateRequest(
                key: "QA-versioning-key", organizationId: PolarConstants.organizationID,
                activationId: "QA-activation"
            )),
        ]

        for (path, request) in zip(["activate", "validate", "deactivate"], requests) {
            XCTAssertEqual(request.url?.absoluteString,
                           "https://api.polar.sh/v1/customer-portal/license-keys/\(path)")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Polar-Version"), "2026-10", path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(
                with: XCTUnwrap(request.httpBody)
            ) as? [String: String])
            XCTAssertEqual(body["key"], "QA-versioning-key")
            XCTAssertEqual(body["organization_id"], PolarConstants.organizationID)
            if path == "activate" {
                XCTAssertEqual(body["label"], "QA versioning test")
            } else {
                XCTAssertEqual(body["activation_id"], "QA-activation")
            }
            if path == "validate" {
                XCTAssertEqual(body["benefit_id"], PolarConstants.benefitID)
            }
        }
    }
}
