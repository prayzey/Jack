import Foundation

/// Pure helpers for the index math behind drag-reordering folders and notes.
///
/// The store mutates `sortOrder` integers based on the user-visible reordered
/// list. The "interesting" part — and the part that's easy to get subtly
/// wrong without tests — is that when the user drags an item *downwards*, the
/// visible target index is computed against the pre-removal list, but the
/// insertion happens against the post-removal list, so the target shifts up
/// by one. Capture that as a pure function so the store stays a thin caller.
enum NoteOrdering {

    /// Compute the result of moving the item at `currentIndex` to
    /// `targetIndex` in a list. Returns the new visible ordering as a list of
    /// the existing item IDs in their new positions.
    ///
    /// `targetIndex` is interpreted against the list *before* removal — the
    /// natural way callers see drop slots. The function adjusts internally.
    /// Out-of-range targets clamp to `[0, list.count]`. Dropping onto an
    /// item's own slot (or the slot directly after itself) is a no-op and
    /// returns the input unchanged.
    static func reorder<Item>(_ list: [Item], from currentIndex: Int, to targetIndex: Int) -> [Item] {
        guard currentIndex >= 0, currentIndex < list.count else { return list }
        // Clamp the drop slot to a legal range, then translate the
        // "pre-removal" target into the "post-removal" insert position.
        let clamped = max(0, min(targetIndex, list.count))
        let insertAt = clamped > currentIndex ? clamped - 1 : clamped
        if insertAt == currentIndex { return list } // no-op drop
        var working = list
        let item = working.remove(at: currentIndex)
        working.insert(item, at: max(0, min(insertAt, working.count)))
        return working
    }
}
