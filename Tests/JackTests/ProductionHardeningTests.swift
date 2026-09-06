import XCTest
@testable import Gilt

final class ProductionHardeningTests: XCTestCase {

    func testPasteboardSuppressionOnlyIgnoresExactMatchingChangeCount() {
        XCTAssertTrue(
            ClipboardStore.shouldIgnorePasteboardChange(
                suppressedChangeCount: 42,
                currentChangeCount: 42
            )
        )
        XCTAssertFalse(
            ClipboardStore.shouldIgnorePasteboardChange(
                suppressedChangeCount: 42,
                currentChangeCount: 43
            )
        )
        XCTAssertFalse(
            ClipboardStore.shouldIgnorePasteboardChange(
                suppressedChangeCount: nil,
                currentChangeCount: 42
            )
        )
    }

    func testDidEnableImageOCROnlyReturnsTrueForFalseToTrueTransition() {
        var previous = AppSettings()
        var current = AppSettings()

        previous.enableImageTextRecognition = false
        current.enableImageTextRecognition = true
        XCTAssertTrue(ClipboardStore.didEnableImageOCR(previous: previous, current: current))

        previous.enableImageTextRecognition = true
        current.enableImageTextRecognition = true
        XCTAssertFalse(ClipboardStore.didEnableImageOCR(previous: previous, current: current))
    }

    func testDidChangeImageOCRConfigurationDetectsRecognitionSettingChanges() {
        var previous = AppSettings()
        var current = AppSettings()

        previous.enableImageTextRecognition = true
        current.enableImageTextRecognition = true
        current.ocrRecognitionLevelRaw = "accurate"

        XCTAssertTrue(ClipboardStore.didChangeImageOCRConfiguration(previous: previous, current: current))
    }

    func testAudioCaptureFromPathLikeTextDetectsRealAudioFilePath() {
        let capture = CapturedClip.audioCapture(fromPathLikeText: "/Users/test/Mixdown.wav")

        XCTAssertEqual(capture?.type, .audio)
        XCTAssertEqual(capture?.previewText, "Mixdown")
        XCTAssertEqual(capture?.textValue, "/Users/test/Mixdown.wav")
    }

    func testAudioCaptureFromPathLikeTextIgnoresPlainSpotifySentence() {
        let capture = CapturedClip.audioCapture(fromPathLikeText: "listen on spotify later")

        XCTAssertNil(capture)
    }

    func testWebLinkCapturePromotesPlainTextHTTPSLink() {
        let capture = CapturedClip.webLinkCapture(fromText: "https://youtu.be/TEAlD4p1yqI")

        XCTAssertEqual(capture?.type, .link)
        XCTAssertEqual(capture?.urlValue, "https://youtu.be/TEAlD4p1yqI")
    }

    func testWebLinkCapturePromotesSchemeLessDomain() {
        let capture = CapturedClip.webLinkCapture(fromText: "github.com/santifer/cv-santiago.git")

        XCTAssertEqual(capture?.type, .link)
        XCTAssertEqual(capture?.urlValue, "https://github.com/santifer/cv-santiago.git")
    }

    func testWebLinkCaptureRejectsRegularSentence() {
        let capture = CapturedClip.webLinkCapture(fromText: "watch this on youtube later")

        XCTAssertNil(capture)
    }

    func testWebLinkCaptureRejectsEmailAddresses() {
        // Regression: emails were being normalized to `https://user@host` because
        // URL parsing treats text before `@` as userinfo. Emails must stay text clips.
        XCTAssertNil(CapturedClip.webLinkCapture(fromText: "support@nasenicslfinance.com"))
        XCTAssertNil(CapturedClip.webLinkCapture(fromText: "first.last+tag@example.co.uk"))
    }

    func testWebLinkCaptureStillAcceptsPathsContainingAtSign() {
        // The `@` guard must only fire when `@` is in the authority position.
        // Paths like `example.com/users/@handle` should still resolve to a link.
        let capture = CapturedClip.webLinkCapture(fromText: "example.com/users/@handle")

        XCTAssertEqual(capture?.type, .link)
        XCTAssertEqual(capture?.urlValue, "https://example.com/users/@handle")
    }

    func testAppSupportLocatorPrefersSystemCandidateWhenAvailable() {
        let preferred = URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)
        let fallbackHome = URL(fileURLWithPath: "/Users/fallback", isDirectory: true)
        let fallbackTemp = URL(fileURLWithPath: "/tmp/fallback", isDirectory: true)

