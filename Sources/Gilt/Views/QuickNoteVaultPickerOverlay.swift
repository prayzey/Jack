import SwiftUI

/// Compact chrome pill showing where the current note saves inside the vault,
/// and opening the destination picker on tap. Like the browse button, it stays
/// solid at every scroll offset: retargeting a note should always be reachable.
struct QuickNoteVaultDestinationButton: View {
    let destination: String?
    let hasVault: Bool
    let tint: Color
    /// Compact form for narrow windows: icon only, no label. The help text and
    /// accessibility label keep carrying the full state.
    var iconOnly: Bool = false
    let action: () -> Void

    private var isSynced: Bool { hasVault && (destination?.isEmpty == false) }

    private var label: String {
        guard hasVault else {
            return L10n.string("quickNote.vault.localOnly", default: "Local only")
        }
        guard isSynced, let destination else {
            return L10n.string("quickNote.vault.notSynced", default: "Not synced")
        }
        return destination.components(separatedBy: "/").last ?? destination
    }

    /// Character-capped label so a long vault folder name can't balloon the
    /// pill and shove the rest of the chrome row leftward into the nav arrows.
    /// The help text still carries the full path.
    private var displayLabel: String {
        label.count > 18 ? label.prefix(17) + "…" : label
    }

    private var helpText: String {
        guard hasVault else {
            return L10n.string(
                "quickNote.vault.chooseVaultHelp",
                default: "This note is saved locally. Tap to choose a vault folder."
            )
        }
        guard isSynced, let destination else {
            return L10n.string(
                "quickNote.vault.notSyncedHelp",
                default: "Not synced. Tap to pick a vault folder."
            )
        }
        let template = L10n.string(
            "quickNote.vault.syncedHelp",
            default: "Saves to %@ in your vault"
        )
        return String(format: template, destination)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isSynced ? "folder" : "icloud.slash")
                    .font(.system(size: 11, weight: .semibold))
                if !iconOnly {
                    Text(displayLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.10)))
            .overlay(Capsule(style: .continuous).stroke(tint.opacity(0.16), lineWidth: 0.8))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(Text(helpText))
    }
}

/// Full-window overlay to choose which vault subfolder the current note saves
/// into, with fuzzy search. Rendered inside `QuickNoteView`'s ZStack (a
/// standalone window), mirroring `QuickNoteBrowserOverlay` so it sidesteps the
/// tray's sheet/window pitfalls. Search reuses `CommandPaletteMatcher`.
///
/// Phase 0 is non-destructive: selecting a folder only records the choice on the
/// note. The "Use ..." option for a typed-but-missing folder also just records
/// the path; the folder is created lazily when Phase 1 first writes the file.
struct QuickNoteVaultPickerOverlay: View {
    @Binding var isPresented: Bool
    let style: QuickNoteStyle
    let hasVault: Bool
    let vaultDisplayPath: String?
    let currentSelection: String?
    let loadFolders: () async -> [String]
    let onSelect: (String?) -> Void
    let onChooseVault: () -> Void

    @State private var searchText = ""
    @State private var folders: [String] = []
    @State private var isLoading = true
    @FocusState private var searchFocused: Bool

    private var isLight: Bool { style.isLightSurface }
    private var accent: Color { style.insertionColor }
    private var primaryText: Color { isLight ? .black.opacity(0.85) : .white.opacity(0.92) }
    private var secondaryText: Color { isLight ? .black.opacity(0.5) : .white.opacity(0.55) }
    private var panelFill: Color { isLight ? Color(white: 0.98) : Color(white: 0.11) }
    private var fieldFill: Color { isLight ? .black.opacity(0.05) : .white.opacity(0.07) }
    private var hairline: Color { isLight ? .black.opacity(0.10) : .white.opacity(0.10) }

    private var trimmedQuery: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var filtered: [String] {
        CommandPaletteMatcher.filter(folders, query: searchText, limit: 200) { [$0] }
    }

    /// Offer "Use <query>" only when the typed path doesn't already exist.
    private var showCreateOption: Bool {
        !trimmedQuery.isEmpty
            && !folders.contains { $0.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            GeometryReader { geo in
                panel
                    .frame(width: min(geo.size.width - 40, 460), height: min(geo.size.height - 40, 540))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onKeyPress(.escape) { isPresented = false; return .handled }
        // Keyed on the vault path too, so picking a different vault via the
        // in-header Change button reloads the folder list in place.
        .task(id: "\(hasVault)|\(vaultDisplayPath ?? "")") {
            guard hasVault else { isLoading = false; return }
            isLoading = true
            folders = await loadFolders()
            isLoading = false
            searchFocused = true
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 0) {
            if hasVault {
                header
                Divider().overlay(hairline)
                content
            } else {
                noVaultState
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(panelFill))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(hairline, lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText)
                TextField(
                    "",
                    text: $searchText,
                    // Explicit prompt ink: the default placeholder color follows
                    // the app's dark appearance, which turns invisible on light
                    // note styles like Paper. secondaryText flips with isLight.
                    prompt: Text(L10n.string("quickNote.vault.searchFolders", default: "Search folders"))
                        .foregroundStyle(secondaryText)
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(primaryText)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = filtered.first { select(first) }
                        else if showCreateOption { select(trimmedQuery) }
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(fieldFill))

            if let vaultDisplayPath {
                HStack(spacing: 5) {
                    Image(systemName: "books.vertical").font(.system(size: 10))
                    Text(abbreviatedPath(vaultDisplayPath))
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: onChooseVault) {
                        Text(L10n.string("quickNote.vault.changeVault", default: "Change…"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string(
                        "quickNote.vault.changeVaultHelp",
                        default: "Choose a different folder to save notes into"
                    ))
                }
                .foregroundStyle(secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                row(title: "Not synced (local only)", systemImage: "icloud.slash", selected: currentSelection == nil) {
                    select(nil)
                }
                if isLoading {
                    ProgressView().controlSize(.small).padding(.vertical, 16)
                } else {
                    ForEach(filtered, id: \.self) { folder in
                        row(title: folder, systemImage: "folder", selected: currentSelection == folder) {
                            select(folder)
                        }
                    }
                    if showCreateOption {
                        row(title: "Use \"\(trimmedQuery)\"", systemImage: "plus", selected: false, accentRow: true) {
                            select(trimmedQuery)
                        }
                    } else if filtered.isEmpty {
                        Text(L10n.string("ui.no.folders.in.this.vault.yet.type.a..80aaa4", default: "No folders in this vault yet. Type a name to create one."))
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.visible)
    }

    private var noVaultState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(secondaryText)
            Text(L10n.string("ui.no.vault.chosen", default: "No vault chosen"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primaryText)
            Text(L10n.string("ui.pick.a.folder.like.your.obsidian.vau.ae8e13", default: "Pick a folder (like your Obsidian vault) to save notes into."))
                .font(.system(size: 12))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
            Button(action: onChooseVault) {
                Text(L10n.string("ui.choose.vault.folder", default: "Choose Vault Folder…"))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accent.opacity(0.16)))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func row(
        title: String,
        systemImage: String,
        selected: Bool,
        accentRow: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentRow ? accent : secondaryText)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(accentRow ? accent : primaryText)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? accent.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func select(_ folder: String?) {
        onSelect(folder)
        isPresented = false
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
