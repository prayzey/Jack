import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The workspace sidebar — the **only** navigation surface after the
/// two-column redesign.
///
/// Structure, top to bottom:
/// 1. **Nav strip.** Horizontal 4-up of icon+label tabs (Clipboard, Tasks,
///    Pulse, Meetings). Active tab has a gold pill that slides
///    between positions via `matchedGeometryEffect`.
/// 2. **Search field.** Scopes the contextual content below.
/// 3. **Contextual content.** Folders + items for whatever section is
///    active. Provided by `WorkspaceListColumn` (no longer a column — now
///    just a content view embedded here). Scrolls independently.
///
/// Design rationale:
/// - The earlier three-pane layout had a middle column duplicating what the
///   sidebar already showed. Folding it back into the sidebar gives the
///   detail pane all the horizontal space and removes a redundant surface.
/// - Putting the nav strip *above* the search puts the highest-level
///   navigation first, which matches how Mail, Notion, and Linear order
///   their sidebars.
/// - The view assumes the parent applies `.workspaceScrim(.strong)` so
///   labels stay legible over any wallpaper. No background here.
struct WorkspaceSidebarView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.openWindow) private var openWindow

    /// Shared namespace so the active-section highlight can slide between
    /// nav tabs via `matchedGeometryEffect`.
    @Namespace private var navHighlight

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        VStack(spacing: 14) {
            navStrip
            searchField
            // Section content scrolls independently of the fixed nav + search.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    WorkspaceListColumn()
                        .environmentObject(store)
                }
                .padding(.bottom, 24)
            }
            // Settings pinned to the bottom of the sidebar so it's always
            // reachable regardless of how far the section content scrolls.
            settingsButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// Opens the app-owned Settings window. Uses the same coordination as
    /// `ModeSettingsLink` so Settings stays interactable above the workspace.
    private var settingsButton: some View {
        SidebarRow(title: "Settings", icon: "gearshape", tint: .white.opacity(0.7)) {
            NSApp.activate(ignoringOtherApps: true)
            AppWindowManager.shared.prepareForSettingsPresentation(source: "workspace-sidebar")
            openWindow(id: SettingsNavigation.windowID)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField("Search", text: $store.workspaceSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    /// Horizontal 4-up of nav tabs. The `.animation` modifier picks up the
    /// change in `selectedSidebarSection` and runs the
    /// `matchedGeometryEffect` defined inside `WorkspaceNavTab`, sliding the
    /// gold pill from the old tab to the new one.
    private var navStrip: some View {
        HStack(spacing: 3) {
            ForEach(WorkspaceSidebarSection.allCases) { section in
                WorkspaceNavTab(
                    section: section,
                    isActive: store.workspaceSession.selectedSidebarSection == section,
                    accent: goldAccent,
                    namespace: navHighlight
                ) {
                    store.workspaceSession.selectedSidebarSection = section
                    if section == .tasks { store.openKanbanBoard() }
                    if section == .meetings { store.openMeetingsInWorkspace() }
                }
            }
        }
        // Snappy spring so the pill feels responsive, not floaty.
        .animation(
            .spring(response: 0.32, dampingFraction: 0.82),
            value: store.workspaceSession.selectedSidebarSection
        )
    }
}

// MARK: - Horizontal nav tab

/// A single tab in the workspace sidebar's top nav strip. Icon stacked above
/// a small label; active state uses a gold pill rendered via
/// `matchedGeometryEffect` so the pill physically slides between tabs when
/// the active section changes.
///
/// Hover tint is intentionally separate from the shared pill — if it joined
/// the matched-geometry chain, hovering an inactive tab would yank the pill
/// across to it.
struct WorkspaceNavTab: View {
    let section: WorkspaceSidebarSection
    let isActive: Bool
    let accent: Color
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(height: 16)
                Text(section.label)
                    .font(.system(size: 9.5, weight: isActive ? .bold : .medium))
                    .foregroundStyle(labelTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .tracking(0.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                ZStack {
                    if hover && !isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(accent.opacity(0.38), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "workspaceNavHighlight", in: namespace)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(section.label)
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var iconTint: Color {
        if isActive { return accent }
        return .white.opacity(hover ? 0.92 : 0.62)
    }
    private var labelTint: Color {
        if isActive { return accent.opacity(0.95) }
        return .white.opacity(hover ? 0.86 : 0.55)
    }
}

// MARK: - Generic SidebarRow (no drag/drop)

/// Generic row used by tasks and other non-draggable list items. Made
/// `internal` so the workspace list column can use the same row style.
struct SidebarRow: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(hover ? 1.0 : 0.75))
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: 12.5, weight: hover ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(hover ? 1.0 : 0.78))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Clip folder row (draggable + drop target)

/// Sidebar row for a clipboard folder. Drags as `folder:<uuid>` and accepts
/// clip drags via the canonical `ClipDragItemProvider.internalDragType`. Also
/// accepts a plain UUID string fallback for compatibility with any older
/// drag sources still emitting plain text.
struct ClipFolderSidebarRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let folder: ClipFolderModel
    @State private var hover = false
    @State private var dropTargeted = false

    private var iconName: String {
        folder.effectiveFolderIcon?.rawValue.replacingOccurrences(of: "sf:", with: "") ?? "folder"
    }
    private var tint: Color { .teal.opacity(0.75) }

    var body: some View {
        Button {
            store.selectedFolderID = folder.folderID
            store.openWorkspaceFolderTab(folder.folderID, isNoteFolder: false)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(hover ? 1.0 : 0.75))
                    .frame(width: 16)
                Text(folder.name)
                    .lineLimit(1)
                    .font(.system(size: 12.5, weight: hover ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(hover ? 1.0 : 0.78))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(dropTargeted ? tint.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(dropTargeted ? tint.opacity(0.65) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onDrag {
            let provider = NSItemProvider(object: "folder:\(folder.folderID.uuidString)" as NSString)
            provider.suggestedName = folder.name
            return provider
        }
        .onDrop(
            of: [
                ClipDragItemProvider.internalDragType.identifier,
                UTType.plainText.identifier
            ],
            isTargeted: $dropTargeted
        ) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Prefer the typed internal drag — this is what real clip cards emit.
        if provider.hasItemConformingToTypeIdentifier(ClipDragItemProvider.internalDragType.identifier) {
            provider.loadDataRepresentation(
                forTypeIdentifier: ClipDragItemProvider.internalDragType.identifier
            ) { data, _ in
                guard let data,
                      let raw = String(data: data, encoding: .utf8),
                      let dragItem = StripDragItem(serializedValue: raw),
                      case .clip(let clipID) = dragItem else { return }
                DispatchQueue.main.async {
                    store.addClip(clipID, to: folder.folderID)
                }
            }
            return true
        }

        // Fallback to plain text payloads (legacy clip drags + sidebar clip rows).
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String else { return }

            // Reject prefixed payloads we don't handle (notes, sub-folders).
            if string.hasPrefix("note:") || string.hasPrefix("noteFolder:") || string.hasPrefix("folder:") {
                return
            }

            // A bare UUID string is treated as a clip ID — matches the legacy
            // drag format from earlier card views.
            guard let clipID = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                store.addClip(clipID, to: folder.folderID)
            }
        }
        return true
    }
}

// MARK: - Clip row (draggable using the canonical provider)

/// Sidebar row for a clipboard item. Uses the same `ClipDragItemProvider` that
/// the tray cards do, so dragging into Finder, Mail, etc. behaves identically
/// to a real card drag.
struct ClipSidebarRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let clip: ClipItemModel
    @State private var hover = false

    private var iconName: String {
        store.isMirroredNoteClip(clip) ? "note.text.badge.plus" : "doc.on.doc"
    }
    private var tint: Color { .orange.opacity(0.7) }

    var body: some View {
        Button {
            store.openClipInWorkspace(clip.clipID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint.opacity(hover ? 1.0 : 0.75))
                    .frame(width: 16)
                Text(clip.title)
                    .lineLimit(1)
                    .font(.system(size: 12.5, weight: hover ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(hover ? 1.0 : 0.78))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onDrag {
            ClipDragItemProvider.makeProvider(for: clip)
        }
    }
}

