import Foundation

/// Pattern-matching content classifier for smart folder routing.
/// All methods are static — no instance state needed.
struct ContentClassifier {
    private struct WeightedRegex {
        let regex: NSRegularExpression
        let weight: Int
    }

    private struct WeightedLanguageRegex {
        let regex: NSRegularExpression
        let language: DetectedLanguage
        let weight: Int
    }

    // MARK: - Detector Input Cap

    /// Upper bound on text fed to the email/phone/URL/address/credential regex
    /// detectors. Generous (detectCode caps at 5k), a paste's categorization
    /// signal lives at its start, and matches beyond the cap are deliberately
    /// not detected so megabyte pastes can't stall the main actor at ingest.
    private static let detectorInputCap = 20_000

    private static func detectorInput(_ text: String) -> String {
        // No count pre-check: String.count is O(n) over the very megabyte pastes
        // this cap protects against, while prefix alone is O(cap).
        String(text.prefix(detectorInputCap))
    }

    // MARK: - Main Entry Point

    static func classify(item: ClipItemModel) -> ContentClassification {
        var categories = Set<SmartCategory>()
        var tags = Set<ContentTag>()
        var isSensitive = false
        var language: DetectedLanguage?
        var actions: [SuggestedAction] = []

        // Image clips go straight to Images
        if item.clipType == .image {
            categories.insert(.images)
            return ContentClassification(
                matchedCategories: categories,
                contentTags: tags,
                isSensitive: false,
                detectedLanguage: nil,
                suggestedActions: []
            )
        }

        // Link clips go to Links
        if item.clipType == .link {
            categories.insert(.links)
            if let url = item.urlValue {
                actions.append(SuggestedAction(type: .openURL, label: L10n.string("action.open.label", default: "Open"), value: url))
            }
        }

        // Text analysis
        let text = item.textValue ?? item.previewText
        guard !text.isEmpty else {
            return ContentClassification(
                matchedCategories: categories,
                contentTags: tags,
                isSensitive: false,
                detectedLanguage: nil,
                suggestedActions: actions
            )
        }

        // Cap detector input like detectCode already does (5k there): classify runs
        // synchronously on the main actor at ingest, and uncapped regex passes over
        // megabyte pastes stall the app. Tradeoff: matches beyond the cap are not
        // detected, acceptable because the categorization signal of a paste lives
        // at its start, and detection exists primarily for smart-folder routing.
        let detectionText = detectorInput(text)
        let fullRange = NSRange(detectionText.startIndex..., in: detectionText)

        // Credential detection (run first — sensitive flag affects other decisions)
        if detectCredentials(text: detectionText, range: fullRange) {
            isSensitive = true
            tags.insert(.credential)
            categories.insert(.sensitive)
        }

        // Code detection
        let codeResult = detectCode(text: text)
        if codeResult.isCode {
            tags.insert(.code)
            language = codeResult.language
            categories.insert(.code)
            actions.append(SuggestedAction(type: .language, label: codeResult.language.displayName, value: codeResult.language.rawValue))
        }

        // Email detection
        let emails = detectEmails(text: detectionText, range: fullRange)
        if !emails.isEmpty {
            tags.insert(.email)
            categories.insert(.contacts)
            actions.append(SuggestedAction(type: .email, label: L10n.string("action.email.label", default: "Email"), value: emails[0]))
        }

        // Phone detection
        let phones = detectPhones(text: detectionText, range: fullRange)
        if !phones.isEmpty {
            tags.insert(.phoneNumber)
            categories.insert(.contacts)
            actions.append(SuggestedAction(type: .call, label: L10n.string("action.call.label", default: "Call"), value: phones[0]))
        }

        // Color detection (only for short text — avoids false positives in code)
        if text.count < 200, detectColor(text: detectionText, range: fullRange) {
            tags.insert(.colorValue)
            categories.insert(.colors)
            // Extract the first color value for the swatch
            if let colorValue = extractFirstColor(text: detectionText, range: fullRange) {
                actions.append(SuggestedAction(type: .colorSwatch, label: colorValue, value: colorValue))
            }
        }

        // URL detection in plain text (not already a link clip)
        if item.clipType == .text {
            let urls = detectURLs(text: detectionText, range: fullRange)
            if !urls.isEmpty {
                categories.insert(.links)
                actions.append(SuggestedAction(type: .openURL, label: L10n.string("action.open.label", default: "Open"), value: urls[0]))
            }
        }

        // Address detection (the Maps action still carries the full text)
        if detectAddress(text: detectionText, range: fullRange) {
            tags.insert(.address)
            categories.insert(.addresses)
            actions.append(SuggestedAction(type: .openMaps, label: L10n.string("action.maps.label", default: "Maps"), value: text))
        }

        return ContentClassification(
            matchedCategories: categories,
            contentTags: tags,
            isSensitive: isSensitive,
            detectedLanguage: language,
            suggestedActions: Array(actions.prefix(3))
        )
    }

