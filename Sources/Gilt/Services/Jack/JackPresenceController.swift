import AppKit
import Foundation

/// Drives Jack's on-screen presence from `JackSettings`.
///
/// Background: the object that used to own a `PulseCharacterPerformer` and react
/// to the presence setting (`PulseUsageCharacterAnnouncer`) was removed when the
/// usage-monitoring feature was deleted. That left the "Always on" presence mode
/// with no effect: flipping it in Settings saved the value, but nothing parked
/// Jack above the dock. This controller restores that link with a small surface
/// — it owns the performer, maps the chosen `look` to its walk video, and parks
/// or hides Jack as the mode changes (live and at launch).
///
/// It deliberately covers only what the presence setting needs. The legacy
/// "appears on triggers" walk depended on the deleted usage pipeline, so in
/// `onTriggers` mode Jack stays hidden (no regression — nothing drove that walk
/// before this either) until a trigger source is rebuilt.
@MainActor
final class JackPresenceController {
    /// What `apply` should do for a given presence transition. Pure result of
    /// `resolveAction` so the decision can be unit-tested without touching
    /// `NSScreen` / `NSWindow`.
    enum PresenceAction: Equatable {
        /// Ensure the performer exists and park him above the dock.
        case park
        /// Leave parked mode, hide the performer, and dismiss the popover.
        case hide
        /// Nothing relevant changed — leave the current presentation alone.
        case none
    }

    /// Reminders shown in the popover's Reminders tab. Read on each click so the
    /// list reflects the user's latest edits.
    private let remindersProvider: () -> [PulseReminder]
    /// Which popover tab opens first when Jack is clicked.
    private let defaultTabProvider: () -> JackPopoverTab
    /// Chat thread backing the popover's Chat tab.
    private let chatStore: JackChatStore
    /// Turn Jack off from the popover's power button (sets presence to `.off`,
    /// which flows back through settings and hides him) so the user doesn't have
    /// to open Settings to dismiss an always-on Jack.
    private let onTurnOff: () -> Void
    /// Create a reminder from the popover composer.
    private let addReminder: (PulseReminder) -> Void
    /// Delete a reminder from the popover list.
    private let deleteReminder: (UUID) -> Void

    private let popover = JackPopoverController()

    private var performer: PulseCharacterPerformer?
    /// Look the current `performer` was built for. A performer is bound to one
    /// walk video at init, so a look change tears it down and rebuilds.
    private var performerLook: JackLook?
    private var currentMode: JackPresenceMode = .off

    init(
        chatStore: JackChatStore,
        remindersProvider: @escaping () -> [PulseReminder],
        defaultTabProvider: @escaping () -> JackPopoverTab,
        onTurnOff: @escaping () -> Void,
        addReminder: @escaping (PulseReminder) -> Void,
        deleteReminder: @escaping (UUID) -> Void
    ) {
        self.chatStore = chatStore
        self.remindersProvider = remindersProvider
        self.defaultTabProvider = defaultTabProvider
        self.onTurnOff = onTurnOff
        self.addReminder = addReminder
        self.deleteReminder = deleteReminder
    }

    /// Apply a presence-mode / look combination. Safe to call on every relevant
    /// settings change and once at launch — it only re-triggers the parking walk
    /// on an actual transition into `alwaysOn` or a look swap, so an unrelated
    /// settings save can't restart the walk-in animation.
    func apply(presenceMode mode: JackPresenceMode, look: JackLook) {
        let lookChanged = performerLook != nil && performerLook != look
        if lookChanged {
            // Rebuild for the new character: the performer is bound to one video
            // at init, so swapping looks means a fresh performer.
            performer?.hideImmediately()
            performer = nil
            performerLook = nil
            popover.close()
        }

        let action = Self.resolveAction(
            previousMode: currentMode,
            newMode: mode,
            lookChanged: lookChanged,
            hasPerformer: performer != nil
        )
        currentMode = mode

        switch action {
        case .none:
            break
        case .hide:
            performer?.leaveParkedMode()
            performer?.hideImmediately()
            popover.close()
        case .park:
            guard let screen = Self.dockScreen() else { return }
            let performer = ensurePerformer(for: look)
            performer.parkAboveDock(on: screen)
        }
    }

    /// Pure decision: given the previous and new presence modes (plus whether
    /// the look changed and whether a performer already exists), what should
    /// `apply` do? Kept side-effect-free so it can be exhaustively unit-tested.
    nonisolated static func resolveAction(
        previousMode: JackPresenceMode,
        newMode: JackPresenceMode,
        lookChanged: Bool,
        hasPerformer: Bool
    ) -> PresenceAction {
        switch newMode {
        case .off, .onTriggers:
            return .hide
        case .alwaysOn:
            // Re-park only on a real transition, a look swap, or when there's no
            // performer yet (the launch case). Otherwise leave him where he is.
            let needsPark = previousMode != newMode || lookChanged || !hasPerformer
            return needsPark ? .park : .none
        }
    }

    private func ensurePerformer(for look: JackLook) -> PulseCharacterPerformer {
        if let performer, performerLook == look { return performer }
        let performer = PulseCharacterPerformer(
            videoName: Self.videoName(for: look),
            displayHeight: 154,
            walkProfile: Self.walkProfile(for: look)
        )
        performer.onClick = { [weak self] performer in
            self?.handleClick(on: performer)
        }
        self.performer = performer
        performerLook = look
        return performer
    }

    /// Toggle the chat / reminders popover when the user clicks Jack.
    private func handleClick(on performer: PulseCharacterPerformer) {
        if popover.isAttached(to: performer) {
            popover.close()
        } else {
            popover.present(
                attachedTo: performer,
                chatStore: chatStore,
                defaultTab: defaultTabProvider(),
                actions: JackPopoverController.Actions(
                    remindersProvider: remindersProvider,
                    onTurnOff: { [weak self] in
                        // Close the popover first so it doesn't linger after Jack
                        // hides, then flip presence off via the injected handler.
                        self?.popover.close()
                        self?.onTurnOff()
                    },
                    onAddReminder: addReminder,
                    onDeleteReminder: deleteReminder
                )
            )
        }
    }

    /// Map a look to its bundled walk video in `Resources/PulseCharacters`.
    nonisolated static func videoName(for look: JackLook) -> String {
        switch look {
        case .bruce: return "walk-bruce-01"
        }
    }

    /// Per-character walk tuning (accel/decel timing, vertical offset, etc.).
    nonisolated static func walkProfile(for look: JackLook) -> PulseCharacterPerformer.WalkProfile {
        switch look {
        case .bruce: return .bruce
        }
    }

    /// Pick the screen whose dock area is visible so Jack parks above the dock.
    /// Mirrors the screen selection the removed announcer used: prefer a screen
    /// with reserved dock space, then any screen with a reserved bottom strip,
    /// then the main screen.
    private static func dockScreen() -> NSScreen? {
        if let dockScreen = NSScreen.screens.first(where: {
            DockVisibility.screenHasVisibleDockReservedArea(
                screenFrame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        }) {
            return dockScreen
        }
        if let reserved = NSScreen.screens.first(where: { $0.visibleFrame.maxY < $0.frame.maxY }) {
            return reserved
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
