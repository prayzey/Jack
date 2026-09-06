import XCTest
@testable import Gilt

/// Tests for LinkPlatform detection, LinkMetadataService parsing, and HTML utilities.
final class LinkParsingTests: XCTestCase {

    // MARK: - Platform Detection

    func testDetectsYouTube() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .youtube)
    }

    func testDetectsYouTubeShortURL() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .youtube)
    }

    func testDetectsYouTubeMusic() {
        let url = URL(string: "https://music.youtube.com/watch?v=abc123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .youtubeMusic)
    }

    func testYouTubeMusicTakesPriorityOverYouTube() {
        // music.youtube.com contains "youtube.com" — verify ordering handles it
        let musicURL = URL(string: "https://music.youtube.com/watch?v=abc")!
        XCTAssertEqual(LinkPlatform.detect(from: musicURL), .youtubeMusic,
                        "music.youtube.com should be youtubeMusic, not youtube")
    }

    func testDetectsSpotify() {
        let url = URL(string: "https://open.spotify.com/track/123abc")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .spotify)
    }

    func testDetectsAppleMusic() {
        let url = URL(string: "https://music.apple.com/us/album/some-album/123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .appleMusic)
    }

    func testDetectsAppStore() {
        let url = URL(string: "https://apps.apple.com/us/app/some-app/id123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .appStore)
    }

    func testDetectsGitHub() {
        let url = URL(string: "https://github.com/user/repo")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .github)
    }

    func testDetectsTwitter() {
        let url = URL(string: "https://twitter.com/user/status/123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .twitter)
    }

    func testDetectsXDotCom() {
        let url = URL(string: "https://x.com/user/status/456")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .twitter)
    }

    func testDetectsReddit() {
        let url = URL(string: "https://www.reddit.com/r/swift/comments/abc123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .reddit)
    }

    func testDetectsVimeo() {
        let url = URL(string: "https://vimeo.com/123456789")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .vimeo)
    }

    func testDetectsSoundCloud() {
        let url = URL(string: "https://soundcloud.com/artist/track")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .soundcloud)
    }

    func testDetectsTidal() {
        let url = URL(string: "https://listen.tidal.com/album/123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .tidal)
    }

    func testDetectsDeezer() {
        let url = URL(string: "https://www.deezer.com/track/123")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .deezer)
    }

    func testDetectsPlayStore() {
        let url = URL(string: "https://play.google.com/store/apps/details?id=com.example")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .playStore)
    }

    func testReturnsNilForUnknownDomain() {
        let url = URL(string: "https://www.randomsite.com/page")!
        XCTAssertNil(LinkPlatform.detect(from: url))
    }

    func testReturnsNilForFileURL() {
        let url = URL(string: "file:///local/path")!
        XCTAssertNil(LinkPlatform.detect(from: url), "file:// URLs have no HTTP host")
    }

    func testDetectionIsCaseInsensitive() {
        let url = URL(string: "https://YOUTUBE.COM/watch?v=abc")!
        XCTAssertEqual(LinkPlatform.detect(from: url), .youtube,
                        "Platform detection should be case-insensitive")
    }

    // MARK: - Platform Properties

    func testPlatformDisplayNames() {
        XCTAssertEqual(LinkPlatform.youtube.displayName, "YouTube")
        XCTAssertEqual(LinkPlatform.github.displayName, "GitHub")
        XCTAssertEqual(LinkPlatform.twitter.displayName, "Twitter")
        XCTAssertEqual(LinkPlatform.youtubeMusic.displayName, "YT Music")
    }

    // MARK: - YouTube Video ID Extraction

    func testExtractsYouTubeIDFromWatchURL() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertEqual(LinkMetadataService.extractYouTubeVideoID(from: url), "dQw4w9WgXcQ")
    }

    func testExtractsYouTubeIDFromShortURL() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(LinkMetadataService.extractYouTubeVideoID(from: url), "dQw4w9WgXcQ")
    }

    func testExtractsYouTubeIDFromShortsURL() {
        let url = URL(string: "https://www.youtube.com/shorts/abcXYZ123")!
        XCTAssertEqual(LinkMetadataService.extractYouTubeVideoID(from: url), "abcXYZ123")
    }

    func testExtractsYouTubeIDFromEmbedURL() {
        let url = URL(string: "https://www.youtube.com/embed/abcXYZ123")!
        XCTAssertEqual(LinkMetadataService.extractYouTubeVideoID(from: url), "abcXYZ123")
    }

    func testExtractsYouTubeIDFromMusicURL() {
        let url = URL(string: "https://music.youtube.com/watch?v=musicID123")!
        XCTAssertEqual(LinkMetadataService.extractYouTubeVideoID(from: url), "musicID123")
    }

    func testReturnsNilForYouTubeURLWithoutVideoID() {
        let url = URL(string: "https://www.youtube.com/channel/UCxyz")!
        XCTAssertNil(LinkMetadataService.extractYouTubeVideoID(from: url),
                      "Channel URLs have no video ID")
    }

    func testReturnsNilForNonYouTubeURL() {
        let url = URL(string: "https://www.example.com/watch?v=fake")!
        // This should still work since it uses URLComponents query parsing
        // But the caller would only invoke this for YouTube URLs
        // The function itself just parses the ?v= param, so this returns "fake"
        // That's the expected behavior — the function extracts, it doesn't validate domain
        let id = LinkMetadataService.extractYouTubeVideoID(from: url)
        XCTAssertEqual(id, "fake", "Function extracts ?v= regardless of domain (caller validates)")
    }

    // MARK: - HTML Title Extraction

    func testExtractsTitleFromBasicHTML() {
        let html = "<html><head><title>My Page Title</title></head><body></body></html>"
        XCTAssertEqual(LinkMetadataService.extractTitle(fromHTML: html), "My Page Title")
    }

    func testExtractsTitleWithHTMLEntities() {
        let html = "<title>Tom &amp; Jerry&#39;s Page</title>"
        XCTAssertEqual(LinkMetadataService.extractTitle(fromHTML: html), "Tom & Jerry's Page")
    }

    func testReturnsNilForEmptyTitle() {
        let html = "<html><head><title></title></head></html>"
        XCTAssertNil(LinkMetadataService.extractTitle(fromHTML: html), "Empty title should return nil")
    }

    func testReturnsNilForNoTitleTag() {
        let html = "<html><head></head><body>No title</body></html>"
        XCTAssertNil(LinkMetadataService.extractTitle(fromHTML: html))
    }

    // MARK: - Open Graph Tag Extraction

    func testExtractsOGTitlePropertyFirst() {
        let html = """
        <meta property="og:title" content="OG Title Here">
        """
        XCTAssertEqual(LinkMetadataService.extractOGTag(fromHTML: html, property: "og:title"), "OG Title Here")
    }

    func testExtractsOGTitleContentFirst() {
        // Some sites put content before property
        let html = """
        <meta content="Reversed OG Title" property="og:title">
        """
        XCTAssertEqual(LinkMetadataService.extractOGTag(fromHTML: html, property: "og:title"), "Reversed OG Title")
    }

    func testExtractsOGDescription() {
        let html = """
        <meta property="og:description" content="A great description.">
        """
        XCTAssertEqual(LinkMetadataService.extractOGTag(fromHTML: html, property: "og:description"), "A great description.")
    }

    func testReturnsNilForMissingOGTag() {
        let html = "<html><head></head></html>"
        XCTAssertNil(LinkMetadataService.extractOGTag(fromHTML: html, property: "og:title"))
    }

    func testOGTagDecodesHTMLEntities() {
        let html = """
        <meta property="og:title" content="Rock &amp; Roll">
        """
        XCTAssertEqual(LinkMetadataService.extractOGTag(fromHTML: html, property: "og:title"), "Rock & Roll")
    }

    // MARK: - Meta Content Extraction

    func testExtractsMetaDescription() {
        let html = """
        <meta name="description" content="Page description here.">
        """
        XCTAssertEqual(LinkMetadataService.extractMetaContent(fromHTML: html, name: "description"), "Page description here.")
    }

    func testExtractsMetaContentReversedOrder() {
        let html = """
        <meta content="Reversed content" name="description">
        """
        XCTAssertEqual(LinkMetadataService.extractMetaContent(fromHTML: html, name: "description"), "Reversed content")
    }

    // MARK: - Apple Touch Icon Extraction

    func testExtractsAppleTouchIcon() {
        let html = """
        <link rel="apple-touch-icon" href="/apple-icon-180.png">
        """
        XCTAssertEqual(LinkMetadataService.extractAppleTouchIcon(fromHTML: html), "/apple-icon-180.png")
    }

    func testExtractsAppleTouchIconReversedAttrs() {
        let html = """
        <link href="/icon.png" rel="apple-touch-icon-precomposed">
        """
        XCTAssertEqual(LinkMetadataService.extractAppleTouchIcon(fromHTML: html), "/icon.png")
    }

    func testExtractsGenericShortcutIconWhenAppleTouchIconMissing() {
        let html = """
        <link rel="shortcut icon" href="favicon.ico">
        """
        XCTAssertEqual(LinkMetadataService.extractIconLink(fromHTML: html), "favicon.ico")
    }

    func testExtractsGenericIconReversedAttrs() {
        let html = """
        <link href="/assets/site-icon.png" rel="icon">
        """
        XCTAssertEqual(LinkMetadataService.extractIconLink(fromHTML: html), "/assets/site-icon.png")
    }

    // MARK: - ISO 8601 Duration Formatting

    func testFormatsFullDuration() {
        XCTAssertEqual(LinkMetadataService.formatISO8601Duration("PT1H2M3S"), "1:02:03")
    }

    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(LinkMetadataService.formatISO8601Duration("PT3M42S"), "3:42")
    }

    func testFormatsSecondsOnly() {
        XCTAssertEqual(LinkMetadataService.formatISO8601Duration("PT30S"), "0:30")
    }

    func testFormatsHoursOnly() {
        XCTAssertEqual(LinkMetadataService.formatISO8601Duration("PT1H"), "1:00:00")
    }

    func testFormatsMinutesOnly() {
        XCTAssertEqual(LinkMetadataService.formatISO8601Duration("PT5M"), "5:00")
    }

    func testReturnsNilForZeroDuration() {
        XCTAssertNil(LinkMetadataService.formatISO8601Duration("PT0S"), "Zero duration should return nil")
    }

    func testReturnsNilForInvalidDuration() {
        XCTAssertNil(LinkMetadataService.formatISO8601Duration("garbage"), "Invalid string should return nil")
    }

    // MARK: - Duration Seconds Formatting

    func testFormatsDurationSecondsShort() {
        XCTAssertEqual(LinkMetadataService.formatDurationSeconds(62), "1:02")
    }

    func testFormatsDurationSecondsWithHours() {
        // 1 hour + 2 minutes + 3 seconds = 3723 seconds
        XCTAssertEqual(LinkMetadataService.formatDurationSeconds(1 * 3600 + 2 * 60 + 3), "1:02:03")
    }

    func testFormatsDurationSecondsZero() {
        XCTAssertEqual(LinkMetadataService.formatDurationSeconds(0), "0:00")
    }

    func testFormatsDurationSecondsBoundary() {
        // 3599 seconds = 59 minutes 59 seconds (just under 1 hour)
        XCTAssertEqual(LinkMetadataService.formatDurationSeconds(3599), "59:59")
        // 3600 seconds = exactly 1 hour
        XCTAssertEqual(LinkMetadataService.formatDurationSeconds(3600), "1:00:00")
    }

    // MARK: - URL Resolution

    func testResolvesBareRelativeURLAgainstPageURL() {
        let pageURL = URL(string: "https://icrp.cac.gov.ng")!
        let result = LinkMetadataService.resolveURL("favicon.ico", against: pageURL)
        XCTAssertEqual(result?.absoluteString, "https://icrp.cac.gov.ng/favicon.ico")
    }

    func testResolvesNestedRelativeURLAgainstPagePath() {
        let pageURL = URL(string: "https://example.com/docs/page")!
        let result = LinkMetadataService.resolveURL("../favicon.png", against: pageURL)
        XCTAssertEqual(result?.absoluteString, "https://example.com/favicon.png")
    }

    // MARK: - HTML Entity Decoding

    func testDecodesBasicHTMLEntities() {
        XCTAssertEqual("&amp;".decodingHTMLEntities(), "&")
        XCTAssertEqual("&lt;".decodingHTMLEntities(), "<")
        XCTAssertEqual("&gt;".decodingHTMLEntities(), ">")
        XCTAssertEqual("&quot;".decodingHTMLEntities(), "\"")
        XCTAssertEqual("&#39;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&apos;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&nbsp;".decodingHTMLEntities(), " ")
    }

    func testDecodesNamedNumericEntities() {
        XCTAssertEqual("&#8211;".decodingHTMLEntities(), "\u{2013}") // en-dash
        XCTAssertEqual("&#8212;".decodingHTMLEntities(), "\u{2014}") // em-dash
        XCTAssertEqual("&#8217;".decodingHTMLEntities(), "\u{2019}") // right single quote
    }

    func testDecodesArbitraryNumericEntityViaRegex() {
        // &#169; is copyright symbol — NOT in the hardcoded list, exercises the regex path
        XCTAssertEqual("&#169;".decodingHTMLEntities(), "\u{00A9}")
    }

    func testDecodesHexNumericEntities() {
        XCTAssertEqual("&#xE9;".decodingHTMLEntities(), "\u{00E9}") // é lowercase hex prefix
        XCTAssertEqual("&#X2019;".decodingHTMLEntities(), "\u{2019}") // uppercase X also valid
    }

    func testDecodesMultipleEntitiesInOneString() {
        let input = "Tom &amp; Jerry &lt;3"
        let expected = "Tom & Jerry <3"
        XCTAssertEqual(input.decodingHTMLEntities(), expected)
    }

    func testPlainTextPassesThroughUnchanged() {
        let plain = "No entities here"
        XCTAssertEqual(plain.decodingHTMLEntities(), plain)
    }

    func testMalformedEntityPassesThrough() {
        let malformed = "&bogus; stays unchanged"
        XCTAssertEqual(malformed.decodingHTMLEntities(), malformed, "Unrecognized entities should pass through")
    }
}
