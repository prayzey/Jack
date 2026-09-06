import Combine
import XCTest
@testable import Gilt

@MainActor
final class WallpaperOffsetTests: XCTestCase {
    func testClampWallpaperOffsetClampsBelowZero() {
        XCTAssertEqual(ClipboardStore.clampWallpaperOffset(-0.25), 0)
    }

    func testClampWallpaperOffsetClampsAboveOne() {
        XCTAssertEqual(ClipboardStore.clampWallpaperOffset(1.4), 1)
    }

    func testClampWallpaperOffsetPassesThroughInRangeValues() {
        XCTAssertEqual(ClipboardStore.clampWallpaperOffset(0.0), 0.0)
        XCTAssertEqual(ClipboardStore.clampWallpaperOffset(0.5), 0.5)
        XCTAssertEqual(ClipboardStore.clampWallpaperOffset(1.0), 1.0)
    }

    func testWallpaperPreviewPublishesOnceForCombinedOffsetUpdate() {
        let preview = WallpaperPreviewState()
        var cancellables: Set<AnyCancellable> = []
        var changeCount = 0

        preview.objectWillChange
            .sink { changeCount += 1 }
            .store(in: &cancellables)

        preview.update(x: 0.2, y: 0.8)

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(preview.liveOffsets, WallpaperOffsets(x: 0.2, y: 0.8))
    }

    func testWallpaperPreviewCommitClampsAndClearsLiveState() {
        let preview = WallpaperPreviewState()
        var settings = AppSettings()

        preview.update(x: -0.2, y: 1.3)
        preview.commit(into: &settings)

        XCTAssertEqual(settings.wallpaperOffsetX, 0)
        XCTAssertEqual(settings.wallpaperOffsetY, 1)
        XCTAssertNil(preview.liveOffsets)
    }
}
