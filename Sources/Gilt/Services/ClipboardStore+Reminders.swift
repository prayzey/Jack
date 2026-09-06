import Foundation

/// Store-level funnel for the one-way Apple Reminders mirror.
///
/// All reminder creation should go through `addPulseReminder(_:)` so there is a
/// single place that both persists the in-app reminder and (when the user has
/// opted in) mirrors it to Apple Reminders. Keeping this on the store means
/// future reminder-editor UI just calls one method instead of re-implementing
/// the mirror handshake.
extension ClipboardStore {
    /// Whether Apple Reminders sync is currently turned on.
    var appleRemindersSyncEnabled: Bool {
        RemindersSyncService.shared.isSyncEnabled
    }

    /// Add an in-app reminder and, if sync is enabled, mirror it to Apple
    /// Reminders. Appending to `settings.pulseReminders` triggers the store's
    /// `settings.didSet`, which persists the change — so we do not persist here.
    func addPulseReminder(_ reminder: PulseReminder) {
        settings.pulseReminders.append(reminder)
        guard RemindersSyncService.shared.isSyncEnabled else { return }
        Task { await RemindersSyncService.shared.mirror(reminder) }
    }

    /// Remove an in-app reminder. We intentionally do *not* delete its mirror in
    /// Apple Reminders: the sync is one-way and we never delete the user's Apple
    /// reminders on their behalf (see `RemindersSyncService`). Mutating
    /// `settings.pulseReminders` persists via the store's `settings.didSet`.
    func removePulseReminder(_ id: UUID) {
        settings.pulseReminders.removeAll { $0.id == id }
    }

    /// Turn Apple Reminders sync on or off.
    ///
    /// Enabling prompts for system permission the first time; if the user
    /// declines we leave the toggle off and report that back so the UI can
    /// reflect reality. On a successful enable we back-fill any reminders the
    /// user already had so nothing is silently left behind.
    ///
    /// Returns the *effective* enabled state after the permission handshake.
    @discardableResult
    func setAppleRemindersSync(enabled: Bool) async -> Bool {
        guard enabled else {
            RemindersSyncService.shared.isSyncEnabled = false
            return false
        }

        let granted = await RemindersSyncService.shared.requestAccess()
        RemindersSyncService.shared.isSyncEnabled = granted
        if granted {
            await RemindersSyncService.shared.mirrorAll(settings.pulseReminders)
        }
        return granted
    }
}
