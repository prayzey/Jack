import AppKit
import Foundation

struct ClipBrowserActionPlan: Equatable {
    enum Destination: Equatable {
        case openURL(URL)
        case search(URL)
    }

    let destination: Destination

    var menuLabel: String {
        switch destination {
        case .openURL:
            return L10n.string("clipAction.browser.open", default: "Open in Browser")
        case .search:
            return L10n.string("clipAction.browser.search", default: "Search in Browser")
        }
    }

    var systemImage: String {
        switch destination {
        case .openURL:
            return "safari"
        case .search:
            return "magnifyingglass"
        }
    }
}

struct ClipEmailActionPlan: Equatable {
    let subject: String
    let body: String
    let hasImageAttachments: Bool

    var menuLabel: String {
        hasImageAttachments
            ? L10n.string("clipAction.email.menu.withImage", default: "Send as Email (with image)")
            : L10n.string("clipAction.email.menu.default", default: "Send as Email")
    }
}

@MainActor
final class ClipActionService {
    static let shared = ClipActionService()

    private init() {}

    func openInBrowser(clips: [ClipItemModel]) -> Bool {
        guard let plan = Self.planBrowserAction(for: clips) else {
            return false
        }

        let targetURL: URL
        switch plan.destination {
        case .openURL(let url), .search(let url):
            targetURL = url
        }
        return NSWorkspace.shared.open(targetURL)
    }

    func sendAsEmail(clips: [ClipItemModel]) -> Bool {
        guard let plan = Self.planEmailAction(for: clips) else {
            return false
        }

        if plan.hasImageAttachments {
            let items = composeEmailItems(clips: clips, body: plan.body)
            if performComposeEmail(items: items, subject: plan.subject) {
                return true
            }
        }

        guard let mailtoURL = Self.makeMailtoURL(subject: plan.subject, body: plan.body) else {
            return false
        }

        // If macOS resolves mailto to the same app as https (usually a browser),
        // prefer composeEmail so users still get an email draft UI.
        if shouldUseComposeEmailFallback(for: mailtoURL),
           performComposeEmail(items: [plan.body], subject: plan.subject) {
            return true
        }

        let didOpenMailto = NSWorkspace.shared.open(mailtoURL)
        if didOpenMailto {
            return true
        }

        return performComposeEmail(items: [plan.body], subject: plan.subject)
    }

    nonisolated static func planBrowserAction(for clips: [ClipItemModel]) -> ClipBrowserActionPlan? {
        guard !clips.isEmpty else { return nil }

        if clips.count == 1,
           let directURL = preferredDirectURL(for: clips[0]) {
            return ClipBrowserActionPlan(destination: .openURL(directURL))
        }

        guard let query = combinedTextPayload(for: clips),
              query.isEmpty == false,
              let searchURL = makeSearchURL(query: query)
        else {
            return nil
        }

        return ClipBrowserActionPlan(destination: .search(searchURL))
    }

    nonisolated static func planEmailAction(for clips: [ClipItemModel]) -> ClipEmailActionPlan? {
        guard !clips.isEmpty else { return nil }

        let body = emailBody(for: clips)
        let subject = emailSubject(for: clips)
        let hasImageAttachments = clips.contains { $0.imageData != nil }

        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !hasImageAttachments {
            return nil
        }

        return ClipEmailActionPlan(
            subject: subject,
            body: body,
            hasImageAttachments: hasImageAttachments
        )
    }

    nonisolated static func makeMailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    nonisolated private static func preferredDirectURL(for clip: ClipItemModel) -> URL? {
        if let rawURL = clip.urlValue,
           let normalized = normalizeWebURL(rawURL) {
            return normalized
        }

        let candidate = clip.textValue ?? clip.previewText
        return normalizeWebURL(candidate)
    }

    nonisolated static func normalizeWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let parsed = URL(string: trimmed),
           let scheme = parsed.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           parsed.host?.isEmpty == false {
            return parsed
        }

        if trimmed.contains(" ") {
            return nil
        }

        // Support copied domains without scheme: "example.com/docs"
        // But reject strings that look like filenames with known code/doc extensions —
        // "wow.md" is a Markdown file, not the domain wow.md (Moldova).
        // Many code extensions overlap with real TLDs (.rs, .py, .sh, .io, etc.),
        // so without this guard, copying a filename from a terminal or editor would
        // create a broken link card instead of a text card.
        // The shared `knownCodeExtensions` set (in CreativeTextPreviews.swift) is the
        // single source of truth for recognized file extensions.
        if trimmed.contains("."),
           let withScheme = URL(string: "https://\(trimmed)"),
           withScheme.host?.isEmpty == false {
            // Check if this looks like a filename rather than a domain
            if looksLikeFilename(trimmed) { return nil }
            // Reject email addresses like "support@example.com". URL parsing treats
            // text before `@` as userinfo (e.g. `https://user@host`), so without this
            // guard `URL(string:)` happily accepts emails as valid hosted URLs and we
            // turn `support@example.com` into `https://support@example.com`.
            // A real URL with userinfo always carries a scheme already (handled above),
            // so a scheme-less `@` in the authority position is always an email.
            if looksLikeEmail(trimmed) { return nil }
            return withScheme
        }

