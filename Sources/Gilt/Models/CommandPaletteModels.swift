import SwiftUI

/// A runnable command surfaced in both the command palette and the grid
/// launchpad. The `run` closure is the single source of truth for "what this
/// action does", so the palette and the launchpad never drift apart.
///
/// `run` is `@MainActor` because every action it can perform (showing a window,
/// switching view mode, starting dictation) touches main-actor UI state.
struct CommandAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    /// Extra words matched against the query so, e.g., typing "record" surfaces
    /// "Meetings". Kept separate from `title`/`subtitle` so the visible copy stays
    /// clean while search stays forgiving.
    let keywords: [String]
    /// Pre-formatted shortcut hint to display (e.g. "⌥Space"), or nil when the
    /// action has no global shortcut.
    let shortcutHint: String?
    let run: @MainActor () -> Void
}

/// Which group a palette result belongs to. `rawValue` also defines the order
/// the sections render in, so actions always sit above content.
enum CommandPaletteSection: Int, CaseIterable, Identifiable {
    case actions
    case clips
    case notes
    case meetings
    case reminders

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .actions: return "Actions"
        case .clips: return "Clipboard"
        case .notes: return "Notes"
        case .meetings: return "Meetings"
        case .reminders: return "Reminders"
        }
    }
}

/// A single selectable row in the palette, flattened across all sections so
/// keyboard up/down navigation is a simple index walk. `run` performs the row's
/// action; the palette dismisses itself first, then calls it.
struct CommandPaletteItem: Identifiable {
    let id: String
    let section: CommandPaletteSection
    let title: String
    let subtitle: String?
    let systemImage: String
    let accent: Color
    /// Trailing detail shown right-aligned: a shortcut hint for actions, or a
    /// relative timestamp for content rows.
    let trailingText: String?
    let run: @MainActor () -> Void
}
