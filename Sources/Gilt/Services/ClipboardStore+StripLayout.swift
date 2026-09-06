import Foundation

extension ClipboardStore {
    // MARK: - Strip Layout

    /// Keep strip arrangement together so drag/drop, separators, and visual ordering
    /// live in one place instead of being scattered through the main store file.

    /// Merges filteredClips and separators for the current folder into a unified strip.
    func computeStripItems() -> [ClipStripItem] {
        let clips = filteredClips
        guard let folder = selectedFolder else {
            return clips.enumerated().map { .clip($1, index: $0) }
        }
        let separators = folder.separators
        guard !separators.isEmpty else {
            return clips.enumerated().map { .clip($1, index: $0) }
        }

        var items: [ClipStripItem] = clips.enumerated().map { .clip($1, index: $0) }
        items.append(contentsOf: separators.map { .separator($0) })

        // Sort: pinned first, then sortOrder DESC, then createdAt DESC.
        // At equal sortOrder, separators come first because they mark a section start.
        items.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            if a.sortOrder != b.sortOrder { return a.sortOrder > b.sortOrder }
            if case .separator = a, case .clip = b { return true }
            if case .clip = a, case .separator = b { return false }
            return a.createdAt > b.createdAt
        }
        return items
    }

    func addSeparator(afterClipID: UUID?, label: String = L10n.string("folder.separator.default", default: "Section")) {
        addSeparator(afterStripItemID: afterClipID, label: label)
    }

    func addSeparator(afterStripItemID itemID: UUID?, label: String = L10n.string("folder.separator.default", default: "Section")) {
        // The main Clipboard tab is the raw inbox. Separators belong only to
        // explicit folders, so this guard protects the model even if UI checks regress.
        guard let folder = selectedFolder, folder.supportsSeparators else { return }

        let separator = FolderSeparatorModel(
            label: label,
            colorRaw: folder.resolvedColor.rawString,
            sortOrder: 0,
            folder: folder
        )
        modelContext.insert(separator)

        let group = stripItems.filter { !$0.isPinned }
        if let itemID,
           let itemIndex = group.firstIndex(where: { $0.id == itemID }) {
            var reordered = group
            reordered.insert(.separator(separator), at: itemIndex + 1)
            assignStripSortOrders(reordered)
        } else if let firstItem = group.first {
            var reordered = group
            let insertionIndex = reordered.firstIndex(where: { $0.id == firstItem.id }) ?? reordered.endIndex
            reordered.insert(.separator(separator), at: min(insertionIndex + 1, reordered.count))
            assignStripSortOrders(reordered)
        } else if let firstItem = stripItems.first {
            let group = stripItems.filter { $0.isPinned == firstItem.isPinned }
            if !group.isEmpty {
                var reordered = group
                reordered.append(.separator(separator))
                assignStripSortOrders(reordered)
            }
        }

        save()
        invalidateFilteredClips(reason: "separator-add")
        logState("addSeparator label=\"\(label)\" folder=\(folder.name)")
    }

    func renameSeparator(_ separatorID: UUID, to newLabel: String) {
        guard let folder = selectedFolder,
              let separator = folder.separators.first(where: { $0.separatorID == separatorID }) else { return }
        separator.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        invalidateFilteredClips(reason: "separator-rename")
    }

    func setSeparatorColor(_ separatorID: UUID, to color: ResolvedColor) {
        guard let folder = selectedFolder,
              let separator = folder.separators.first(where: { $0.separatorID == separatorID }) else { return }
        separator.colorRaw = color.rawString
        save()
        invalidateFilteredClips(reason: "separator-color")
    }

    func canMoveSeparator(_ separatorID: UUID, direction: SeparatorMoveDirection) -> Bool {
        let visible = stripItems.filter { !$0.isPinned }
        guard let currentIndex = visible.firstIndex(where: { item in
            guard case .separator(let separator) = item else { return false }
            return separator.separatorID == separatorID
        }) else {
            return false
        }

        switch direction {
        case .left:
            return currentIndex > 0
        case .right:
            return currentIndex < visible.count - 1
        }
    }

    func moveSeparator(_ separatorID: UUID, direction: SeparatorMoveDirection) {
        guard let folder = selectedFolder, folder.supportsSeparators else { return }

        let visible = stripItems.filter { !$0.isPinned }
        guard let currentIndex = visible.firstIndex(where: { item in
            guard case .separator(let separator) = item else { return false }
            return separator.separatorID == separatorID
        }) else {
            return
        }

        let targetIndex: Int
        switch direction {
        case .left:
            targetIndex = currentIndex - 1
        case .right:
            targetIndex = currentIndex + 1
        }

        guard visible.indices.contains(targetIndex) else { return }

        var reordered = visible
        let moved = reordered.remove(at: currentIndex)
        reordered.insert(moved, at: targetIndex)
        assignStripSortOrders(reordered)

        save()
        invalidateFilteredClips(reason: "separator-move")
        logState("moveSeparator \(separatorID.uuidString.prefix(8)) direction=\(direction.rawValue) folder=\(folder.name)")
    }

    func moveStripItem(_ draggedItem: StripDragItem, before targetID: UUID) {
        moveStripItem(draggedItem, relativeTo: targetID, placement: .before)
    }

    func moveStripItem(_ draggedItem: StripDragItem, relativeTo targetID: UUID, placement: StripReorderPlacement) {
        guard draggedItem.id != targetID else { return }
        guard let dragged = stripItem(matching: draggedItem),
              let target = stripItems.first(where: { $0.id == targetID }),
              dragged.isPinned == target.isPinned else {
            return
        }

        let groupedItems = stripItems.filter { $0.isPinned == dragged.isPinned }
        let currentOrder = groupedItems.map(\.id)
        guard let reorderedIDs = reorderedStripIDs(
            ids: currentOrder,
            draggedID: dragged.id,
            targetID: targetID,
            placement: placement
        ) else {
            return
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: groupedItems.map { ($0.id, $0) })
        let reordered = reorderedIDs.compactMap { itemsByID[$0] }
        guard reordered.count == groupedItems.count else { return }

        assignStripSortOrders(reordered)

        save()
        invalidateFilteredClips(reason: "strip-move")
        logState(
            "moveStripItem \(draggedItem.id.uuidString.prefix(8)) "
                + "\(placement == .before ? "before" : "after") "
                + "\(targetID.uuidString.prefix(8))"
        )
    }

    func deleteSeparator(_ separatorID: UUID) {
        guard let folder = selectedFolder,
              let separator = folder.separators.first(where: { $0.separatorID == separatorID }) else { return }
        modelContext.delete(separator)
        save()
        invalidateFilteredClips(reason: "separator-delete")
        logState("deleteSeparator \(separatorID.uuidString.prefix(8))")
    }

    // MARK: - Clip Reordering

    /// Reorder a clip by placing it before another clip in the current view.
    /// Only updates sortOrder values — createdAt timestamps are never touched.
    func moveClip(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        let visible = filteredClips
        guard let draggedClip = visible.first(where: { $0.clipID == draggedID }),
              let targetClip = visible.first(where: { $0.clipID == targetID }),
              draggedClip.isPinned == targetClip.isPinned else { return }

        let group = visible.filter { $0.isPinned == draggedClip.isPinned }
        guard let draggedIndex = group.firstIndex(where: { $0.clipID == draggedID }),
              let targetIndex = group.firstIndex(where: { $0.clipID == targetID }) else { return }
        guard draggedIndex != targetIndex else { return }

        var reordered = group
        let dragged = reordered.remove(at: draggedIndex)
        let insertAt = reordered.firstIndex(where: { $0.clipID == targetID }) ?? reordered.endIndex
        reordered.insert(dragged, at: insertAt)

        // Use descending sortOrder so the first visual item remains the highest-priority item.
        let base = reordered.count
        for (index, clip) in reordered.enumerated() {
            clip.sortOrder = base - index
        }
        save()
        // Do not refetch from SwiftData here. The in-memory reference objects already carry
        // the new sort order, and a full refresh causes a visible flash during drag.
        invalidateFilteredClips(reason: "reorder")
        logState("moveClip \(draggedID.uuidString.prefix(8)) before \(targetID.uuidString.prefix(8))")
    }

    private func stripItem(matching draggedItem: StripDragItem) -> ClipStripItem? {
        stripItems.first { item in
            switch (draggedItem, item) {
            case (.clip(let id), .clip(let clip, _)):
                return clip.clipID == id
            case (.separator(let id), .separator(let separator)):
                return separator.separatorID == id
            default:
                return false
            }
        }
    }

    private func assignStripSortOrders(_ items: [ClipStripItem]) {
        // Higher sortOrder renders farther left, so we rewrite the whole visible lane
        // from left to right whenever the user inserts or reorders strip content.
        let base = items.count
        for (index, item) in items.enumerated() {
            let sortOrder = base - index
            switch item {
            case .clip(let clip, _):
                clip.sortOrder = sortOrder
            case .separator(let separator):
                separator.sortOrder = sortOrder
            }
        }
    }
}
