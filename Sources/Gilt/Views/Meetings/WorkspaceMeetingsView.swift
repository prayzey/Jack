import AppKit
import SwiftUI

/// Meetings surface embedded inside the workspace. Renders inside
/// `WorkspaceDetailView` whenever the user has a `.meetings` tab open.
///
/// Layout mirrors the rest of the workspace:
///   - 28px horizontal padding, 26px top padding
///   - Gold monospaced eyebrow + 30pt bold title
///   - Hairline `Color.white.opacity(0.06)` dividers between rows
///   - Subtle white-opacity action buttons (no purple gradients)
///
/// When the user is in a meeting (recording, viewing transcript/summary/ask),
/// the same surface swaps to the corresponding panel — no separate window.
struct WorkspaceMeetingsView: View {
    @EnvironmentObject private var clipboardStore: ClipboardStore
    @ObservedObject private var meetingStore = MeetingHub.shared.store
    @ObservedObject private var controller = MeetingHub.shared.controller

    @State private var presentingNew = false
    @State private var presentingModels = false
    @State private var hostWindow: NSWindow?

    private var accent: Color { MeetingAccent.gold }

    var body: some View {
        Group {
            if controller.currentMeetingID != nil {
                MeetingDetailSurface(
                    accent: accent,
                    onClose: {
                        controller.clearSelection()
                    },
                    onOpenModels: { presentingModels = true },
                    onDelete: { id in confirmDelete(id) }
                )
                .environmentObject(meetingStore)
                .environmentObject(controller)
            } else {
                MeetingDashboardView(
                    meetingStore: meetingStore,
                    accent: accent,
                    onNew: { presentingNew = true },
                    onOpenModels: { presentingModels = true },
                    onSelect: { id in
                        controller.selectMeeting(id)
                    },
                    onDelete: { id in confirmDelete(id) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            WindowAccessor { window in
                hostWindow = window
            }
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $presentingNew) {
            MeetingNewSheetView(
                meetingStore: meetingStore,
                modelManager: controller.modelManager,
                accent: accent,
                onCreated: { session in
                    presentingNew = false
                    Task { await controller.startRecording(for: session) }
                },
                onCancel: { presentingNew = false }
            )
        }
        .sheet(isPresented: $presentingModels) {
            MeetingModelSettingsView(
                meetingStore: meetingStore,
                modelManager: controller.modelManager,
                accent: accent
            )
            .frame(minWidth: 620, minHeight: 520)
        }
    }

    private func confirmDelete(_ meetingID: UUID) {
        guard let session = meetingStore.session(for: meetingID) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(session.displayTitle)”?"
        alert.informativeText = "This removes the recording audio, transcript, summary, and Q&A history from this Mac. This can’t be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        if let parentWindow = hostWindow ?? NSApp.keyWindow ?? NSApp.mainWindow {
            parentWindow.makeKeyAndOrderFront(nil)
            alert.window.level = WorkspaceModalPresentation.alertLevel(parentLevel: parentWindow.level)
            alert.beginSheetModal(for: parentWindow) { response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor in
                    controller.deleteMeeting(meetingID)
                }
            }
        } else {
            alert.window.level = WorkspaceModalPresentation.alertLevel(parentLevel: nil)
            guard alert.runModalInFront() == .alertFirstButtonReturn else { return }
            controller.deleteMeeting(meetingID)
        }
    }
}

enum WorkspaceModalPresentation {
    static func alertLevel(parentLevel: NSWindow.Level?) -> NSWindow.Level {
        guard let parentLevel else { return .floating }
        return NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue, parentLevel.rawValue + 1))
    }
}