        XCTAssertEqual(
            AppSupportLocator.resolve(
                candidates: [preferred],
                homeDirectory: fallbackHome,
                temporaryDirectory: fallbackTemp
            ),
            preferred
        )
    }

    func testAppSupportLocatorFallsBackToHomeLibraryWhenSystemLookupIsEmpty() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let temp = URL(fileURLWithPath: "/tmp/fallback", isDirectory: true)

        XCTAssertEqual(
            AppSupportLocator.resolve(
                candidates: [],
                homeDirectory: home,
                temporaryDirectory: temp
            ),
            home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        )
    }

    func testGiltDirectoryAppendsAppFolderName() {
        let appSupport = URL(fileURLWithPath: "/Users/tester/Library/Application Support", isDirectory: true)

        XCTAssertEqual(
            AppSupportLocator.giltDirectory(in: appSupport),
            appSupport.appendingPathComponent("Gilt", isDirectory: true)
        )
    }

    func testStoreFileURLUsesSharedGiltDirectory() {
        let giltDirectory = URL(fileURLWithPath: "/Users/tester/Library/Application Support/Gilt", isDirectory: true)

        XCTAssertEqual(
            AppSupportLocator.storeFileURL(in: giltDirectory),
            giltDirectory.appendingPathComponent("Gilt.store")
        )
    }

    func testAppResourceLocatorBundleCandidatesPreferPackagedBundleRoot() {
        let appBundleURL = URL(fileURLWithPath: "/Applications/Jack.app", isDirectory: true)
        let mainResourceURL = URL(fileURLWithPath: "/Applications/Jack.app/Contents/Resources", isDirectory: true)
        let executableURL = URL(fileURLWithPath: "/Applications/Jack.app/Contents/MacOS/Jack")
        let candidates = AppResourceLocator.bundleURLCandidates(
            bundleName: AppBrand.resourceBundleName,
            mainBundleURL: appBundleURL,
            mainResourceURL: mainResourceURL,
            executableURL: executableURL
        )

        XCTAssertEqual(
            candidates.map(\.path),
            [
                "/Applications/Jack.app/Gilt_Gilt.bundle",
                "/Applications/Jack.app/Contents/Resources/Gilt_Gilt.bundle",
                "/Applications/Jack.app/Contents/MacOS/Gilt_Gilt.bundle",
            ]
        )
    }

    func testAppResourceLocatorBundleCandidatesIncludeBuildProductsFallback() {
        let buildBundleURL = URL(fileURLWithPath: "/tmp/Gilt", isDirectory: false)

        XCTAssertEqual(
            AppResourceLocator.bundleURLCandidates(
                bundleName: "Gilt_Gilt.bundle",
                mainBundleURL: URL(fileURLWithPath: "/tmp/Gilt", isDirectory: true),
                mainResourceURL: nil,
                executableURL: buildBundleURL
            ).last?.path,
            "/tmp/Gilt_Gilt.bundle"
        )
    }

    func testAppResourceLocatorReturnsMainBundleWhenResourceBundleIsMissing() {
        let missingRoot = URL(fileURLWithPath: "/tmp/gilt-missing-bundle", isDirectory: true)

        XCTAssertEqual(
            AppResourceLocator.resourceBundle(
                bundleName: "Missing.bundle",
                mainBundleURL: missingRoot,
                mainResourceURL: nil,
                executableURL: nil
            ),
            .main
        )
    }

    func testAppAttributionIncludesLilAgentsMITNotice() {
        XCTAssertEqual(AppAttribution.copyright, "Copyright © 2025-2026 Praise Adesokan. All rights reserved.")
        XCTAssertTrue(AppAttribution.openSourceCreditsText.contains("Lil Agents"))
        XCTAssertTrue(AppAttribution.openSourceCreditsText.contains("Copyright (c) 2026 Ryan Stephen"))
        XCTAssertTrue(AppAttribution.openSourceCreditsText.contains("Licensed under the MIT License"))
        XCTAssertTrue(AppAttribution.openSourceCreditsText.contains("https://github.com/ryanstephen/lil-agents"))
        XCTAssertTrue(AppAttribution.openSourceCreditsText.contains("The above copyright notice and this permission notice"))
    }

    func testDmgBuilderDefaultsToReleaseConfiguration() throws {
        let script = try projectFile("scripts/build-dmg.sh")

        XCTAssertTrue(script.contains("CONFIG=\"${1:-release}\""))
        XCTAssertTrue(script.contains("DMG_STEM=\"${DMG_NAME%.dmg}\""))
    }

    func testReleaseScriptsKeepLegacyGiltDownloadNames() throws {
        let publisher = try projectFile("scripts/publish-r2-release.sh")
        let appcast = try projectFile("scripts/update-sparkle-appcast.sh")
        let versionManifest = try projectFile("version.json")

        XCTAssertTrue(publisher.contains("RELEASE_BASENAME=\"${RELEASE_BASENAME:-Gilt}\""))
        XCTAssertTrue(publisher.contains("VERSIONED_DMG_NAME=\"${RELEASE_BASENAME}-${VERSION}.dmg\""))
        XCTAssertTrue(appcast.contains("$ARCHIVES_DIR/${RELEASE_BASENAME}-${VERSION}.dmg"))
        XCTAssertTrue(versionManifest.contains("https://downloads.gilt.novor.dev/Gilt.dmg"))
    }

    private func projectFile(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
