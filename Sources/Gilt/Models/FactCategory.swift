import Foundation

/// One distilled thing Jack remembers about the user. Categories exist so the
/// memory system can apply per-bucket caps and pruning — without categories,
/// one runaway area (every app the user has ever opened, for example) would
/// crowd out higher-value facts like identity.
///
/// The raw values are persisted to SwiftData via `FactModel.categoryRaw`, so
/// they must remain stable. Adding a new category is safe; renaming an
/// existing one is a breaking change for stored facts.
enum FactCategory: String, Codable, CaseIterable, Identifiable {
    /// Who the user is: name, role, location, pronouns.
    case identity
    /// Apps, languages, frameworks, devices the user works with.
    case tools
    /// Named, recurring things the user works on (codebases, products,
    /// clients). Single-shot project mentions should land in `misc` until
    /// reinforcement promotes them.
    case projects
    /// How the user likes things: dark mode, tabs over spaces, vim
    /// bindings, terse responses, etc.
    case preferences
    /// The user's domain: industry, what they build for a living, who
    /// their audience is.
    case domain
    /// Catch-all for facts that don't fit elsewhere. Kept deliberately
    /// last so it never beats a more specific bucket.
    case misc

    var id: String { rawValue }

    /// Plain-English label shown in the settings panel.
    var displayName: String {
        switch self {
        case .identity: return "Identity"
        case .tools: return "Tools"
        case .projects: return "Projects"
        case .preferences: return "Preferences"
        case .domain: return "Domain"
        case .misc: return "Other"
        }
    }

    /// Max number of facts allowed in this category before eviction. Used by
    /// the future pruning pass (step 4). Identity stays small and curated;
    /// tools and misc are the buckets most likely to grow.
    var capacity: Int {
        switch self {
        case .identity: return 5
        case .tools: return 15
        case .projects: return 8
        case .preferences: return 10
        case .domain: return 5
        case .misc: return 12
        }
    }
}

/// Where a fact came from. Surfaced in the settings UI via a small badge so
/// users can see *why* Jack thinks something — manual entries earn more trust
/// than screen-extracted ones, and users can decide what to keep.
enum FactSource: String, Codable, CaseIterable, Identifiable {
    /// The user typed it themselves in the settings panel.
    case manual
    /// Pulled from the license activation flow (e.g. customer name).
    case license
    /// Extracted from a "read my screen" context query.
    case screen
    /// Extracted from a Jack chat turn. Reserved for future use.
    case chat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .license: return "License"
        case .screen: return "Screen"
        case .chat: return "Chat"
        }
    }
}
