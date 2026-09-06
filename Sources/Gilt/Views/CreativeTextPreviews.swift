import SwiftUI

// MARK: - Known Code / Document Extensions

/// Canonical set of file extensions recognized as code or document files.
/// Shared by:
///   - `CreativeTextPattern.detectFilePath` — triggers creative file-type card previews
///   - `ClipActionService.normalizeWebURL` — prevents "wow.md" from being misclassified as a URL
///     (many code extensions like .md, .rs, .py overlap with real country-code TLDs)
///   - Any future feature that needs to distinguish filenames from domain names
///
/// Keep sorted by category for readability. Add new extensions here, not in call sites.
let knownCodeExtensions: Set<String> = [
    // JavaScript / TypeScript
    "js", "jsx", "ts", "tsx", "mjs", "cjs",
    // Systems
    "swift", "rs", "go", "c", "cpp", "h", "hpp", "cs", "m", "mm",
    // Scripting
    "py", "rb", "r", "jl", "lua", "dart", "ex", "exs", "erl", "hs", "ml", "scala",
    // JVM
    "java", "kt", "kts",
    // Web
    "html", "htm", "css", "scss", "sass", "less", "vue", "svelte", "astro",
    // Data / Config
    "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf",
    "env", "gitignore", "editorconfig",
    // Docs
    "md", "mdx", "txt", "rtf", "tex", "rst",
    // Shell
    "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
    // Query / Schema
    "sql", "graphql", "gql", "prisma", "proto",
    // Build / Infra
    "dockerfile", "makefile", "tf", "hcl", "nix",
    // Other
    "zig", "wasm", "lock", "log",
]

// MARK: - Pattern Detection

/// Detects special text patterns that get creative visual treatment instead of plain text rendering.
/// Returns nil for ordinary text — the caller falls back to standard textContent.
///
/// Why this exists: Short developer-oriented strings (localhost URLs, file paths) are visually
/// uninteresting as plain text but carry strong semantic identity. A clipboard manager used by
/// developers benefits from making these instantly recognizable at a glance.
///
/// Why detection is conservative: Only short, single-purpose strings (<=300 chars, <=3 lines)
/// are matched. Multi-line code blocks, prose, and long paths fall through to standard text
/// rendering so we never hide useful content behind a decorative preview.
enum CreativeTextPattern {
    case localhost(port: String?, path: String?)
    case filePath(filename: String, ext: String)

    /// Attempts to match the text against known creative patterns.
    /// Only matches short, single-purpose strings — multi-line code blocks or long prose are excluded.
    ///
    /// Called from both `textContent` (ClipType.text) and `linkContent` (ClipType.link) in
    /// ClipCardView. This dual-path is necessary because the same content (e.g., "localhost:3000")
    /// can arrive as either type depending on how the user copied it:
    ///   - Copying from a browser address bar → macOS puts NSPasteboardTypeURL → ClipType.link
    ///   - Copying from a text editor or terminal → plain string → ClipType.text
    /// See ClipboardMonitor.fromPasteboard() for the classification order.
    static func detect(in text: String) -> CreativeTextPattern? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip multi-line text or very long strings — those are real content, not references
        guard !trimmed.isEmpty, trimmed.count <= 300, trimmed.components(separatedBy: .newlines).count <= 3 else {
            return nil
        }

        if let localhost = detectLocalhost(trimmed) { return localhost }
        if let file = detectFilePath(trimmed) { return file }
        return nil
    }

    // MARK: - Localhost

    // Compiled once (see ContentClassifier for the same static-let convention):
    // detect() runs for every visible text/link card on every render pass, and
    // each search keystroke re-renders all visible cards, per-call
    // NSRegularExpression compilation here was measurable render churn.
    // Match: localhost, localhost:PORT, http://localhost:PORT/path, 127.0.0.1:PORT
    private static let localhostRegex = try! NSRegularExpression(
        pattern: #"^(?:https?://)?(?:localhost|127\.0\.0\.1)(?::(\d{1,5}))?(/\S*)?$"#,
        options: .caseInsensitive
    )

    private static func detectLocalhost(_ text: String) -> CreativeTextPattern? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = localhostRegex.firstMatch(in: text, range: range) else { return nil }

        var port: String?
        if match.range(at: 1).location != NSNotFound,
           let portRange = Range(match.range(at: 1), in: text) {
            port = String(text[portRange])
        }

        var path: String?
        if match.range(at: 2).location != NSNotFound,
           let pathRange = Range(match.range(at: 2), in: text) {
            let p = String(text[pathRange])
            if p != "/" { path = p }
        }

        return .localhost(port: port, path: path)
    }

    // MARK: - File Path

    private static func detectFilePath(_ text: String) -> CreativeTextPattern? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip URL scheme if present — a link-type clip for "https://wow.md" should still
        // match as a file path since the URL normalizer may have prepended a scheme to what
        // was originally just "wow.md" in the user's clipboard.
        // hasPrefix instead of the old `range(of:options:.regularExpression)`, that
        // compiled a fresh regex on every call, and this runs per visible card per render.
        let cleaned: String
        if trimmed.hasPrefix("https://") {
            cleaned = String(trimmed.dropFirst("https://".count))
        } else if trimmed.hasPrefix("http://") {
            cleaned = String(trimmed.dropFirst("http://".count))
        } else {
            cleaned = trimmed
        }

        // Must look like a filename or path — contains a dot and ends with a known extension
        guard let dotIndex = cleaned.lastIndex(of: ".") else { return nil }

        let ext = String(cleaned[cleaned.index(after: dotIndex)...]).lowercased()
        // Reject if anything after the dot contains slashes or query params — that's a real URL path
        if ext.contains("/") || ext.contains("?") || ext.contains("#") { return nil }
        guard knownCodeExtensions.contains(ext) else { return nil }

        // Extract just the filename from a path
        let filename: String
        if let lastSlash = trimmed.lastIndex(of: "/") {
            filename = String(trimmed[trimmed.index(after: lastSlash)...])
        } else if let lastBackslash = trimmed.lastIndex(of: "\\") {
            filename = String(trimmed[trimmed.index(after: lastBackslash)...])
        } else {
            filename = trimmed
        }

        // Sanity: filename shouldn't contain spaces (paths can, but the filename part usually doesn't for code)
        // Allow it though — some files do have spaces
        guard !filename.isEmpty else { return nil }

        return .filePath(filename: filename, ext: ".\(ext)")
    }
}

