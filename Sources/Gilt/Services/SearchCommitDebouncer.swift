import Foundation

/// Debounces commits of a search draft into shared state.
///
/// Used by `ClipSearchTextField` so each keystroke edits a view-local draft
/// instead of writing straight to `ClipboardStore.searchText`. The store
/// property is `@Published`; writing it per keystroke fires
/// `objectWillChange` and re-renders every store-observing view in the
/// window (card grid, drawer rows, radial ring), which is what made search
/// feel laggy outside the tray. Committing only after a short idle pause
/// keeps typing at field-editor speed while results still feel live.
@MainActor
final class SearchCommitDebouncer {
    private var pending: Task<Void, Never>?
    private let interval: Duration

    init(interval: Duration = .milliseconds(50)) {
        self.interval = interval
    }

    /// Schedule `commit(text)` after the idle interval, replacing any pending
    /// commit. Empty text commits immediately so clearing the field never lags.
    func textChanged(_ text: String, commit: @escaping @MainActor (String) -> Void) {
        pending?.cancel()
        pending = nil
        guard !text.isEmpty else {
            commit("")
            return
        }
        pending = Task { [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            commit(text)
        }
    }

    /// Drop any scheduled commit without firing it. Called when the store
    /// text changes externally (dismiss, AI rewrite) so a stale draft can't
    /// resurrect itself after the field was cleared.
    func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
