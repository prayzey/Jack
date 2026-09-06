import CoreServices
import Foundation

/// Watches the vault subtree for changes via FSEvents and forwards a single
/// debounced notification (Obsidian saves via temp-write + rename, which fires
/// several raw events). One recursive stream covers the whole vault.
///
/// `@unchecked Sendable`: it owns an `FSEventStreamRef` (not Sendable), but every
/// access to that mutable state happens on `queue` — start/stop dispatch to it,
/// and FSEvents delivers callbacks on it (FSEventStreamSetDispatchQueue).
final class VaultWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "ink.jack.vault-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    init(vaultPath: String, onChange: @escaping @Sendable () -> Void) {
        self.path = vaultPath
        self.onChange = onChange
    }

    func start() { queue.async { [weak self] in self?.startStream() } }
    func stop() { queue.async { [weak self] in self?.stopStream() } }

    private func startStream() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().scheduleNotify()
        }
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        debounce?.cancel()
        debounce = nil
    }

    /// Coalesce a burst of raw events into one `onChange` after a short quiet
    /// period. Runs on `queue`, so the mutable `debounce` is single-threaded.
    private func scheduleNotify() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
