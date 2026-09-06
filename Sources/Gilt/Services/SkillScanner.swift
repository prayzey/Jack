import Foundation
import OSLog

// MARK: - AI Provider Definition

/// Represents a known AI coding tool that stores skills/rules on disk.
struct AIProvider: Identifiable, Codable, Hashable {
    let id: String          // e.g. "claude", "codex", "cursor"
    let displayName: String // e.g. "Claude Code", "Codex CLI"
    let color: String       // FolderColorToken rawValue for folder pill
    let iconSymbol: String  // SF Symbol name

    /// All known providers and where their skills live.
    static let all: [AIProvider] = [
        AIProvider(
            id: "claude",
            displayName: "Claude Skills",
            color: FolderColorToken.amber.rawValue,
            iconSymbol: "brain.head.profile"
        ),
        AIProvider(
            id: "codex",
            displayName: "Codex Skills",
            color: FolderColorToken.emerald.rawValue,
            iconSymbol: "terminal"
        ),
        AIProvider(
            id: "cursor",
            displayName: "Cursor Rules",
            color: FolderColorToken.sapphire.rawValue,
            iconSymbol: "cursorarrow.rays"
        ),
        AIProvider(
            id: "windsurf",
            displayName: "Windsurf Rules",
            color: FolderColorToken.teal.rawValue,
            iconSymbol: "wind"
        ),
        AIProvider(
            id: "agents",
            displayName: "Shared Skills",
            color: FolderColorToken.mauve.rawValue,
            iconSymbol: "person.2"
        ),
        AIProvider(
            id: "continue",
            displayName: "Continue Prompts",
            color: FolderColorToken.coral.rawValue,
            iconSymbol: "play.circle"
        ),
        AIProvider(
            id: "cline",
            displayName: "Cline Rules",
            color: FolderColorToken.gold.rawValue,
            iconSymbol: "bolt"
        ),
    ]

    static func provider(for id: String) -> AIProvider? {
        all.first { $0.id == id }
    }
}

// MARK: - Discovered Skill File

/// A single skill/rule file found on disk.
struct DiscoveredSkill {
    let providerID: String
    let fileName: String
    let filePath: URL
    let content: String
    let name: String        // Parsed from frontmatter or filename
    let description: String // Parsed from frontmatter or first line
}

// MARK: - Scan Result

/// Result of scanning a single provider's directories.
struct ProviderScanResult: Identifiable {
    let provider: AIProvider
    let skills: [DiscoveredSkill]
    let directoryPath: String
    var id: String { provider.id }
    var isEmpty: Bool { skills.isEmpty }
}

// MARK: - Skill Scanner

/// Scans known AI coding tool directories for skills, commands, and rules.
enum SkillScanner {
    private static let logger = Logger(subsystem: AppBrand.logSubsystem, category: "SkillScanner")

    /// Scan all known providers and return results for those that exist on disk.
    static func scanAll() -> [ProviderScanResult] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [ProviderScanResult] = []