// MARK: - File Extension Colors

/// Language-specific color identities for file extension previews.
struct FileExtensionTheme {
    let color: Color
    let glowOpacity: Double

    static func theme(for ext: String) -> FileExtensionTheme {
        switch ext.lowercased() {
        // JavaScript family
        case ".js", ".jsx":
            return FileExtensionTheme(color: Color(red: 0.97, green: 0.87, blue: 0.12), glowOpacity: 0.12)
        case ".ts", ".tsx":
            return FileExtensionTheme(color: Color(red: 0.19, green: 0.47, blue: 0.78), glowOpacity: 0.12)

        // Systems
        case ".swift":
            return FileExtensionTheme(color: Color(red: 0.94, green: 0.32, blue: 0.22), glowOpacity: 0.12)
        case ".rs":
            return FileExtensionTheme(color: Color(red: 0.87, green: 0.65, blue: 0.52), glowOpacity: 0.12)
        case ".go":
            return FileExtensionTheme(color: Color(red: 0.0, green: 0.68, blue: 0.85), glowOpacity: 0.12)
        case ".py":
            return FileExtensionTheme(color: Color(red: 0.22, green: 0.45, blue: 0.67), glowOpacity: 0.12)
        case ".rb":
            return FileExtensionTheme(color: Color(red: 0.80, green: 0.20, blue: 0.18), glowOpacity: 0.12)
        case ".java", ".kt", ".kts":
            return FileExtensionTheme(color: Color(red: 0.91, green: 0.30, blue: 0.24), glowOpacity: 0.10)
        case ".c", ".cpp", ".h", ".hpp":
            return FileExtensionTheme(color: Color(red: 0.40, green: 0.55, blue: 0.82), glowOpacity: 0.10)
        case ".cs":
            return FileExtensionTheme(color: Color(red: 0.41, green: 0.18, blue: 0.71), glowOpacity: 0.10)

        // Web
        case ".html", ".htm":
            return FileExtensionTheme(color: Color(red: 0.89, green: 0.30, blue: 0.15), glowOpacity: 0.12)
        case ".css", ".scss", ".sass", ".less":
            return FileExtensionTheme(color: Color(red: 0.15, green: 0.30, blue: 0.89), glowOpacity: 0.12)
        case ".vue":
            return FileExtensionTheme(color: Color(red: 0.26, green: 0.72, blue: 0.48), glowOpacity: 0.12)
        case ".svelte":
            return FileExtensionTheme(color: Color(red: 1.0, green: 0.24, blue: 0.0), glowOpacity: 0.12)

        // Data / Config
        case ".json":
            return FileExtensionTheme(color: Color(red: 0.66, green: 0.66, blue: 0.66), glowOpacity: 0.08)
        case ".yaml", ".yml":
            return FileExtensionTheme(color: Color(red: 0.80, green: 0.09, blue: 0.12), glowOpacity: 0.12)
        case ".xml":
            return FileExtensionTheme(color: Color(red: 0.60, green: 0.60, blue: 0.60), glowOpacity: 0.08)
        case ".sql":
            return FileExtensionTheme(color: Color(red: 0.89, green: 0.55, blue: 0.08), glowOpacity: 0.12)
        case ".graphql", ".gql":
            return FileExtensionTheme(color: Color(red: 0.88, green: 0.0, blue: 0.60), glowOpacity: 0.10)
        case ".prisma":
            return FileExtensionTheme(color: Color(red: 0.11, green: 0.15, blue: 0.38), glowOpacity: 0.10)

        // Docs
        case ".md", ".mdx":
            return FileExtensionTheme(color: .white, glowOpacity: 0.06)
        case ".txt", ".rtf":
            return FileExtensionTheme(color: Color(red: 0.7, green: 0.7, blue: 0.7), glowOpacity: 0.05)

        // Shell
        case ".sh", ".bash", ".zsh", ".fish":
            return FileExtensionTheme(color: Color(red: 0.31, green: 0.67, blue: 0.15), glowOpacity: 0.12)
        case ".ps1":
            return FileExtensionTheme(color: Color(red: 0.01, green: 0.44, blue: 0.73), glowOpacity: 0.10)

        // Misc
        case ".dart":
            return FileExtensionTheme(color: Color(red: 0.01, green: 0.67, blue: 0.85), glowOpacity: 0.10)
        case ".lua":
            return FileExtensionTheme(color: Color(red: 0.0, green: 0.0, blue: 0.50), glowOpacity: 0.08)
        case ".r":
            return FileExtensionTheme(color: Color(red: 0.15, green: 0.43, blue: 0.70), glowOpacity: 0.10)
        case ".zig":
            return FileExtensionTheme(color: Color(red: 0.97, green: 0.65, blue: 0.16), glowOpacity: 0.12)
        case ".ex", ".exs":
            return FileExtensionTheme(color: Color(red: 0.29, green: 0.18, blue: 0.43), glowOpacity: 0.10)
        case ".tf", ".hcl":
            return FileExtensionTheme(color: Color(red: 0.39, green: 0.30, blue: 0.82), glowOpacity: 0.10)

        // Env / Config
        case ".env", ".ini", ".cfg", ".conf", ".toml", ".editorconfig":
            return FileExtensionTheme(color: Color(red: 0.55, green: 0.55, blue: 0.55), glowOpacity: 0.06)

        default:
            return FileExtensionTheme(color: Color(red: 0.5, green: 0.5, blue: 0.5), glowOpacity: 0.06)
        }
    }
}