    // MARK: - Suggested Actions (from stored tags, no re-classification)

    /// Derives display actions from already-persisted tags on a clip.
    /// Used by views to avoid re-running the classifier.
    static func suggestedActions(for item: ClipItemModel) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []

        if let lang = item.detectedLanguage {
            actions.append(SuggestedAction(type: .language, label: lang.displayName, value: lang.rawValue))
        }

        let tags = item.contentTags

        // Same cap as classify(): this runs from view code, so uncapped regex
        // passes over a huge paste would stall rendering. A clip tagged by the
        // old UNCAPPED classifier can have its only match beyond the cap, so an
        // action is added only when extraction actually found a value, an
        // empty mailto:/tel: button is worse than no button.
        if tags.contains(.email) {
            let text = detectorInput(item.textValue ?? item.previewText)
            let range = NSRange(text.startIndex..., in: text)
            if let email = detectEmails(text: text, range: range).first {
                actions.append(SuggestedAction(type: .email, label: L10n.string("action.email.label", default: "Email"), value: email))
            }
        }

        if tags.contains(.phoneNumber) {
            let text = detectorInput(item.textValue ?? item.previewText)
            let range = NSRange(text.startIndex..., in: text)
            if let phone = detectPhones(text: text, range: range).first {
                actions.append(SuggestedAction(type: .call, label: L10n.string("action.call.label", default: "Call"), value: phone))
            }
        }

        if tags.contains(.colorValue) {
            let text = detectorInput(item.textValue ?? item.previewText)
            let range = NSRange(text.startIndex..., in: text)
            if let colorVal = extractFirstColor(text: text, range: range) {
                actions.append(SuggestedAction(type: .colorSwatch, label: colorVal, value: colorVal))
            }
        }

        // URL action from link clips or detected URLs
        if item.clipType == .link, let url = item.urlValue {
            actions.append(SuggestedAction(type: .openURL, label: L10n.string("action.open.label", default: "Open"), value: url))
        }

        if tags.contains(.address) {
            actions.append(SuggestedAction(type: .openMaps, label: L10n.string("action.maps.label", default: "Maps"), value: item.textValue ?? item.previewText))
        }