        // Claude Code: ~/.claude/skills/ and ~/.claude/commands/
        let claudeSkills = scanDirectory(home.appending(path: ".claude/skills"), providerID: "claude")
        let claudeCommands = scanDirectory(home.appending(path: ".claude/commands"), providerID: "claude")
        let allClaude = claudeSkills + claudeCommands
        if !allClaude.isEmpty, let provider = AIProvider.provider(for: "claude") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: allClaude,
                directoryPath: home.appending(path: ".claude").path
            ))
        }

        // Codex CLI: ~/.codex/skills/
        let codexSkills = scanDirectory(home.appending(path: ".codex/skills"), providerID: "codex")
        if !codexSkills.isEmpty, let provider = AIProvider.provider(for: "codex") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: codexSkills,
                directoryPath: home.appending(path: ".codex/skills").path
            ))
        }

        // Cursor: ~/.cursor/rules/ and ~/.cursor/skills-cursor/
        let cursorRules = scanDirectory(home.appending(path: ".cursor/rules"), providerID: "cursor")
        let cursorSkills = scanDirectory(home.appending(path: ".cursor/skills-cursor"), providerID: "cursor")
        let allCursor = cursorRules + cursorSkills
        if !allCursor.isEmpty, let provider = AIProvider.provider(for: "cursor") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: allCursor,
                directoryPath: home.appending(path: ".cursor").path
            ))
        }

        // Windsurf: ~/.codeium/windsurf/memories/
        let windsurfMemories = scanDirectory(home.appending(path: ".codeium/windsurf/memories"), providerID: "windsurf")
        if !windsurfMemories.isEmpty, let provider = AIProvider.provider(for: "windsurf") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: windsurfMemories,
                directoryPath: home.appending(path: ".codeium/windsurf/memories").path
            ))
        }

        // Shared agent skills: ~/.agents/skills/
        let sharedSkills = scanDirectory(home.appending(path: ".agents/skills"), providerID: "agents")
        if !sharedSkills.isEmpty, let provider = AIProvider.provider(for: "agents") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: sharedSkills,
                directoryPath: home.appending(path: ".agents/skills").path
            ))
        }

        // Continue.dev: ~/.continue/prompts/
        let continuePrompts = scanDirectory(home.appending(path: ".continue/prompts"), providerID: "continue")
        if !continuePrompts.isEmpty, let provider = AIProvider.provider(for: "continue") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: continuePrompts,
                directoryPath: home.appending(path: ".continue/prompts").path
            ))
        }

        // Cline: ~/.cline/rules/
        let clineRules = scanDirectory(home.appending(path: ".cline/rules"), providerID: "cline")
        if !clineRules.isEmpty, let provider = AIProvider.provider(for: "cline") {
            results.append(ProviderScanResult(
                provider: provider,
                skills: clineRules,
                directoryPath: home.appending(path: ".cline/rules").path
            ))
        }

        logger.info("Skill scan complete: \(results.count) providers found, \(results.reduce(0) { $0 + $1.skills.count }) total skills")
        return results
    }

    /// Scan a user-chosen custom directory and return a result with a "custom" provider.
    static func scanCustomDirectory(_ url: URL) -> ProviderScanResult? {
        let skills = scanDirectory(url, providerID: "custom")
        guard !skills.isEmpty else { return nil }
        let folderName = url.lastPathComponent.localizedCapitalized
        let provider = AIProvider(
            id: "custom:\(url.path)",
            displayName: folderName,
            color: FolderColorToken.gold.rawValue,
            iconSymbol: "folder"
        )
        return ProviderScanResult(
            provider: provider,
            skills: skills,
            directoryPath: url.path
        )
    }

    // MARK: - Private

    /// Scan a single directory for markdown/rule files, including one level of subdirectories.
    private static func scanDirectory(_ url: URL, providerID: String) -> [DiscoveredSkill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }

        var skills: [DiscoveredSkill] = []
        let validExtensions: Set<String> = ["md", "mdc", "txt", "rules", "prompt", "yaml", "yml"]

        // Direct files in directory
        if let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

                if isDir {
                    // Check for SKILL.md or skill.md inside subdirectory
                    let skillFile = findSkillFile(in: item)
                    if let skillFile {
                        if let skill = parseSkillFile(skillFile, providerID: providerID, parentName: item.lastPathComponent) {
                            skills.append(skill)
                        }
                    }
                } else if validExtensions.contains(item.pathExtension.lowercased()) {
                    if let skill = parseSkillFile(item, providerID: providerID, parentName: nil) {
                        skills.append(skill)
                    }
                }
            }
        }

        return skills
    }

    /// Look for the primary skill file inside a skill subdirectory.
    private static func findSkillFile(in directory: URL) -> URL? {
        let candidates = ["SKILL.md", "skill.md", "README.md"]
        let fm = FileManager.default
        for candidate in candidates {
            let path = directory.appending(path: candidate)
            if fm.fileExists(atPath: path.path) {
                return path
            }
        }
        // Fallback: first .md file
        if let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            return items.first { $0.pathExtension.lowercased() == "md" }
        }
        return nil
    }

    /// Parse a skill file, extracting name and description from YAML frontmatter if present.
    private static func parseSkillFile(_ url: URL, providerID: String, parentName: String?) -> DiscoveredSkill? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let (name, description) = parseFrontmatter(content: content, fileName: parentName ?? url.deletingPathExtension().lastPathComponent)

        return DiscoveredSkill(
            providerID: providerID,
            fileName: url.lastPathComponent,
            filePath: url,
            content: content,
            name: name,
            description: description
        )
    }

    /// Extract name and description from YAML frontmatter, falling back to filename.
    private static func parseFrontmatter(content: String, fileName: String) -> (name: String, description: String) {
        var name = fileName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
        var description = ""

        // Check for YAML frontmatter (--- delimited)
        if content.hasPrefix("---") {
            let lines = content.components(separatedBy: "\n")
            var inFrontmatter = false
            for (index, line) in lines.enumerated() {
                if index == 0 && line.trimmingCharacters(in: .whitespaces) == "---" {
                    inFrontmatter = true
                    continue
                }
                if inFrontmatter && line.trimmingCharacters(in: .whitespaces) == "---" {
                    break
                }
                if inFrontmatter {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.lowercased().hasPrefix("name:") {
                        let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { name = value }
                    } else if trimmed.lowercased().hasPrefix("description:") {
                        let value = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { description = value }
                    }
                }
            }
        }

        // Fallback description: first non-empty, non-frontmatter line
        if description.isEmpty {
            let lines = content.components(separatedBy: "\n")
            var pastFrontmatter = !content.hasPrefix("---")
            var closedFrontmatter = false
            for line in lines {
                if !pastFrontmatter {
                    if closedFrontmatter { pastFrontmatter = true }
                    if line.trimmingCharacters(in: .whitespaces) == "---" {
                        closedFrontmatter = !closedFrontmatter || true
                        if closedFrontmatter { pastFrontmatter = true; continue }
                    }
                    continue
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    .trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    description = String(trimmed.prefix(120))
                    break
                }
            }
        }

        return (name, description)
    }
}
