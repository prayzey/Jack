import Foundation
import XCTest
@testable import Gilt

final class TrialStorageMigrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LicenseVault.serviceOverride = "com.praisedev.gilt.tests.\(UUID().uuidString)"
        LicenseVault.clearAll()
        LicenseVault.clearTrialStartDate()
    }

    override func tearDown() {
        LicenseVault.clearTrialStartDate()
        LicenseVault.clearAll()
        LicenseVault.serviceOverride = nil
        super.tearDown()
    }

    func testTrialStartedAtRoundTripsThroughKeychain() {
        let startedAt = "2026-03-25T12:00:00Z"

        LicenseVault.trialStartedAt = startedAt

        XCTAssertEqual(LicenseVault.trialStartedAt, startedAt)
    }

    func testResolveTrialStartStoragePrefersKeychainValue() {
        let resolution = ClipboardStore.resolveTrialStartStorage(
            keychainTrialStartedAt: "2026-03-20T12:00:00Z",
            legacySettingsTrialStartedAt: "2026-03-21T12:00:00Z"
        )

        XCTAssertEqual(resolution.effectiveTrialStartedAt, "2026-03-20T12:00:00Z")
        XCTAssertFalse(resolution.shouldPersistToKeychain)
        XCTAssertTrue(resolution.shouldClearLegacySettingsValue)
    }

    func testResolveTrialStartStorageMigratesLegacyValueWhenKeychainIsEmpty() {
        let resolution = ClipboardStore.resolveTrialStartStorage(
            keychainTrialStartedAt: nil,
            legacySettingsTrialStartedAt: "2026-03-21T12:00:00Z"
        )

        XCTAssertEqual(resolution.effectiveTrialStartedAt, "2026-03-21T12:00:00Z")
        XCTAssertTrue(resolution.shouldPersistToKeychain)
        XCTAssertTrue(resolution.shouldClearLegacySettingsValue)
    }

    func testResolveTrialStartStorageReturnsEmptyResolutionWhenNothingStored() {
        let resolution = ClipboardStore.resolveTrialStartStorage(
            keychainTrialStartedAt: nil,
            legacySettingsTrialStartedAt: nil
        )

        XCTAssertNil(resolution.effectiveTrialStartedAt)
        XCTAssertFalse(resolution.shouldPersistToKeychain)
        XCTAssertFalse(resolution.shouldClearLegacySettingsValue)
    }

    func testTrialStateIsExpiredWhenStoredStartIsOlderThan24Hours() {
        let now = Date(timeIntervalSince1970: 1_711_454_400)
        let startedAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(-25 * 3600))

        let state = ClipboardStore.trialState(
            licenseState: .unlicensed,
            trialStartedAt: startedAt,
            now: now
        )

        XCTAssertEqual(state, .expired)
    }

    func testTrialStateIsNotStartedWhenNoTimestampExists() {
        let state = ClipboardStore.trialState(
            licenseState: .unlicensed,
            trialStartedAt: nil,
            now: Date(timeIntervalSince1970: 1_711_454_400)
        )

        XCTAssertEqual(state, .notStarted)
    }

    func testTrialStateRemainsActiveForLicensedUsers() {
        let state = ClipboardStore.trialState(
            licenseState: .licensed(activationID: "activation-123"),
            trialStartedAt: nil,
            now: Date(timeIntervalSince1970: 1_711_454_400)
        )

        XCTAssertEqual(state, .active(remaining: .infinity))
    }
}
