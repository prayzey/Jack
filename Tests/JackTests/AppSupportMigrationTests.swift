import XCTest
@testable import Gilt

/// Covers the Gilt→Jack data-folder migration ladder in `AppSupportLocator`.
/// Every case uses a throwaway temp base — never the real Application Support.
final class AppSupportMigrationTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSupportMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private var jack: URL { base.appendingPathComponent("Jack", isDirectory: true) }
    private var gilt: URL { base.appendingPathComponent("Gilt", isDirectory: true) }

    func testFreshInstallCreatesJack() {
        let resolved = AppSupportLocator.resolveDataDirectory(base: base)

        XCTAssertEqual(resolved, jack)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jack.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: gilt.path))
    }

    func testExistingGiltIsRenamedToJackWithContentsIntact() throws {
        try FileManager.default.createDirectory(at: gilt, withIntermediateDirectories: true)
        let marker = gilt.appendingPathComponent("Gilt.store")
        try "clips".write(to: marker, atomically: true, encoding: .utf8)

        let resolved = AppSupportLocator.resolveDataDirectory(base: base)

        XCTAssertEqual(resolved, jack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gilt.path))
        let moved = jack.appendingPathComponent("Gilt.store")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "clips")
    }

    func testPopulatedJackIsUsedAsIsAndGiltIsLeftAlone() throws {
        try FileManager.default.createDirectory(at: jack, withIntermediateDirectories: true)
        try "new".write(to: jack.appendingPathComponent("Gilt.store"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: gilt, withIntermediateDirectories: true)
        try "old".write(to: gilt.appendingPathComponent("Gilt.store"), atomically: true, encoding: .utf8)

        let resolved = AppSupportLocator.resolveDataDirectory(base: base)

        XCTAssertEqual(resolved, jack)
        XCTAssertTrue(FileManager.default.fileExists(atPath: gilt.path), "stale Gilt must never be deleted or merged")
        XCTAssertEqual(try String(contentsOf: jack.appendingPathComponent("Gilt.store"), encoding: .utf8), "new")
    }

    func testJackHoldingOnlyDSStoreStillAdoptsGilt() throws {
        try FileManager.default.createDirectory(at: jack, withIntermediateDirectories: true)
        try Data().write(to: jack.appendingPathComponent(".DS_Store"))
        try FileManager.default.createDirectory(at: gilt, withIntermediateDirectories: true)
        try "clips".write(to: gilt.appendingPathComponent("Gilt.store"), atomically: true, encoding: .utf8)

        let resolved = AppSupportLocator.resolveDataDirectory(base: base)

        XCTAssertEqual(resolved, jack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gilt.path))
        XCTAssertEqual(try String(contentsOf: jack.appendingPathComponent("Gilt.store"), encoding: .utf8), "clips")
    }

    func testEmptyJackWithExistingGiltAdoptsGilt() throws {
        try FileManager.default.createDirectory(at: jack, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gilt, withIntermediateDirectories: true)
        try "clips".write(to: gilt.appendingPathComponent("Gilt.store"), atomically: true, encoding: .utf8)

        let resolved = AppSupportLocator.resolveDataDirectory(base: base)

        XCTAssertEqual(resolved, jack)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gilt.path))
        XCTAssertEqual(try String(contentsOf: jack.appendingPathComponent("Gilt.store"), encoding: .utf8), "clips")
    }
}
