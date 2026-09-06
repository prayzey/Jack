import SwiftUI

/// Settings editor for user-defined Kanban writing actions (custom system prompts).
struct KanbanCustomAssistPresetsSettingsView: View {
    @EnvironmentObject private var store: ClipboardStore

    @State private var isComposing = false
    @State private var editingID: UUID?
    @State private var draftTitle = ""
    @State private var draftInstruction = ""

    private var presets: [KanbanCustomAssistPreset] {
        store.settings.kanbanCustomAssistPresets
    }

    private var canAddMore: Bool {
        presets.count < KanbanAssistCatalog.maxCustomPresets
    }

    var body: some View {
        VStack(spacing: 0) {
            if presets.isEmpty, !isComposing {
                Text(
                    L10n.string(
                        "settings.kanban.assist.empty",
                        default: "No custom actions yet. Built-in Fix spelling, Polish, Clarify, and Shorten always appear on Kanban cards."
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            } else {
                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 { SettingsDivider() }
                    presetRow(preset)
                }
            }

            if isComposing {
                if !presets.isEmpty { SettingsDivider() }
                composeForm
            }

            SettingsDivider()

            Button(action: beginCompose) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.gold)
                    Text(
                        L10n.string(
                            "settings.kanban.assist.add",
                            default: "Add custom action"
                        )
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAddMore || isComposing)
            .opacity(canAddMore ? 1 : 0.45)
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: KanbanCustomAssistPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Text(preset.instruction)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.textTertiary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    beginEdit(preset)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SettingsTheme.textSecondary)

                Button(role: .destructive) {
                    deletePreset(id: preset.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SettingsTheme.textSecondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                editingID == nil
                    ? L10n.string("settings.kanban.assist.compose.new", default: "New custom action")
                    : L10n.string("settings.kanban.assist.compose.edit", default: "Edit custom action")
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SettingsTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("settings.kanban.assist.field.title", default: "Menu label"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textTertiary)
                TextField(
                    L10n.string("settings.kanban.assist.field.title.placeholder", default: "e.g. Make actionable"),
                    text: $draftTitle
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("settings.kanban.assist.field.instruction", default: "System prompt"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textTertiary)
                Text(
                    L10n.string(
                        "settings.kanban.assist.field.instruction.hint",
                        default: "Tell the model how to rewrite the task title. Be specific about tone, format, and what not to change."
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(SettingsTheme.textTertiary)
                TextEditor(text: $draftInstruction)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88, maxHeight: 140)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(L10n.string("workspace.kanban.cancel", default: "Cancel"), action: cancelCompose)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textSecondary)
                Button(L10n.string("settings.kanban.assist.save", default: "Save"), action: commitCompose)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.gold)
                    .disabled(!canCommitCompose)
                    .opacity(canCommitCompose ? 1 : 0.45)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var canCommitCompose: Bool {
        KanbanCustomAssistPreset(
            title: draftTitle,
            instruction: draftInstruction
        ).sanitized() != nil
    }

    private func beginCompose() {
        editingID = nil
        draftTitle = ""
        draftInstruction = ""
        isComposing = true
    }

    private func beginEdit(_ preset: KanbanCustomAssistPreset) {
        editingID = preset.id
        draftTitle = preset.title
        draftInstruction = preset.instruction
        isComposing = true
    }

    private func cancelCompose() {
        isComposing = false
        editingID = nil
        draftTitle = ""
        draftInstruction = ""
    }

    private func commitCompose() {
        guard let sanitized = KanbanCustomAssistPreset(
            title: draftTitle,
            instruction: draftInstruction
        ).sanitized() else { return }

        var list = presets
        if let editingID, let index = list.firstIndex(where: { $0.id == editingID }) {
            list[index] = KanbanCustomAssistPreset(
                id: editingID,
                title: sanitized.title,
                instruction: sanitized.instruction
            )
        } else if list.count < KanbanAssistCatalog.maxCustomPresets {
            list.append(sanitized)
        }
        store.settings.kanbanCustomAssistPresets = list
        cancelCompose()
    }

    private func deletePreset(id: UUID) {
        store.settings.kanbanCustomAssistPresets = presets.filter { $0.id != id }
        if editingID == id {
            cancelCompose()
        }
    }
}
