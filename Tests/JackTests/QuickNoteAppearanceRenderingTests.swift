import AppKit
import XCTest
@testable import Gilt

final class QuickNoteAppearanceRenderingTests: XCTestCase {
    func testCleanCanvasWithWallpaperUsesWallpaperAsPrimarySurface() {
        let appearance = QuickNoteAppearance(
            style: .cleanCanvas,
            transparencyMode: .material,
            backgroundWallpaper: .custom,
            customWallpaperFilename: "quick-note-wallpaper.jpg",
            wallpaperOffsetX: 0.5,
            wallpaperOffsetY: 0.5,
            surfaceOpacity: 0.55
        )

        XCTAssertTrue(appearance.usesWallpaperAsPrimarySurface(hasLoadedWallpaper: true))
        XCTAssertFalse(appearance.shouldRenderTemplateSurface(hasLoadedWallpaper: true))
        XCTAssertFalse(appearance.shouldRenderMaterialOverlay(hasLoadedWallpaper: true))
        XCTAssertFalse(appearance.shouldUseGlassSurface(hasLoadedWallpaper: true))
        XCTAssertFalse(appearance.shouldRenderTemplateChrome(hasLoadedWallpaper: true))
    }

    func testCleanCanvasWithoutWallpaperFallsBackToPlainSurface() {
        let appearance = QuickNoteAppearance(
            style: .cleanCanvas,
            transparencyMode: .glass,
            backgroundWallpaper: .custom,
            customWallpaperFilename: "missing.png",
            wallpaperOffsetX: 0.5,
            wallpaperOffsetY: 0.5,
            surfaceOpacity: 0.8
        )

        XCTAssertFalse(appearance.usesWallpaperAsPrimarySurface(hasLoadedWallpaper: false))
        XCTAssertTrue(appearance.shouldRenderTemplateSurface(hasLoadedWallpaper: false))
        XCTAssertFalse(appearance.shouldRenderMaterialOverlay(hasLoadedWallpaper: false))
        XCTAssertTrue(appearance.shouldUseGlassSurface(hasLoadedWallpaper: false))
        XCTAssertFalse(appearance.shouldRenderTemplateChrome(hasLoadedWallpaper: false))
    }

    @MainActor
    func testMenuBarPopoverTextColorPrefersDedicatedSetting() {
        var settings = AppSettings()
        settings.menuBarPopoverTextColorHex = "#224466"
        var appearance = QuickNoteAppearance()
        appearance.customTextColorHex = "#FF5500"

        let resolved = settings.resolvedMenuBarPopoverTextColor(appearance: appearance)

        XCTAssertEqual(resolved.hexString, "#224466")
    }

    @MainActor
    func testMenuBarPopoverAppearanceRespectsCustomTextColorOverride() {
        var settings = AppSettings()
        var appearance = QuickNoteAppearance()
        appearance.customTextColorHex = "#FF5500"
        appearance.autoTextColorOnWallpaper = true

        let resolved = settings.resolvedMenuBarPopoverTextColor(appearance: appearance)

        XCTAssertEqual(resolved.hexString, "#FF5500")
    }

    func testMenuBarPopoverAppearanceAutoPicksDarkTextOnBrightWallpaper() {
        var appearance = QuickNoteAppearance()
        appearance.autoTextColorOnWallpaper = true

        let resolved = appearance.effectiveTextColor(wallpaperLuminance: 0.82)
        let rgb = NSColor(resolved).usingColorSpace(.deviceRGB)

        XCTAssertNotNil(rgb)
        XCTAssertLessThan((rgb?.brightnessComponent ?? 1), 0.5)
    }

    @MainActor
    func testMenuBarPopoverAutoInkOnLightPaperStyle() {
        var settings = AppSettings()
        var appearance = QuickNoteAppearance(style: .paper)
        appearance.autoTextColorOnWallpaper = true

        let resolved = settings.resolvedMenuBarPopoverTextColor(appearance: appearance)
        let rgb = NSColor(resolved).usingColorSpace(.deviceRGB)

        XCTAssertNotNil(rgb)
        XCTAssertLessThan((rgb?.brightnessComponent ?? 1), 0.5)
    }

    @MainActor
    func testMenuBarPopoverAutoInkOnDarkObsidianStyle() {
        var settings = AppSettings()
        var appearance = QuickNoteAppearance(style: .obsidian)
        appearance.autoTextColorOnWallpaper = true

        let resolved = settings.resolvedMenuBarPopoverTextColor(appearance: appearance)
        let rgb = NSColor(resolved).usingColorSpace(.deviceRGB)

        XCTAssertNotNil(rgb)
        XCTAssertGreaterThan((rgb?.brightnessComponent ?? 0), 0.5)
    }

    func testPaperStyleCardLuminanceIsBright() {
        XCTAssertGreaterThan(QuickNoteStyle.paper.averageCardLuminance, 0.55)
    }

    func testObsidianStyleCardLuminanceIsDark() {
        XCTAssertLessThan(QuickNoteStyle.obsidian.averageCardLuminance, 0.55)
    }

    func testBuiltInWallpaperStillAllowsMaterialMode() {
        let appearance = QuickNoteAppearance(
            style: .paper,
            transparencyMode: .material,
            backgroundWallpaper: .terra,
            customWallpaperFilename: nil,
            wallpaperOffsetX: 0.5,
            wallpaperOffsetY: 0.5,
            surfaceOpacity: 0.9
        )

        XCTAssertFalse(appearance.usesWallpaperAsPrimarySurface(hasLoadedWallpaper: true))
        XCTAssertTrue(appearance.shouldRenderTemplateSurface(hasLoadedWallpaper: true))
        XCTAssertTrue(appearance.shouldRenderMaterialOverlay(hasLoadedWallpaper: true))
        XCTAssertFalse(appearance.shouldUseGlassSurface(hasLoadedWallpaper: true))
        XCTAssertTrue(appearance.shouldRenderTemplateChrome(hasLoadedWallpaper: true))
    }
}
