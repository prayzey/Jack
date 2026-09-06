import SwiftUI

/// The clip search text field shared by every view mode (tray, drawer, grid,
/// radial, panel).
///
/// Typing edits a local `draft` and commits to `store.searchText` through
/// `SearchCommitDebouncer` after a short idle pause. Do not rebind this field
/// to `$store.searchText` directly — per-keystroke writes publish through the
/// store and re-render the whole mode window, which is the lag this component
/// exists to prevent.
///
/// External writes to `store.searchText` (dismiss clearing it, typed-seed
/// activation appending to it, AI search rewriting it) sync back into the
/// draft and cancel any pending commit so stale text can't reappear.
struct ClipSearchTextField: View {
    @EnvironmentObject private var store: ClipboardStore

    let placeholder: String
    var font: Font = .system(size: 12)
    var textColor: Color = .white
    var focus: FocusState<Bool>.Binding
    var onEscape: () -> Void = {}
    var onSubmit: (() -> Void)? = nil

    @State private var draft = ""
    @State private var debouncer = SearchCommitDebouncer()

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .foregroundStyle(textColor)
            .font(font)
            .focused(focus)
            .onSubmit {
                // Flush before the submit action so handlers (AI interpret)
                // see the final query, not the last committed prefix.
                flushDraft()
                onSubmit?()
            }
            .onKeyPress(.escape) {
                onEscape()
                return .handled
            }
            .onAppear { draft = store.searchText }
            .onChange(of: draft) { _, newValue in
                guard newValue != store.searchText else { return }
                debouncer.textChanged(newValue) { [weak store] committed in
                    guard let store, store.searchText != committed else { return }
                    store.searchText = committed
                }
            }
            .onChange(of: store.searchText) { _, newValue in
                guard newValue != draft else { return }
                debouncer.cancelPending()
                draft = newValue
            }
            .onDisappear { debouncer.cancelPending() }
    }

    private func flushDraft() {
        debouncer.cancelPending()
        if store.searchText != draft {
            store.searchText = draft
        }
    }
}
