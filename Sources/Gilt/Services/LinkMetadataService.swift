import Foundation
import OSLog

struct LinkMetadata: Sendable {
    var pageTitle: String?
    var pageDescription: String?
    var faviconURL: URL?
    var thumbnailURL: URL?
    var thumbnailData: Data?
    var platform: LinkPlatform?
    var videoDuration: String?
}

actor LinkMetadataService {
    static let shared = LinkMetadataService()

    private struct CacheEntry {
        var metadata: LinkMetadata
        var costBytes: Int
        var accessOrder: UInt64
    }

    private var cache: [String: CacheEntry] = [:]
    private let maxCacheSize = 200
    private let maxCacheBytes = 24 * 1024 * 1024  // 24 MB cap for in-memory metadata blobs
    private let warningTargetBytes = 12 * 1024 * 1024
    private var cacheBytes = 0
    private var accessCounter: UInt64 = 0

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "LinkMetadata")
    private let perfLoggingEnabled = ProcessInfo.processInfo.environment["GILT_DEBUG_LOGS"] == "1"

    // Aggregate stats for periodic health checks
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var fetchSuccesses: Int = 0
    private var fetchFailures: Int = 0
    private var totalFetchMs: Double = 0
    private var totalParseMs: Double = 0
    private var totalThumbDownloadMs: Double = 0
    private var evictionCount: Int = 0

    func metadata(for rawURL: String) async -> LinkMetadata? {
        let overallStart = DispatchTime.now()

        guard let url = URL(string: rawURL),
              let host = url.host(percentEncoded: false) else {
            logPerf("skip invalidURL")
            return nil
        }

        // Cache by full URL (per-page thumbnails differ)
        if var cached = cache[rawURL] {
            cacheHits += 1
            accessCounter &+= 1
            cached.accessOrder = accessCounter
            cache[rawURL] = cached
            logPerf("cacheHit host=\(host) hits=\(cacheHits) misses=\(cacheMisses) ratio=\(cacheHitRatio)")
            return cached.metadata
        }
        cacheMisses += 1

        let platform = LinkPlatform.detect(from: url)
        let defaultFavicon = URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")

        var metadata = LinkMetadata(
            faviconURL: defaultFavicon,
            platform: platform
        )

        // Fetch HTML page
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        // Use a real browser user-agent so sites return full og: tags
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let fetchStart = DispatchTime.now()
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {

            let fetchMs = elapsedMs(since: fetchStart)
            totalFetchMs += fetchMs
            fetchSuccesses += 1
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logPerf("htmlFetch host=\(host) status=\(statusCode) size=\(data.count)B time=\(fmt(fetchMs))ms")

            // Parse HTML metadata
            let parseStart = DispatchTime.now()

            // Title: prefer og:title, fall back to <title>
            metadata.pageTitle = Self.extractOGTag(fromHTML: html, property: "og:title")
                ?? Self.extractTitle(fromHTML: html)

            // Description: og:description or meta description
            metadata.pageDescription = Self.extractOGTag(fromHTML: html, property: "og:description")
                ?? Self.extractMetaContent(fromHTML: html, name: "description")

            // Thumbnail URL: platform-specific first, then og:image, then twitter:image
            let thumbnailString = Self.platformThumbnailURL(for: url, platform: platform)
                ?? Self.extractOGTag(fromHTML: html, property: "og:image")
                ?? Self.extractMetaContent(fromHTML: html, name: "twitter:image")
                ?? Self.extractOGTag(fromHTML: html, property: "twitter:image")

            if let urlStr = thumbnailString {
                metadata.thumbnailURL = Self.resolveURL(urlStr, against: url)
            }

            // Prefer site-provided icons before falling back to Google's favicon proxy.
            if let iconHref = Self.extractAppleTouchIcon(fromHTML: html)
                ?? Self.extractIconLink(fromHTML: html) {
                metadata.faviconURL = Self.resolveURL(iconHref, against: url) ?? defaultFavicon
            }

            // Video duration (YouTube, Vimeo)
            if platform == .youtube || platform == .youtubeMusic {
                metadata.videoDuration = Self.extractYouTubeDuration(fromHTML: html)
            } else if platform == .vimeo {
                metadata.videoDuration = Self.extractISO8601Duration(fromHTML: html)
            }

            let parseMs = elapsedMs(since: parseStart)
            totalParseMs += parseMs
            logPerf(
                "htmlParse host=\(host) time=\(fmt(parseMs))ms "
                    + "title=\(metadata.pageTitle != nil) "
                    + "thumb=\(metadata.thumbnailURL != nil) "
                    + "platform=\(platform?.rawValue ?? "nil")"
            )
        } else {
            let fetchMs = elapsedMs(since: fetchStart)
            totalFetchMs += fetchMs
            fetchFailures += 1
            logPerf("htmlFetch FAILED host=\(host) time=\(fmt(fetchMs))ms successes=\(fetchSuccesses) failures=\(fetchFailures)")

            // HTML fetch failed — still try platform-specific thumbnail
            if let thumbStr = Self.platformThumbnailURL(for: url, platform: platform) {
                metadata.thumbnailURL = URL(string: thumbStr)
            }
        }

        // Download thumbnail image data for local caching
        if let thumbURL = metadata.thumbnailURL {
            let thumbStart = DispatchTime.now()
            metadata.thumbnailData = await Self.downloadThumbnail(from: thumbURL)
            let thumbMs = elapsedMs(since: thumbStart)
            totalThumbDownloadMs += thumbMs
            logPerf(
                "thumbDownload host=\(host) size=\(metadata.thumbnailData?.count ?? 0)B "
                    + "time=\(fmt(thumbMs))ms ok=\(metadata.thumbnailData != nil)"
            )
        }

        cacheInsert(metadata, for: rawURL)
        let totalMs = elapsedMs(since: overallStart)
        logPerf(
            "complete host=\(host) totalTime=\(fmt(totalMs))ms cacheSize=\(cache.count) cacheMB=\(fmt(Double(cacheBytes) / 1_048_576)) "
                + "avgFetch=\(fmt(avgFetchMs))ms avgParse=\(fmt(avgParseMs))ms"
        )
        return metadata
    }

    func handleMemoryPressure(isCritical: Bool) {
        let beforeEntries = cache.count
        let beforeBytes = cacheBytes

        if isCritical {
            cache.removeAll()
            cacheBytes = 0
            logPerf(
                "memoryPressure CRITICAL clearedCache entries=\(beforeEntries) "
                    + "bytes=\(beforeBytes)"
            )
            return
        }

        trimCacheIfNeeded(targetBytes: warningTargetBytes)
        let removed = beforeEntries - cache.count
        if removed > 0 || beforeBytes != cacheBytes {
            logPerf(
                "memoryPressure WARNING trimmed entries=\(removed) "
                    + "bytesBefore=\(beforeBytes) bytesAfter=\(cacheBytes)"
            )
        }
    }

    private var cacheHitRatio: String {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", Double(cacheHits) / Double(total) * 100)
    }

    private var avgFetchMs: Double {
        let total = fetchSuccesses + fetchFailures
        guard total > 0 else { return 0 }
        return totalFetchMs / Double(total)
    }

    private var avgParseMs: Double {
        guard fetchSuccesses > 0 else { return 0 }
        return totalParseMs / Double(fetchSuccesses)
    }

    private func elapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private func fmt(_ ms: Double) -> String {
        String(format: "%.2f", ms)
    }

    private func logPerf(_ message: String) {
        guard perfLoggingEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    private func cacheInsert(_ metadata: LinkMetadata, for key: String) {
        if cache[key] != nil {
            removeCacheEntry(for: key)
        }
        accessCounter &+= 1
        let cost = estimatedCostBytes(for: metadata)
        cache[key] = CacheEntry(metadata: metadata, costBytes: cost, accessOrder: accessCounter)
        cacheBytes += cost
        trimCacheIfNeeded(targetBytes: maxCacheBytes)
    }

    private func trimCacheIfNeeded(targetBytes: Int) {
        var removed = 0
        while cache.count > maxCacheSize || cacheBytes > targetBytes {
            guard let oldestKey = cache.min(by: { $0.value.accessOrder < $1.value.accessOrder })?.key else {
                break
            }
            removeCacheEntry(for: oldestKey)
            removed += 1
        }
        if removed > 0 {
            evictionCount += removed
            logPerf(
                "cacheEvict removed=\(removed) totalEvictions=\(evictionCount) "
                    + "cacheSize=\(cache.count) cacheBytes=\(cacheBytes)"
            )
        }
    }

    private func removeCacheEntry(for key: String) {
        guard let removed = cache.removeValue(forKey: key) else { return }
        cacheBytes = max(0, cacheBytes - removed.costBytes)
    }

    private func estimatedCostBytes(for metadata: LinkMetadata) -> Int {
        // Rough accounting to keep cache bounded:
        // Strings/URLs by utf8 length + binary payload by byte length + object overhead.
        var total = 192
        total += metadata.pageTitle?.utf8.count ?? 0
        total += metadata.pageDescription?.utf8.count ?? 0
        total += metadata.faviconURL?.absoluteString.utf8.count ?? 0
        total += metadata.thumbnailURL?.absoluteString.utf8.count ?? 0
        total += metadata.thumbnailData?.count ?? 0
        total += metadata.videoDuration?.utf8.count ?? 0
        total += metadata.platform?.rawValue.utf8.count ?? 0
        return total
    }

    // MARK: - Platform-Specific Thumbnail URLs

    private static func platformThumbnailURL(for url: URL, platform: LinkPlatform?) -> String? {
        guard let platform else { return nil }

        switch platform {
        case .youtube, .youtubeMusic:
            if let videoID = extractYouTubeVideoID(from: url) {
                // hqdefault (480x360) is always available; maxresdefault may 404
                return "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
            }
        default:
            break // Other platforms use og:image extracted from HTML
        }

        return nil
    }

    /// Extract YouTube video ID from various URL formats
    static func extractYouTubeVideoID(from url: URL) -> String? {
        // youtube.com/watch?v=VIDEO_ID or music.youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoID.isEmpty {
            return videoID
        }

        // youtu.be/VIDEO_ID
        if url.host(percentEncoded: false)?.contains("youtu.be") == true {
            let path = url.path
            let id = path.hasPrefix("/") ? String(path.dropFirst()) : path
            if !id.isEmpty { return id.components(separatedBy: "?").first }
        }

        // youtube.com/shorts/VIDEO_ID
        if let idx = url.pathComponents.firstIndex(of: "shorts"), idx + 1 < url.pathComponents.count {
            return url.pathComponents[idx + 1]
        }

        // youtube.com/embed/VIDEO_ID
        if let idx = url.pathComponents.firstIndex(of: "embed"), idx + 1 < url.pathComponents.count {
            return url.pathComponents[idx + 1]
        }

        return nil
    }

    // MARK: - HTML Tag Extraction

    static func extractTitle(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<title[^>]*>(.*?)</title>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let titleRange = Range(match.range(at: 1), in: html) else { return nil }

        let title = String(html[titleRange])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decodingHTMLEntities()

        return title.isEmpty ? nil : title
    }

    /// Extract Open Graph meta tag: <meta property="og:xxx" content="...">
    static func extractOGTag(fromHTML html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        // Try property-first: <meta property="og:title" content="...">
        if let v = regexCapture("meta[^>]+property=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']*)[\"']", in: html) {
            let decoded = v.decodingHTMLEntities()
            return decoded.isEmpty ? nil : decoded
        }
        // Try content-first: <meta content="..." property="og:title">
        if let v = regexCapture("meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']\(escaped)[\"']", in: html) {
            let decoded = v.decodingHTMLEntities()
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }

    /// Extract standard meta tag: <meta name="xxx" content="...">
    static func extractMetaContent(fromHTML html: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        if let v = regexCapture("meta[^>]+name=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']*)[\"']", in: html) {
            let decoded = v.decodingHTMLEntities()
            return decoded.isEmpty ? nil : decoded
        }
        if let v = regexCapture("meta[^>]+content=[\"']([^\"']*)[\"'][^>]+name=[\"']\(escaped)[\"']", in: html) {
            let decoded = v.decodingHTMLEntities()
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }

    /// Extract apple-touch-icon href (higher-res favicon)
    static func extractAppleTouchIcon(fromHTML html: String) -> String? {
        // Try rel-first
        if let v = regexCapture("link[^>]+rel=[\"']apple-touch-icon[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']", in: html) {
            return v
        }
        // Try href-first
        if let v = regexCapture("link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"']apple-touch-icon[^\"']*[\"']", in: html) {
            return v
        }
        return nil
    }

    /// Extract any generic favicon-ish link when apple-touch-icon is not present.
    static func extractIconLink(fromHTML html: String) -> String? {
        let patterns = [
            "link[^>]+rel=[\"'][^\"']*(?:shortcut\\s+icon|icon)[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']",
            "link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"'][^\"']*(?:shortcut\\s+icon|icon)[^\"']*[\"']",
        ]

        for pattern in patterns {
            if let value = regexCapture(pattern, in: html), !value.isEmpty {
                return value
            }
        }

        return nil
    }

    // MARK: - Video Duration Extraction

    /// Extract YouTube video duration from embedded structured data or player config
    private static func extractYouTubeDuration(fromHTML html: String) -> String? {
        // JSON-LD: "duration": "PT3M42S" (in <script> blocks, not HTML tags)
        if let iso = rawCapture("\"duration\"\\s*:\\s*\"(PT[^\"]+)\"", in: html) {
            return formatISO8601Duration(iso)
        }
        // itemprop: <meta itemprop="duration" content="PT3M42S"> (HTML tag)
        if let iso = regexCapture("meta[^>]+itemprop=[\"']duration[\"'][^>]+content=[\"']([^\"']+)[\"']", in: html) {
            return formatISO8601Duration(iso)
        }
        // Player response: "lengthSeconds":"123" (in JSON/script)
        if let secs = rawCapture("\"lengthSeconds\"\\s*:\\s*\"(\\d+)\"", in: html),
           let total = Int(secs) {
            return formatDurationSeconds(total)
        }
        return nil
    }

    /// Generic ISO 8601 duration extraction (for Vimeo etc.)
    private static func extractISO8601Duration(fromHTML html: String) -> String? {
        if let iso = rawCapture("\"duration\"\\s*:\\s*\"(PT[^\"]+)\"", in: html) {
            return formatISO8601Duration(iso)
        }
        return nil
    }

    /// Parse ISO 8601 duration like "PT1H2M3S" → "1:02:03"
    static func formatISO8601Duration(_ iso: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "PT(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?"),
              let match = regex.firstMatch(in: iso, range: NSRange(iso.startIndex..<iso.endIndex, in: iso)) else {
            return nil
        }

        func intAt(_ index: Int) -> Int {
            guard match.range(at: index).location != NSNotFound,
                  let r = Range(match.range(at: index), in: iso) else { return 0 }
            return Int(iso[r]) ?? 0
        }

        let h = intAt(1)
        let m = intAt(2)
        let s = intAt(3)
        let total = h * 3600 + m * 60 + s
        return total > 0 ? formatDurationSeconds(total) : nil
    }

    /// Format total seconds → "M:SS" or "H:MM:SS"
    static func formatDurationSeconds(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    // MARK: - Thumbnail Download

    private static func downloadThumbnail(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }

        // Validate response
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }

        // Sanity checks: at least 200 bytes (real image), at most 3MB
        guard data.count > 200, data.count < 3_000_000 else {
            return nil
        }

        return data
    }

    // MARK: - URL Resolution

    /// Resolve potentially relative URLs against a host
    static func resolveURL(_ urlStr: String, against pageURL: URL) -> URL? {
        let trimmed = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let absolute = URL(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absolute
        }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }

        return URL(string: trimmed, relativeTo: pageURL)?.absoluteURL
    }

    // MARK: - Regex Helper

    /// Capture group 1 from HTML tag patterns (auto-prepends `<` to anchor within tags)
    private static func regexCapture(_ pattern: String, in text: String) -> String? {
        return rawCapture("<" + pattern, in: text)
    }

    /// Capture group 1 from a raw regex pattern (no `<` prefix — for JSON/script content)
    private static func rawCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}

// MARK: - HTML Entity Decoding

extension String {
    func decodingHTMLEntities() -> String {
        var result = self
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&#x27;", "'"), ("&#x2F;", "/"), ("&nbsp;", " "),
            ("&#8211;", "\u{2013}"), ("&#8212;", "\u{2014}"),
            ("&#8217;", "\u{2019}"), ("&#8220;", "\u{201C}"),
            ("&#8221;", "\u{201D}"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Decode numeric entities: &#NNN; and &#xNN;
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|\\d+);", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            for match in regex.matches(in: result, range: range).reversed() {
                guard let numRange = Range(match.range(at: 1), in: result) else { continue }
                let token = result[numRange]
                let code: UInt32? = token.lowercased().hasPrefix("x")
                    ? UInt32(token.dropFirst(), radix: 16)
                    : UInt32(token)
                if let code, let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result
    }
}