        return Array(actions.prefix(3))
    }

    // MARK: - Code Detection

    private static let universalCodeRegexes: [WeightedRegex] = {
        let patterns: [(String, Int)] = [
            ("\\{", 2), ("\\}", 2), ("\\(\\)", 1), (";$", 2),
            ("\\breturn\\b", 2), ("\\bif\\s*\\(", 2), ("\\belse\\b", 1),
            ("\\bfor\\s*\\(", 2), ("\\bwhile\\s*\\(", 2),
            ("=>", 2), ("->", 2), ("\\bimport\\b", 2),
            ("===", 2), ("!==", 2), ("\\|\\|", 1), ("&&", 1),
        ]
        return patterns.compactMap { pattern, weight in
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: .anchorsMatchLines
            ) else { return nil }
            return WeightedRegex(regex: regex, weight: weight)
        }
    }()

    private static let languageCodeRegexes: [WeightedLanguageRegex] = {
        let patterns: [(String, DetectedLanguage, Int)] = [
            // Swift
            ("\\bfunc\\s+\\w+\\s*\\(", .swift, 4),
            ("\\blet\\s+\\w+\\s*(?::|=)", .swift, 3),
            ("\\bvar\\s+\\w+\\s*(?::|=)", .swift, 3),
            ("\\bguard\\s+let", .swift, 4),
            ("\\bstruct\\s+\\w+(?:<[^>]+>)?\\s*(?::|\\{)", .swift, 4),
            ("\\benum\\s+\\w+\\s*(?::|\\{)", .swift, 3),
            ("\\bprotocol\\s+\\w+\\s*(?::|\\{)", .swift, 4),
            ("\\b@State\\b", .swift, 4),
            ("\\b@Published\\b", .swift, 4),
            ("\\bObservableObject\\b", .swift, 3),
            ("\\b@Observable\\b", .swift, 4),
            ("\\bsome\\s+View\\b", .swift, 5),

            // Python
            ("\\bdef\\s+\\w+\\s*\\(", .python, 3),
            ("\\bclass\\s+\\w+.*:", .python, 2),
            ("\\bself\\.", .python, 2),
            ("\\bprint\\s*\\(", .python, 1),
            ("^\\s*#.*$", .python, 1),
            ("\\bimport\\s+\\w+", .python, 1),
            ("\\bfrom\\s+\\w+\\s+import", .python, 3),
            ("\\belif\\b", .python, 4),
            ("\\b__init__\\b", .python, 5),

            // JavaScript/TypeScript
            ("\\bconst\\s+\\w+\\s*=", .javascript, 3),
            ("\\b(?:let|var)\\s+\\w+\\s*=", .javascript, 2),
            ("\\bfunction\\s+\\w+\\s*\\(", .javascript, 3),
            ("\\bconsole\\.log", .javascript, 3),
            ("\\bdocument\\.", .javascript, 3),
            ("\\bwindow\\.", .javascript, 3),
            ("\\basync\\s+function", .javascript, 3),
            ("\\bawait\\s+", .javascript, 2),
            ("\\bexport\\s+(default\\s+)?(?:function|class|const|let|var|\\{)", .javascript, 4),
            ("\\brequire\\s*\\(", .javascript, 3),

            // TypeScript specifics
            (":\\s*(string|number|boolean|any|void|never)\\b", .typescript, 4),
            ("\\binterface\\s+\\w+", .typescript, 4),
            ("\\btype\\s+\\w+\\s*=", .typescript, 4),
            ("<\\w+>", .typescript, 1),

            // HTML
            ("<div[\\s>]", .html, 3),
            ("<span[\\s>]", .html, 3),
            ("<p[\\s>]", .html, 2),
            ("</\\w+>", .html, 2),
            ("<!DOCTYPE", .html, 5),
            ("<html", .html, 5),

            // CSS
            ("\\{[^}]*:[^}]*;[^}]*\\}", .css, 3),
            ("\\b(margin|padding|display|color|background)\\s*:", .css, 3),
            ("@media\\s*\\(", .css, 4),
            ("\\.\\w+\\s*\\{", .css, 2),
            ("#\\w+\\s*\\{", .css, 2),

            // SQL
            ("\\bSELECT\\b.*\\bFROM\\b", .sql, 5),
            ("\\bINSERT\\s+INTO\\b", .sql, 5),
            ("\\bCREATE\\s+TABLE\\b", .sql, 5),
            ("\\bWHERE\\b", .sql, 2),
            ("\\bJOIN\\b", .sql, 2),

            // Go
            ("\\bfunc\\s+\\(\\w+\\s+\\*?\\w+\\)", .go, 5),
            ("\\bpackage\\s+\\w+", .go, 4),
            ("\\bfmt\\.Print", .go, 4),
            (":=", .go, 2),

            // Rust
            ("\\bfn\\s+\\w+", .rust, 3),
            ("\\blet\\s+mut\\b", .rust, 5),
            ("\\bimpl\\s+", .rust, 5),
            ("\\bpub\\s+fn\\b", .rust, 4),
            ("\\bmatch\\s+\\w+", .rust, 2),

            // Ruby
            ("\\bdef\\s+\\w+", .ruby, 2),
            ("\\bend\\b", .ruby, 1),
            ("\\bputs\\b", .ruby, 3),
            ("\\battr_accessor\\b", .ruby, 5),
            ("\\bdo\\s*\\|", .ruby, 3),

            // Java
            ("\\bpublic\\s+(static\\s+)?void\\b", .java, 5),
            ("\\bSystem\\.out\\.print", .java, 5),
            ("\\bprivate\\s+\\w+\\s+\\w+", .java, 2),
            ("\\bnew\\s+\\w+\\(", .java, 1),

            // Shell
            ("^#!/bin/(ba)?sh", .shell, 5),
            ("\\becho\\s+", .shell, 2),
            ("\\$\\{\\w+\\}|\\$[A-Za-z_][A-Za-z0-9_]*", .shell, 1),
            ("\\bfi\\b", .shell, 3),
            ("\\bthen\\b", .shell, 2),
            ("\\besac\\b", .shell, 5),
        ]

        return patterns.compactMap { pattern, language, weight in
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.anchorsMatchLines]
            ) else { return nil }
            return WeightedLanguageRegex(regex: regex, language: language, weight: weight)
        }
    }()

    private static let camelCaseRegex = try! NSRegularExpression(
        pattern: "\\b[a-z]+[A-Z][a-zA-Z]*\\b"
    )
    private static let snakeCaseRegex = try! NSRegularExpression(pattern: "\\b[a-z]+_[a-z]+\\b")
    private static let indentationRegex = try! NSRegularExpression(
        pattern: "^(    |\\t)\\S",
        options: .anchorsMatchLines
    )
    private static let lineCommentRegex = try! NSRegularExpression(
        pattern: "(^|\\s)//\\s*\\S",
        options: .anchorsMatchLines
    )

    /// Weighted scoring for code detection. Returns (isCode, detectedLanguage).
    /// Threshold: score >= 6 to classify as code.
    static func detectCode(text: String) -> (isCode: Bool, language: DetectedLanguage) {
        // Too short to be meaningful code
        guard text.count >= 10 else { return (false, .unknown) }

        // Single-line plain sentences (end with . ? !) — not code
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("\n") {
            let lastChar = trimmed.last
            if lastChar == "." || lastChar == "?" || lastChar == "!" {
                // Only reject if it doesn't also look like code (e.g. no braces or semicolons)
                if !trimmed.contains("{") && !trimmed.contains("}") && !trimmed.contains(";") {
                    return (false, .unknown)
                }
            }
        }

        // Cap analysis length for performance
        let analysisText: String
        if text.count > 10_000 {
            analysisText = String(text.prefix(10_000))
        } else {
            analysisText = text
        }

        // Cap for regex pattern matching
        let regexText: String
        if analysisText.count > 5_000 {
            regexText = String(analysisText.prefix(5_000))
        } else {
            regexText = analysisText
        }

        var score = 0
        var languageScores: [DetectedLanguage: Int] = [:]
        let fullRange = NSRange(regexText.startIndex..., in: regexText)
        var hasStructuralSignal = false

        for entry in universalCodeRegexes where entry.regex.firstMatch(in: regexText, range: fullRange) != nil {
            score += entry.weight
        }

        // Enhanced structural patterns
        // Comment patterns (strong code signal)
        if lineCommentRegex.firstMatch(in: regexText, range: fullRange) != nil
            || regexText.contains("/*")
            || regexText.contains("*/") {
            score += 3
            hasStructuralSignal = true
        }

        // JSON/object structure (starts with { ends with }, or [ and ])
        let structTrimmed = analysisText.trimmingCharacters(in: .whitespacesAndNewlines)
        if (structTrimmed.hasPrefix("{") && structTrimmed.hasSuffix("}"))
            || (structTrimmed.hasPrefix("[") && structTrimmed.hasSuffix("]")) {
            score += 4
            hasStructuralSignal = true
        }

        // XML/HTML tag patterns
        if regexText.contains("</") && regexText.contains("/>") {
            score += 4
            hasStructuralSignal = true
        }

        // CamelCase or snake_case identifiers
        if camelCaseRegex.firstMatch(in: regexText, range: fullRange) != nil {
            score += 2
        }
        if snakeCaseRegex.firstMatch(in: regexText, range: fullRange) != nil {
            score += 2
        }

        // Indentation (lines starting with 4+ spaces or tab)
        if indentationRegex.firstMatch(in: regexText, range: fullRange) != nil {
            score += 2
        }

        // Multi-line text (3+ lines is a code signal)
        let lineCount = analysisText.components(separatedBy: "\n").count
        if lineCount >= 3 {
            score += 1
        }

        // Multiple colons (dict/type annotation signal)
        let colonCount = analysisText.filter({ $0 == ":" }).count
        if colonCount > 1 {
            score += 1
        }

        for entry in languageCodeRegexes where entry.regex.firstMatch(in: regexText, range: fullRange) != nil {
            score += entry.weight
            languageScores[entry.language, default: 0] += entry.weight
        }

        guard score >= 6 else {
            return (false, .unknown)
        }

        let hasLanguageSignal = !languageScores.isEmpty
        guard hasStructuralSignal || hasLanguageSignal || score >= 8 else {
            return (false, .unknown)
        }

        // Pick the language with the highest score
        let detectedLang = languageScores.max(by: { $0.value < $1.value })?.key ?? .unknown
        return (true, detectedLang)
    }

    // MARK: - Credential Detection

    private static let credentialPatterns: [NSRegularExpression] = {
        let patterns = [
            "\\bsk-[A-Za-z0-9]{20,}",                    // OpenAI / Stripe secret keys
            "\\bpk-[A-Za-z0-9]{20,}",                    // Public keys
            "\\bghp_[A-Za-z0-9]{36,}",                   // GitHub personal access tokens
            "\\bgho_[A-Za-z0-9]{36,}",                   // GitHub OAuth tokens
            "\\bghs_[A-Za-z0-9]{36,}",                   // GitHub App tokens
            "\\bAKIA[0-9A-Z]{16}",                       // AWS access key IDs
            "\\bapi[_-]?key\\s*[=:]\\s*['\"]?[A-Za-z0-9_\\-]{16,}", // Generic api_key=...
            "\\btoken\\s*[=:]\\s*['\"]?[A-Za-z0-9_\\-]{20,}",      // Generic token=...
            "\\bpassword\\s*[=:]\\s*['\"]?\\S{8,}",      // Password assignments
            "-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----", // SSH/PGP private keys
            "-----BEGIN CERTIFICATE-----",                // Certificates
            "\\bBearer\\s+[A-Za-z0-9_\\-\\.]{20,}",     // Bearer tokens
            "\\bxox[bpsa]-[A-Za-z0-9\\-]{10,}",         // Slack tokens
            "\\bSG\\.[A-Za-z0-9_\\-]{22}\\.[A-Za-z0-9_\\-]{43}", // SendGrid API keys
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static func detectCredentials(text: String, range: NSRange) -> Bool {
        for regex in credentialPatterns {
            if regex.firstMatch(in: text, range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Color Detection

    private static let hexColorRegex = try! NSRegularExpression(pattern: "#([0-9A-Fa-f]{3,8})\\b")
    private static let rgbColorRegex = try! NSRegularExpression(pattern: "rgba?\\s*\\(\\s*\\d{1,3}\\s*,\\s*\\d{1,3}\\s*,\\s*\\d{1,3}")
    private static let hslColorRegex = try! NSRegularExpression(pattern: "hsla?\\s*\\(\\s*\\d{1,3}\\s*,\\s*\\d{1,3}%?\\s*,\\s*\\d{1,3}%?")

    /// Derived from `cssNamedColorHex` so detection and swatch rendering can
    /// never drift apart: a name only classifies as a color if we can also
    /// render its swatch.
    private static let cssNamedColors: Set<String> = Set(cssNamedColorHex.keys)

    static func detectColor(text: String, range: NSRange) -> Bool {
        if hexColorRegex.firstMatch(in: text, range: range) != nil { return true }
        if rgbColorRegex.firstMatch(in: text, range: range) != nil { return true }
        if hslColorRegex.firstMatch(in: text, range: range) != nil { return true }

        // Check for CSS named colors (only for short single-token text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.count < 30, cssNamedColors.contains(trimmed) { return true }

        return false
    }

    static func extractFirstColor(text: String, range: NSRange) -> String? {
        if let match = hexColorRegex.firstMatch(in: text, range: range) {
            return (text as NSString).substring(with: match.range)
        }
        if let match = rgbColorRegex.firstMatch(in: text, range: range) {
            // Include closing paren if present
            let start = match.range.location
            let searchEnd = min(start + match.range.length + 10, text.count)
            let extended = (text as NSString).substring(with: NSRange(location: start, length: searchEnd - start))
            if let parenIdx = extended.firstIndex(of: ")") {
                return String(extended[extended.startIndex...parenIdx])
            }
            return (text as NSString).substring(with: match.range)
        }
        if let match = hslColorRegex.firstMatch(in: text, range: range) {
            let start = match.range.location
            let searchEnd = min(start + match.range.length + 10, text.count)
            let extended = (text as NSString).substring(with: NSRange(location: start, length: searchEnd - start))
            if let parenIdx = extended.firstIndex(of: ")") {
                return String(extended[extended.startIndex...parenIdx])
            }
            return (text as NSString).substring(with: match.range)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.count < 30, cssNamedColors.contains(trimmed) { return trimmed }
        return nil
    }

    // MARK: - Email Detection

    private static let emailRegex = try! NSRegularExpression(
        pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
    )

    static func detectEmails(text: String, range: NSRange) -> [String] {
        emailRegex.matches(in: text, range: range).map {
            (text as NSString).substring(with: $0.range)
        }
    }

    // MARK: - Phone / URL / Address Detection

    /// One cached detector for phones and links — replaces two hand-rolled
    /// regexes with the system's smarter recognizers.
    private static let dataDetector = try! NSDataDetector(types:
        NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        | NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func detectPhones(text: String, range: NSRange) -> [String] {
        dataDetector.matches(in: text, range: range)
            .filter { $0.resultType == .phoneNumber }
            .map { (text as NSString).substring(with: $0.range) }
    }

    static func detectURLs(text: String, range: NSRange) -> [String] {
        // Keep the old regex's scope: explicit http(s) URLs only. The detector
        // also flags bare domains and emails (mailto), which must not classify
        // plain text as containing links.
        dataDetector.matches(in: text, range: range)
            .filter { $0.resultType == .link }
            .map { (text as NSString).substring(with: $0.range) }
            .filter { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
    }

    // Address detection stays regex-based: NSDataDetector's .address needs
    // city/state context, so a bare street line like "742 Evergreen Terrace"
    // (which must classify as an address — see ContentClassifierTests) is
    // missed by the system recognizer.
    private static let addressStreetSuffixPattern =
        "(Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Lane|Ln|Court|Ct|Way|Place|Pl|Circle|Cir|"
        + "Terrace|Ter|Trail|Trl|Highway|Hwy|Parkway|Pkwy)"

    private static let addressRegex = try! NSRegularExpression(
        pattern: "\\d{1,6}\\s+[A-Za-z0-9.]+\\s+\(addressStreetSuffixPattern)\\b",
        options: .caseInsensitive
    )

    static func detectAddress(text: String, range: NSRange) -> Bool {
        addressRegex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Color Parsing (for swatch rendering)

    /// Parse a hex color string like "#FF5733" or "#F53" into RGB components (0-1).
    static func parseHexColor(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }

        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }

        switch cleaned.count {
        case 3: // #RGB
            let r = Double((rgb >> 8) & 0xF) / 15.0
            let g = Double((rgb >> 4) & 0xF) / 15.0
            let b = Double(rgb & 0xF) / 15.0
            return (r, g, b)
        case 6: // #RRGGBB
            let r = Double((rgb >> 16) & 0xFF) / 255.0
            let g = Double((rgb >> 8) & 0xFF) / 255.0
            let b = Double(rgb & 0xFF) / 255.0
            return (r, g, b)
        case 8: // #RRGGBBAA
            let r = Double((rgb >> 24) & 0xFF) / 255.0
            let g = Double((rgb >> 16) & 0xFF) / 255.0
            let b = Double((rgb >> 8) & 0xFF) / 255.0
            return (r, g, b)
        default:
            return nil
        }
    }

    // MARK: - Universal Color Parsing (hex, rgb, hsl)

    private static let rgbParseRegex = try! NSRegularExpression(
        pattern: "rgba?\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)"
    )
    private static let hslParseRegex = try! NSRegularExpression(
        pattern: "hsla?\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)%?\\s*,\\s*(\\d+)%?"
    )

    /// Parse any color format (hex, rgb, hsl, CSS named) into RGB components (0-1).
    /// Used by the color card to render the actual color.
    static func parseAnyColor(_ text: String) -> (r: Double, g: Double, b: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try hex first
        if let hex = parseHexColor(trimmed) { return hex }

        let range = NSRange(trimmed.startIndex..., in: trimmed)

        // Try rgb/rgba
        if let match = rgbParseRegex.firstMatch(in: trimmed, range: range),
           match.numberOfRanges >= 4,
           let rRange = Range(match.range(at: 1), in: trimmed),
           let gRange = Range(match.range(at: 2), in: trimmed),
           let bRange = Range(match.range(at: 3), in: trimmed),
           let r = Int(trimmed[rRange]),
           let g = Int(trimmed[gRange]),
           let b = Int(trimmed[bRange]) {
            return (Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)
        }

        // Try hsl/hsla
        if let match = hslParseRegex.firstMatch(in: trimmed, range: range),
           match.numberOfRanges >= 4,
           let hRange = Range(match.range(at: 1), in: trimmed),
           let sRange = Range(match.range(at: 2), in: trimmed),
           let lRange = Range(match.range(at: 3), in: trimmed),
           let h = Int(trimmed[hRange]),
           let s = Int(trimmed[sRange]),
           let l = Int(trimmed[lRange]) {
            let rgb = hslToRGB(h: h, s: s, l: l)
            return rgb
        }

        // Try CSS named colors
        let lower = trimmed.lowercased()
        if lower.count < 30, let rgb = cssNamedColorRGB(lower) {
            return rgb
        }

        return nil
    }

    /// Convert HSL to RGB (0-1 range).
    private static func hslToRGB(h: Int, s: Int, l: Int) -> (r: Double, g: Double, b: Double) {
        let hNorm = Double(h) / 360.0
        let sNorm = Double(s) / 100.0
        let lNorm = Double(l) / 100.0

        if sNorm == 0 {
            return (lNorm, lNorm, lNorm)
        }

        let q = lNorm < 0.5 ? lNorm * (1 + sNorm) : lNorm + sNorm - lNorm * sNorm
        let p = 2 * lNorm - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var tNorm = t
            if tNorm < 0 { tNorm += 1 }
            if tNorm > 1 { tNorm -= 1 }
            if tNorm < 1.0 / 6.0 { return p + (q - p) * 6 * tNorm }
            if tNorm < 1.0 / 2.0 { return q }
            if tNorm < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - tNorm) * 6 }
            return p
        }

        return (
            r: hueToRGB(p, q, hNorm + 1.0 / 3.0),
            g: hueToRGB(p, q, hNorm),
            b: hueToRGB(p, q, hNorm - 1.0 / 3.0)
        )
    }

    /// Lookup a CSS named color and return RGB (0-1).
    /// Uses a common subset — returns nil for unrecognized names.
    private static func cssNamedColorRGB(_ name: String) -> (r: Double, g: Double, b: Double)? {
        guard let hex = cssNamedColorHex[name] else { return nil }
        return parseHexColor(hex)
    }

    private static let cssNamedColorHex: [String: String] = [
        "red": "#FF0000", "green": "#008000", "blue": "#0000FF", "white": "#FFFFFF",
        "black": "#000000", "yellow": "#FFFF00", "cyan": "#00FFFF", "magenta": "#FF00FF",
        "orange": "#FFA500", "purple": "#800080", "pink": "#FFC0CB", "brown": "#A52A2A",
        "gray": "#808080", "grey": "#808080", "silver": "#C0C0C0", "gold": "#FFD700",
        "navy": "#000080", "teal": "#008080", "maroon": "#800000", "olive": "#808000",
        "lime": "#00FF00", "aqua": "#00FFFF", "fuchsia": "#FF00FF", "coral": "#FF7F50",
        "salmon": "#FA8072", "tomato": "#FF6347", "crimson": "#DC143C", "indigo": "#4B0082",
        "violet": "#EE82EE", "plum": "#DDA0DD", "orchid": "#DA70D6", "turquoise": "#40E0D0",
        "skyblue": "#87CEEB", "steelblue": "#4682B4", "royalblue": "#4169E1",
        "dodgerblue": "#1E90FF", "cornflowerblue": "#6495ED", "chocolate": "#D2691E",
        "sienna": "#A0522D", "peru": "#CD853F", "tan": "#D2B48C", "wheat": "#F5DEB3",
        "khaki": "#F0E68C", "ivory": "#FFFFF0", "beige": "#F5F5DC", "linen": "#FAF0E6",
        "snow": "#FFFAFA", "honeydew": "#F0FFF0", "mintcream": "#F5FFFA",
        "azure": "#F0FFFF", "lavender": "#E6E6FA", "mistyrose": "#FFE4E1",
        "firebrick": "#B22222", "darkred": "#8B0000", "darkgreen": "#006400",
        "darkblue": "#00008B", "darkcyan": "#008B8B", "darkmagenta": "#8B008B",
        "darkorange": "#FF8C00", "darkviolet": "#9400D3", "deeppink": "#FF1493",
        "deepskyblue": "#00BFFF", "forestgreen": "#228B22", "limegreen": "#32CD32",
        "springgreen": "#00FF7F", "mediumblue": "#0000CD", "midnightblue": "#191970",
        "rebeccapurple": "#663399", "hotpink": "#FF69B4", "lightblue": "#ADD8E6",
        "lightcoral": "#F08080", "lightcyan": "#E0FFFF", "lightgreen": "#90EE90",
        "lightpink": "#FFB6C1", "lightyellow": "#FFFFE0", "yellowgreen": "#9ACD32",
    ]
}
