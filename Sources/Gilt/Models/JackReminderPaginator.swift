import Foundation

/// Pure pagination math for the Jack reminders list. Side-effect-free so page
/// counts and clamping are unit-testable, and so the view stays declarative.
enum JackReminderPaginator {
    /// Number of pages needed to show `total` items `pageSize` at a time.
    /// Always at least 1 (an empty list still has one — empty — page).
    static func pageCount(total: Int, pageSize: Int) -> Int {
        guard pageSize > 0, total > 0 else { return 1 }
        return (total + pageSize - 1) / pageSize
    }

    /// Clamp a (possibly stale) page index into the valid range after the list
    /// size or page size changed (e.g. a delete dropped the last page).
    static func clampedPage(_ page: Int, total: Int, pageSize: Int) -> Int {
        let last = pageCount(total: total, pageSize: pageSize) - 1
        return min(max(0, page), last)
    }

    /// The slice of `items` shown on `page`. Clamps the page first so a stale
    /// index never reads out of bounds.
    static func page<T>(_ items: [T], page: Int, pageSize: Int) -> [T] {
        guard pageSize > 0, !items.isEmpty else { return [] }
        let p = clampedPage(page, total: items.count, pageSize: pageSize)
        let start = p * pageSize
        let end = Swift.min(start + pageSize, items.count)
        guard start < end else { return [] }
        return Array(items[start..<end])
    }
}