// MARK: - Localhost Preview

/// Terminal-glow style preview for localhost URLs. Shows the port number large with a green dev-server aesthetic.
struct LocalhostPreview: View {
    let port: String?
    let path: String?
    let fullText: String

    var body: some View {
        ZStack {
            // Radial glow behind the port number
            RadialGradient(
                colors: [Color(red: 0, green: 1, blue: 0.53).opacity(0.10), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 80
            )

            VStack(spacing: 2) {
                if let port = port {
                    Text(port)
                        .font(.system(size: portFontSize(port), weight: .heavy, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0, green: 1, blue: 0.53),
                                    Color(red: 0, green: 0.80, blue: 0.42),
                                    Color(red: 0, green: 0.60, blue: 0.31)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(red: 0, green: 1, blue: 0.53).opacity(0.4), radius: 16)

                    HStack(spacing: 0) {
                        Text(L10n.string("ui.localhost", default: "localhost"))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0, green: 1, blue: 0.53).opacity(0.45))
                        // Blinking cursor
                        Rectangle()
                            .fill(Color(red: 0, green: 1, blue: 0.53).opacity(0.6))
                            .frame(width: 1.5, height: 10)
                            .padding(.leading, 2)
                            .blinkEffect()
                    }
                } else {
                    // No port — show "localhost" as the hero
                    Text(L10n.string("ui.local", default: "local"))
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0, green: 1, blue: 0.53),
                                    Color(red: 0, green: 0.80, blue: 0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(red: 0, green: 1, blue: 0.53).opacity(0.3), radius: 12)

                    Text(L10n.string("ui.host", default: "host"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0, green: 1, blue: 0.53).opacity(0.45))
                }

                if let path = path {
                    Text(path)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func portFontSize(_ port: String) -> CGFloat {
        switch port.count {
        case 1: return 56
        case 2: return 52
        case 3: return 48
        case 4: return 44
        case 5: return 38
        default: return 34
        }
    }
}

// MARK: - File Path Preview

/// Bold extension badge preview for file paths. Shows the extension large with language-specific color.
struct FilePathPreview: View {
    let filename: String
    let ext: String

    var body: some View {
        let theme = FileExtensionTheme.theme(for: ext)

        ZStack(alignment: .bottomTrailing) {
            // Radial glow from bottom-right
            RadialGradient(
                colors: [theme.color.opacity(theme.glowOpacity), .clear],
                center: UnitPoint(x: 0.8, y: 0.7),
                startRadius: 0,
                endRadius: 100
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(ext)
                    .font(.system(size: extFontSize(ext), weight: .heavy, design: .monospaced))
                    .foregroundStyle(theme.color)
                    .shadow(color: theme.color.opacity(0.3), radius: 12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(filename)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func extFontSize(_ ext: String) -> CGFloat {
        switch ext.count {
        case ...3: return 40
        case 4: return 36
        case 5: return 32
        case 6: return 28
        default: return 24
        }
    }
}

// MARK: - Blink Effect

private struct BlinkModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

extension View {
    func blinkEffect() -> some View {
        modifier(BlinkModifier())
    }
}
