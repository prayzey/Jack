import SwiftUI

struct DictationHistoryView: View {
    @EnvironmentObject private var store: DictationStore
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggleRow(
                title: L10n.string("dictation.history.save", default: "Save recent dictations"),
                subtitle: L10n.string("dictation.history.privacy", default: "Keep the last 100 dictations on this Mac. Turning this off stops new saves. Audio is never saved."),
                icon: "clock.arrow.circlepath",
                isOn: $store.settings.saveDictationHistory
            )
            HStack {
                Text(L10n.string("dictation.history.title", default: "Recent dictations"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if !store.history.isEmpty {
                    Button(L10n.string("dictation.history.clear", default: "Clear all"), role: .destructive) {
                        store.clearHistory()
                    }
                    .buttonStyle(.borderless)
                }
            }
            if store.history.isEmpty {
                ContentUnavailableView(
                    L10n.string("dictation.history.empty", default: "No recent dictations"),
                    systemImage: "text.bubble",
                    description: Text(L10n.string("dictation.history.emptyHint", default: "Your finished dictations appear here when saving is on. You can copy the original words or the finished text."))
                )
            } else {
                ForEach(store.history) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsTheme.textSecondary)
                            Spacer()
                            Button {
                                DictationPasteService().copyOnly(entry.text)
                                copiedID = entry.id
                            } label: {
                                Label(
                                    copiedID == entry.id
                                        ? L10n.string("dictation.history.copied", default: "Copied")
                                        : L10n.string("dictation.history.copy", default: "Copy text"),
                                    systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.borderless)
                            Button(role: .destructive) { store.deleteHistoryEntry(entry.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.string("dictation.history.delete", default: "Delete dictation"))
                        }
                        Text(entry.text)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if entry.rawTranscript != entry.text {
                            DisclosureGroup(L10n.string("dictation.history.original", default: "Original transcript")) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.rawTranscript)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button(L10n.string("dictation.history.copyOriginal", default: "Copy original")) {
                                        DictationPasteService().copyOnly(entry.rawTranscript)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                            }
                            .font(.system(size: 12))
                        }
                        Divider().padding(.top, 6)
                    }
                }
            }
        }
        .foregroundStyle(SettingsTheme.textPrimary)
        .tint(SettingsTheme.primaryAccent)
        .onChange(of: copiedID) { _, id in
            guard let id else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                if copiedID == id { copiedID = nil }
            }
        }
    }
}
