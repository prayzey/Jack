import Foundation

/// Text transformation operations available from context menus and preview overlay.
enum TextTransform: String, CaseIterable {
    case uppercase
    case lowercase
    case titleCase
    case trimWhitespace
    case removeEmptyLines
    case sortLines
    case stripHTML
    case urlEncode
    case urlDecode
    case reverseText

    var label: String {
        switch self {
        case .uppercase: return L10n.string("textTransform.uppercase.label", default: "UPPERCASE")
        case .lowercase: return L10n.string("textTransform.lowercase.label", default: "lowercase")
        case .titleCase: return L10n.string("textTransform.titleCase.label", default: "Title Case")
        case .trimWhitespace: return L10n.string("textTransform.trimWhitespace.label", default: "Trim Whitespace")
        case .removeEmptyLines: return L10n.string("textTransform.removeEmptyLines.label", default: "Remove Empty Lines")
        case .sortLines: return L10n.string("textTransform.sortLines.label", default: "Sort Lines")
        case .stripHTML: return L10n.string("textTransform.stripHTML.label", default: "Strip HTML")
        case .urlEncode: return L10n.string("textTransform.urlEncode.label", default: "URL Encode")
        case .urlDecode: return L10n.string("textTransform.urlDecode.label", default: "URL Decode")
        case .reverseText: return L10n.string("textTransform.reverseText.label", default: "Reverse Text")
        }
    }

    var icon: String {
        switch self {
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .titleCase: return "textformat"
        case .trimWhitespace: return "scissors"
        case .removeEmptyLines: return "line.3.horizontal.decrease"
        case .sortLines: return "arrow.up.arrow.down.circle"
        case .stripHTML: return "chevron.left.forwardslash.chevron.right"
        case .urlEncode: return "percent"
        case .urlDecode: return "arrow.uturn.backward"
        case .reverseText: return "arrow.left.arrow.right"
        }
    }

    /// Which section divider group this transform belongs to (for menu separators).
    var group: Int {
        switch self {
        case .uppercase, .lowercase, .titleCase: return 0
        case .trimWhitespace, .removeEmptyLines, .sortLines: return 1
        case .stripHTML, .urlEncode, .urlDecode: return 2
        case .reverseText: return 3
        }
    }

    /// Pre-grouped transforms for menus that render section dividers.
    static var groupedForMenu: [(group: Int, transforms: [TextTransform])] {
        Dictionary(grouping: allCases, by: \.group)
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, transforms: $0.value) }
    }

    func apply(to text: String) -> String {
        switch self {
        case .uppercase:
            return text.uppercased()

        case .lowercase:
            return text.lowercased()

        case .titleCase:
            return text.capitalized

        case .trimWhitespace:
            // Strip leading/trailing whitespace per line and collapse internal whitespace runs
            let lines = text.components(separatedBy: .newlines)
            let cleaned = lines.map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            return cleaned.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

        case .removeEmptyLines:
            return text.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")

        case .sortLines:
            let lines = text.components(separatedBy: .newlines)
            return lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: "\n")

        case .stripHTML:
            return Self.stripHTMLTags(from: text)

        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text

        case .urlDecode:
            return text.removingPercentEncoding ?? text

        case .reverseText:
            return String(text.reversed())
        }
    }

    // MARK: - HTML Stripping

    private static func stripHTMLTags(from html: String) -> String {
        // Remove HTML tags
        var result = html
        // Remove script and style blocks entirely
        result = result.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )
        // Remove remaining HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Decode common HTML entities
        result = decodeHTMLEntities(result)
        // Collapse excessive whitespace
        result = result.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Named entities the shared `decodingHTMLEntities()` doesn't cover, mapped
    /// to plain-ASCII replacements (Strip HTML deliberately produces plain text).
    private static func decodeHTMLEntities(_ text: String) -> String {
        let extraEntities: [(String, String)] = [
            ("&ndash;", "-"),
            ("&mdash;", "--"),
            ("&hellip;", "..."),
            ("&copy;", "(c)"),
            ("&reg;", "(R)"),
            ("&trade;", "(TM)"),
        ]
        var result = text
        for (entity, replacement) in extraEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.decodingHTMLEntities()
    }
}
