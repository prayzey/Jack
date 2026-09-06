import Foundation

/// Unified item for the clip strip — either a real clip or a visual separator.
enum ClipStripItem: Identifiable {
    case clip(ClipItemModel, index: Int)
    case separator(FolderSeparatorModel)

    var id: UUID {
        switch self {
        case .clip(let item, _): return item.clipID
        case .separator(let sep): return sep.separatorID
        }
    }

    /// Sort key for interleaving clips and separators.
    /// Uses the shared sortOrder space — higher values appear first (left).
    var sortOrder: Int {
        switch self {
        case .clip(let item, _): return item.sortOrder
        case .separator(let sep): return sep.sortOrder
        }
    }

    var isPinned: Bool {
        switch self {
        case .clip(let item, _): return item.isPinned
        case .separator: return false
        }
    }

    var createdAt: Date {
        switch self {
        case .clip(let item, _): return item.createdAt
        case .separator: return .distantPast
        }
    }
}
