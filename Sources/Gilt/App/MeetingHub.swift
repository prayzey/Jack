import Foundation

/// Singleton that owns the meeting-feature backing state (store + controller).
/// Lives outside `ClipboardStore` so meetings remain a self-contained domain
/// even though they share the same `@EnvironmentObject` graph as the rest of
/// the workspace.
///
/// The workspace meeting view reaches in through `MeetingHub.shared.store` and
/// `MeetingHub.shared.controller`. There's no separate window — meetings live
/// inside the existing workspace tab system.
@MainActor
final class MeetingHub {
    static let shared = MeetingHub()

    /// Built lazily so the meeting subsystem doesn't pay any cost on launch
    /// when the user never opens it. The disk scan + UserDefaults read are
    /// cheap, but lazy keeps cold launch snappy regardless.
    private var _store: MeetingStore?
    private var _controller: MeetingSessionController?

    private init() {}

    var store: MeetingStore {
        if let _store { return _store }
        let store = MeetingStore()
        _store = store
        return store
    }

    var controller: MeetingSessionController {
        if let _controller { return _controller }
        let controller = MeetingSessionController(store: store)
        _controller = controller
        return controller
    }

    func focusMeeting(_ meetingID: UUID?) {
        if let meetingID {
            controller.selectMeeting(meetingID)
        } else {
            controller.clearSelection()
        }
    }
}
