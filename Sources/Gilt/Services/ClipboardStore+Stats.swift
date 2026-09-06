import Combine
import Foundation

extension ClipboardStore {
    /// Bridge `transcriptionStatsStore.objectWillChange` into the store's own
    /// publisher so any view observing `ClipboardStore` repaints when stats
    /// change. This lets the sidebar teaser stay live without every leaf view
    /// having to inject its own `@ObservedObject`.
    func wireTranscriptionStats() {
        transcriptionStatsCancellable = transcriptionStatsStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

}
