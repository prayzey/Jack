import SwiftUI

/// Top-trailing chrome menu for the current Quick Note. Houses the on-device
/// AI actions (summarize/rewrite/extract) and the Randomize Design shortcut.
/// The AI section only renders when a model is usable and the feature is on,
/// so it never dangles when AI can't run — but the menu itself stays available
/// for Randomize Design regardless, so that action is always reachable.
/// AI results are copied to the clipboard (and so land in clipboard history)
/// rather than overwriting the note, so note text is never destroyed.
struct QuickNoteAIMenu: View {
    @EnvironmentObject private var store: ClipboardStore
    let note: NoteItem?
    let tint: Color

    private var isBusy: Bool {
        guard let note else { return false }
        return store.aiBusyNoteIDs.contains(note.noteID)
    }

    var body: some View {
        if let note {
            Menu {
                if store.aiNoteActionsAvailable {
                    ForEach(AITextAction.allCases) { action in
                        Button {
                            store.runAINoteTextAction(action, noteID: note.noteID)
                        } label: {
                            Label(action.label, systemImage: action.icon)
                        }
                    }

                    Button {
                        store.aiExtractNoteActionItems(note.noteID)
                    } label: {
                        Label(L10n.string("ai.action.actionItems", default: "Extract Action Items"), systemImage: "checklist")
                    }

                    Divider()
                }

                Button {
                    // Animate so the card re-themes with a soft cross-fade
                    // instead of a hard cut between looks.
                    withAnimation(.easeInOut(duration: 0.28)) {
                        store.randomizeQuickNoteStyle()
                    }
                } label: {
                    Label(
                        L10n.string("quickNote.randomizeDesign", default: "Randomize Design"),
                        systemImage: "wand.and.stars"
                    )
                }
            } label: {
                Group {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.78))
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(tint)
            .foregroundStyle(tint)
            .fixedSize()
            .disabled(isBusy)
            .help(L10n.string("ai.note.help", default: "AI actions and design shuffle for this note"))
        }
    }
}