        return nil
    }

    /// Returns true if the input looks like an email address rather than a URL.
    /// We only need to detect the bare `user@host.tld` shape — anything with a path
    /// before the `@` (e.g. `example.com/page@anchor`) is treated as a URL.
    nonisolated private static func looksLikeEmail(_ text: String) -> Bool {
        // If there's a slash before the @, the @ is in the path, not the authority.
        let authority: Substring
        if let slash = text.firstIndex(of: "/") {
            authority = text[..<slash]
        } else {
            authority = Substring(text)
        }
        guard let at = authority.firstIndex(of: "@") else { return false }
        let local = authority[..<at]
        let domain = authority[authority.index(after: at)...]
        // Both halves non-empty and domain contains a dot — that's an email shape.
        return local.isEmpty == false && domain.contains(".")
    }

    /// Returns true if the string looks like a bare filename with a known code/document extension
    /// rather than a domain name or URL path. Prevents "README.md", "app.py", "main.rs" from
    /// being misclassified as URLs.
    ///
    /// Only matches simple filenames without path separators. If the text contains a slash
    /// (e.g., "example.com/file.py"), it's a URL path and should be treated as a valid URL —
    /// not rejected as a filename.
    nonisolated private static func looksLikeFilename(_ text: String) -> Bool {
        // If text contains slashes, it's a URL path like "example.com/file.py", not a bare filename
        if text.contains("/") { return false }
        guard let dotIndex = text.lastIndex(of: ".") else { return false }
        let ext = String(text[text.index(after: dotIndex)...]).lowercased()
        return knownCodeExtensions.contains(ext)
    }

    nonisolated private static func combinedTextPayload(for clips: [ClipItemModel]) -> String? {
        let values = clips.compactMap { textualPayload(for: $0) }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: "\n")
    }

    nonisolated private static func textualPayload(for clip: ClipItemModel) -> String? {
        if let url = clip.urlValue?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            return url
        }

        if let text = clip.textValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        // Avoid low-value placeholders for non-text clips.
        if clip.clipType == .text || clip.clipType == .audio || clip.clipType == .color {
            let preview = clip.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.isEmpty ? nil : preview
        }

        return nil
    }

    nonisolated private static func makeSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    nonisolated private static func emailSubject(for clips: [ClipItemModel]) -> String {
        if clips.count > 1 {
            let format = L10n.string(
                "clipAction.email.subject.multiple",
                default: "Shared %lld Clips from Jack"
            )
            return String(format: format, locale: Locale.autoupdatingCurrent, clips.count)
        }

        guard let clip = clips.first else {
            return L10n.string("clipAction.email.subject.default", default: "Shared Clip from Jack")
        }

        switch clip.clipType {
        case .link: return L10n.string("clipAction.email.subject.link", default: "Shared Link from Jack")
        case .image: return L10n.string("clipAction.email.subject.image", default: "Shared Image from Jack")
        case .audio: return L10n.string("clipAction.email.subject.audio", default: "Shared Audio Note from Jack")
        case .color: return L10n.string("clipAction.email.subject.color", default: "Shared Color from Jack")
        case .text: return L10n.string("clipAction.email.subject.text", default: "Shared Text from Jack")
        }
    }

    nonisolated private static func emailBody(for clips: [ClipItemModel]) -> String {
        let values = clips.compactMap { textualPayload(for: $0) }
        if values.isEmpty {
            return "Shared from Jack."
        }
        return values.joined(separator: "\n\n")
    }

    private func composeEmailItems(clips: [ClipItemModel], body: String) -> [Any] {
        var items: [Any] = []
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            items.append(body)
        }

        for clip in clips {
            guard let data = clip.imageData else { continue }
            let filename = "jack-image-\(clip.clipID.uuidString).png"
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            do {
                try data.write(to: fileURL, options: .atomic)
                items.append(fileURL)
            } catch {
                continue
            }
        }

        return items
    }

    private func performComposeEmail(items: [Any], subject: String) -> Bool {
        guard let sharingService = NSSharingService(named: .composeEmail),
              !items.isEmpty else {
            return false
        }
        sharingService.subject = subject
        sharingService.perform(withItems: items)
        return true
    }

    private func shouldUseComposeEmailFallback(for mailtoURL: URL) -> Bool {
        guard let mailHandler = NSWorkspace.shared.urlForApplication(toOpen: mailtoURL),
              let webURL = URL(string: "https://example.com"),
              let webHandler = NSWorkspace.shared.urlForApplication(toOpen: webURL)
        else {
            return false
        }
        return mailHandler == webHandler
    }
}
