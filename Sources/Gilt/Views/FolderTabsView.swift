import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderTabsView: View {
    static let acceptedDropTypes: [UTType] = [
        ClipDragItemProvider.internalDragType,
        .plainText
    ]
    static let directClipDropTypes: [UTType] = [
        ClipDragItemProvider.internalDragType
    ]

    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.openWindow) private var openWindow
    @State private var editingFolderID: UUID?
    @State private var editingName = ""
    @State private var dropTargetFolderID: UUID?
    @State private var reorderDrag: FolderReorderDrag?
    @State private var folderFrames: [UUID: CGRect] = [:]
    @State private var lastFolderTapTime: Date?
    @State private var lastFolderTapID: UUID?
    @State private var successFolderID: UUID?
    @State private var dropSuckState: DropSuckState?
    @State private var dropSuckCollapsed = false
    @State private var isClipDragActive = false
    @State private var clipDragEndTime: Date?
    @FocusState private var focusedFolderID: UUID?

    private static let pillSpacing: CGFloat = 6

    /// Press-and-drag reorder state. Frames are the layout snapshot from the
    /// moment the drag began; see `liveReorderIndex` for why they must not be
    /// refreshed mid-drag.
    private struct FolderReorderDrag {
        let draggedID: UUID
        let frames: [UUID: CGRect]
        let ids: [UUID]
        var translationX: CGFloat = 0
        var targetIndex: Int
    }

    private var draggedFolderID: UUID? { reorderDrag?.draggedID }

    private func clipboardFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        store.settings.clipboardUIFont(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.pillSpacing) {
                    ForEach(store.visibleFolders, id: \.folderID) { folder in
                        folderTabCell(folder)
                    }

                    Button {
                        quickAddFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .help("New Folder")
                    .zIndex(2)
                }
                .padding(.vertical, 4)
            }
            .coordinateSpace(name: "FolderTabsScroll")
            .onDrop(of: Self.acceptedDropTypes, delegate: makeFolderTabsDropDelegate())
            .onPreferenceChange(FolderTabFramePreferenceKey.self) { frames in
                // Always cache folder frames so dropEntered/performDrop can locate
                // the correct folder under the cursor — even before the
                // clipDragDidStart notification has propagated through Combine.
                folderFrames = frames
            }
            .onChange(of: draggedFolderID) { _, newValue in
                AppWindowManager.shared.setInternalDragActive(newValue != nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipDragDidStart)) { _ in
                guard draggedFolderID == nil else { return }
                isClipDragActive = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipDragDidEnd)) { _ in
                isClipDragActive = false
                clipDragEndTime = Date()
                dropTargetFolderID = nil
                // Keep `folderFrames` populated — clearing them races with an
                // in-flight performDrop that needs them to resolve the target.
            }
            .onChange(of: store.visibleFolders.map(\.folderID)) { _, _ in
                guard let last = store.visibleFolders.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.folderID, anchor: .trailing)
                }
            }
            .onDisappear {
                AppWindowManager.shared.setInternalDragActive(false)
                dropSuckState = nil
                dropSuckCollapsed = false
                isClipDragActive = false
                reorderDrag = nil
                // folderFrames is intentionally retained — the next appearance
                // re-measures via the GeometryReader background, and keeping
                // the cache lets a tail-end drop still resolve its target.
            }
        }
    }

    private struct FolderTabFramePreferenceKey: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]

        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    private struct DropSuckState: Equatable {
        let id = UUID()
        let folderID: UUID
        let clipType: ClipType
        let summary: String
    }

    @ViewBuilder
    private func folderTabCell(_ folder: ClipFolderModel) -> some View {
        let clipIsHovering = dropTargetFolderID == folder.folderID && draggedFolderID == nil
        let justDropped = successFolderID == folder.folderID
        let pillAccent = resolvedAccentColor(for: folder)
        let isDraggingThis = draggedFolderID == folder.folderID
        let reorderOffset = reorderOffset(for: folder.folderID)

        folderPill(folder)
            .id(folder.folderID)
            .scaleEffect(isDraggingThis ? 1.06 : scaleForFolderPill(justDropped: justDropped, clipIsHovering: clipIsHovering))
            .shadow(color: .black.opacity(isDraggingThis ? 0.45 : 0), radius: isDraggingThis ? 10 : 0, y: isDraggingThis ? 4 : 0)
            .offset(x: reorderOffset)
            .zIndex(isDraggingThis ? 10 : 0)
            .overlay(
                Capsule()
                    .stroke(pillAccent.opacity(clipIsHovering ? 0.92 : 0), lineWidth: 2.2)
                    .allowsHitTesting(false)
            )
            .overlay(
                Capsule()
                    .fill(successFillColor(justDropped: justDropped, clipIsHovering: clipIsHovering))
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .center) {
                if let state = dropSuckState, state.folderID == folder.folderID {
                    FolderDropSuckGhostView(
                        clipType: state.clipType,
                        summary: state.summary
                    )
                    .offset(y: dropSuckCollapsed ? 4 : -50)
                    .scaleEffect(dropSuckCollapsed ? 0.08 : 1)
                    .opacity(dropSuckCollapsed ? 0.02 : 0.96)
                    .blur(radius: dropSuckCollapsed ? 2.2 : 0)
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: clipIsHovering ? pillAccent.opacity(0.55) : .clear, radius: clipIsHovering ? 12 : 0)
            .shadow(color: clipIsHovering ? pillAccent.opacity(0.3) : .clear, radius: clipIsHovering ? 4 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: clipIsHovering)
            .animation(.easeOut(duration: 0.2), value: justDropped)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isDraggingThis)
            // The dragged pill tracks the pointer 1:1; only neighbours animate
            // into the gap.
            .animation(isDraggingThis ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: reorderOffset)
            .gesture(folderReorderGesture(for: folder))
            .onDrop(
                of: Self.directClipDropTypes,
                delegate: makeFolderClipDropDelegate(targetFolderID: folder.folderID)
            )
            .background {
                // Always measure folder frames — drop targeting and reorder
                // calculations depend on these frames being available the
                // instant a drag enters the tabs, without waiting for the
                // clipDragDidStart notification to round-trip through Combine.
                GeometryReader { geo in
                    Color.clear.preference(
                        key: FolderTabFramePreferenceKey.self,
                        value: [folder.folderID: geo.frame(in: .named("FolderTabsScroll"))]
                    )
                }
            }
            .contextMenu {
                folderContextMenu(for: folder)
            }
    }

    private func makeFolderTabsDropDelegate() -> FolderTabsDropDelegate {
        FolderTabsDropDelegate(
            isActive: { isClipDragActive },
            hasSupportedPayload: { info in
                !info.itemProviders(for: Self.acceptedDropTypes).isEmpty
            },
            updateHover: updateFolderDropHover,
            performDropAction: finalizeFolderDrop,
            clearHover: clearFolderDropHover
        )
    }

    private func makeFolderClipDropDelegate(targetFolderID: UUID) -> FolderClipDropDelegate {
        FolderClipDropDelegate(
            targetFolderID: targetFolderID,
            acceptedTypes: Self.directClipDropTypes,
            updateHover: updateDirectClipDropHover,
            performDropAction: finalizeDirectClipDrop,
            clearHover: clearFolderDropHover
        )
    }

    private func updateDirectClipDropHover(targetFolderID: UUID) {
        guard draggedFolderID == nil else { return }
        dropTargetFolderID = targetFolderID
        isClipDragActive = true
    }

    private func updateFolderDropHover(_ location: CGPoint) {
        guard draggedFolderID == nil else { return }
        guard let targetFolderID = nearestHorizontalTargetID(
            ids: store.visibleFolders.map(\.folderID),
            frames: folderFrames,
            locationX: location.x
        ) else {
            clearFolderDropHover()
            return
        }

        dropTargetFolderID = targetFolderID
        isClipDragActive = true
    }

    private func finalizeFolderDrop(_ info: DropInfo) -> Bool {
        guard draggedFolderID == nil else { return false }

        // Resolve the target folder. Prefer a fresh location-based lookup, but
        // fall back to the most recently hovered folder when frames are stale
        // (e.g. clipDragDidEnd already cleared them, or the drag entered the
        // tabs before the GeometryReader got to publish preferences).
        let targetFolderID = nearestHorizontalTargetID(
            ids: store.visibleFolders.map(\.folderID),
            frames: folderFrames,
            locationX: info.location.x
        ) ?? dropTargetFolderID

        guard let targetFolderID else {
            clearFolderDropHover()
            return false
        }

        guard let provider = info.itemProviders(for: Self.acceptedDropTypes).first else {
            clearFolderDropHover()
            return false
        }

        // Prefer the typed internal drag — that's what real clip cards emit.
        let internalIdentifier = ClipDragItemProvider.internalDragType.identifier
        if provider.hasItemConformingToTypeIdentifier(internalIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: internalIdentifier) { data, _ in
                guard let data,
                      let value = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    handleFolderDropPayload(value, targetFolderID: targetFolderID)
                }
            }
            return true
        }

        // Fallback to plain-text payloads — covers legacy clip drags and any
        // SwiftUI plumbing that hands us a string-only provider.
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String else { return }
            DispatchQueue.main.async {
                handleFolderDropPayload(string, targetFolderID: targetFolderID)
            }
        }
        return true
    }

    private func finalizeDirectClipDrop(_ info: DropInfo, targetFolderID: UUID) -> Bool {
        guard let provider = info.itemProviders(for: Self.directClipDropTypes).first else {
            clearFolderDropHover()
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: ClipDragItemProvider.internalDragType.identifier) { data, _ in
            guard let data,
                  let value = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                handleFolderDropPayload(value, targetFolderID: targetFolderID)
            }
        }
        return true
    }

    private func handleFolderDropPayload(_ payload: String, targetFolderID: UUID) {
        guard let clipID = folderDropClipID(from: payload) else {
            clearFolderDropHover()
            return
        }

        beginDropSuckAnimation(clipID: clipID, into: targetFolderID)
        ClipDragLifecycle.end()
        isClipDragActive = false
        successFolderID = targetFolderID
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        store.addClip(clipID, to: targetFolderID)
        clearFolderDropHover()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if successFolderID == targetFolderID {
                successFolderID = nil
            }
        }
    }

    private func clearFolderDropHover() {
        dropTargetFolderID = nil
    }

    // MARK: - Press-and-drag reorder

    private func folderReorderGesture(for folder: ClipFolderModel) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("FolderTabsScroll"))
            .onChanged { value in
                guard editingFolderID == nil, !isClipDragActive else { return }
                if reorderDrag == nil {
                    let ids = store.visibleFolders.map(\.folderID)
                    guard let index = ids.firstIndex(of: folder.folderID),
                          folderFrames[folder.folderID] != nil else { return }
                    reorderDrag = FolderReorderDrag(
                        draggedID: folder.folderID,
                        frames: folderFrames,
                        ids: ids,
                        targetIndex: index
                    )
                }
                guard var drag = reorderDrag, drag.draggedID == folder.folderID else { return }
                drag.translationX = value.translation.width
                let newIndex = liveReorderIndex(
                    ids: drag.ids,
                    frames: drag.frames,
                    draggedID: drag.draggedID,
                    translationX: drag.translationX
                ) ?? drag.targetIndex
                if newIndex != drag.targetIndex {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                drag.targetIndex = newIndex
                reorderDrag = drag
            }
            .onEnded { _ in
                guard let drag = reorderDrag, drag.draggedID == folder.folderID else { return }
                let commit = liveReorderCommit(ids: drag.ids, draggedID: drag.draggedID, targetIndex: drag.targetIndex)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    if let commit {
                        store.moveFolder(drag.draggedID, relativeTo: commit.targetID, placement: commit.placement)
                    }
                    reorderDrag = nil
                }
            }
    }

    private func reorderOffset(for folderID: UUID) -> CGFloat {
        guard let drag = reorderDrag else { return 0 }
        if folderID == drag.draggedID { return drag.translationX }
        return liveReorderShifts(
            ids: drag.ids,
            frames: drag.frames,
            draggedID: drag.draggedID,
            targetIndex: drag.targetIndex,
            spacing: Self.pillSpacing
        )[folderID] ?? 0
    }

    @ViewBuilder
    private func folderPill(_ folder: ClipFolderModel) -> some View {
        let selected = folder.folderID == store.selectedFolderID
        let isEditing = editingFolderID == folder.folderID

        if isEditing {
            HStack(spacing: 7) {
                Circle()
                    .fill(resolvedAccentColor(for: folder))
                    .frame(width: 12, height: 12)
                TextField("Folder", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(clipboardFont(size: 12, weight: .medium))
                    .frame(minWidth: 64, idealWidth: 92, maxWidth: 130)
                    .focused($focusedFolderID, equals: folder.folderID)
                    .submitLabel(.done)
                    .onSubmit {
                        commitRename(folderID: folder.folderID)
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.white)
            .background(Capsule().fill(Color.white.opacity(0.30)))
            .onChange(of: focusedFolderID) { _, newValue in
                if newValue != folder.folderID, editingFolderID == folder.folderID {
                    DispatchQueue.main.async {
                        commitRename(folderID: folder.folderID)
                    }
                }
            }
        } else {
            let mode = folder.colorMode
            let showsDot = mode == .dot || mode == .dotAndText
            let showsText = mode == .text || mode == .dotAndText || mode == .fill
            let fillStyle = resolvedFillStyle(for: folder, selected: selected)
            let accentColor = resolvedAccentColor(for: folder)
            let textColor = resolvedTextColor(for: folder, selected: selected)

            HStack(spacing: (showsDot || folder.effectiveFolderIcon != nil) && showsText ? 7 : 0) {
                if showsDot || folder.effectiveFolderIcon != nil {
                    FolderIconView(
                        folder: folder,
                        accentColor: accentColor,
                        textColor: textColor
                    )
                }

                if showsText {
                    Text(folder.displayName)
                        .font(clipboardFont(size: 12, weight: selected ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(textColor)
                }
            }
            .padding(.horizontal, showsText ? 14 : 11)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(fillStyle)
            )
            .overlay {
                if selected {
                    // Two-tone ring so the selected pill reads on anything: the
                    // dark halo carries it on bright wallpapers, the bright
                    // inner ring on dark ones. A single accent stroke vanished
                    // whenever the pill fill was the same color as the accent.
                    Capsule().stroke(Color.black.opacity(0.45), lineWidth: 4)
                    Capsule().stroke(Color.white.opacity(0.95), lineWidth: 2)
                }
            }
            .contentShape(Capsule())
            .help(folder.displayName)
            .onTapGesture {
                handleFolderTap(folder)
            }
            .animation(.easeOut(duration: 0.15), value: selected)
        }
    }

    private func resolvedFillStyle(for folder: ClipFolderModel, selected: Bool) -> AnyShapeStyle {
        if folder.colorMode == .fill {
            let fillValue = folder.resolvedFillColor
            switch fillValue {
            case .gradient(let spec):
                return AnyShapeStyle(spec.linearGradient.opacity(selected ? 0.92 : 0.72))
            case .solid(let resolved):
                let base = resolved.color
                return AnyShapeStyle(base.opacity(selected ? 0.92 : 0.72))
            }
        }
        return AnyShapeStyle(selected ? Color.white.opacity(0.30) : Color.white.opacity(0.06))
    }

    private func resolvedAccentColor(for folder: ClipFolderModel) -> Color {
        folder.resolvedColor.color
    }

    private func resolvedTextColor(for folder: ClipFolderModel, selected: Bool) -> Color {
        switch folder.textColorMode {
        case .white:
            return .white.opacity(selected ? 1 : 0.95)
        case .accent:
            return folder.resolvedColor.color
        case .custom:
            return (folder.resolvedCustomTextColor ?? folder.resolvedColor).color
        case .auto:
            switch folder.colorMode {
            case .fill:
                return .white.opacity(selected ? 1 : 0.95)
            case .text, .dotAndText:
                return folder.resolvedColor.color
            case .dot:
                return .white.opacity(selected ? 1 : 0.8)
            }
        }
    }

    private func quickAddFolder() {
        store.createFolder()
        // Begin inline rename on the newly created folder after SwiftUI updates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let newFolder = store.visibleFolders.last, !newFolder.isSystem {
                beginRename(newFolder)
            }
        }
    }

    private func beginRename(_ folder: ClipFolderModel) {
        AppWindowManager.shared.focusForInput()
        editingFolderID = folder.folderID
        editingName = folder.displayName
        DispatchQueue.main.async {
            focusedFolderID = folder.folderID
        }
    }

    private func commitRename(folderID: UUID) {
        store.renameFolder(id: folderID, name: editingName)
        cancelRename()
    }

    private func cancelRename() {
        editingFolderID = nil
        editingName = ""
        focusedFolderID = nil
    }

    private func handleFolderTap(_ folder: ClipFolderModel) {
        let now = Date()

        // Ignore taps that land within 350ms of a clip drag ending.
        // When a drag session ends, the mouse-up can propagate as a tap to
        // folder tabs, unintentionally switching the selected folder.
        if let dragEnd = clipDragEndTime, now.timeIntervalSince(dragEnd) < 0.35 {
            return
        }

        let isDoubleTap = lastFolderTapID == folder.folderID
            && lastFolderTapTime.map({ now.timeIntervalSince($0) < 0.28 }) ?? false

        if isDoubleTap {
            lastFolderTapTime = nil
            lastFolderTapID = nil
            beginRename(folder)
            return
        }

        lastFolderTapID = folder.folderID
        lastFolderTapTime = now
        store.selectedFolderID = folder.folderID
    }

    private func openFoldersSettings() {
        SettingsNavigation.requestTab(rawValue: SettingsNavigation.foldersTabRawValue)
        NSApp.activate(ignoringOtherApps: true)
        AppWindowManager.shared.prepareForSettingsPresentation(source: "tray-folder-tabs")
        openWindow(id: SettingsNavigation.windowID)
    }

    private func beginDropSuckAnimation(clipID: UUID, into folderID: UUID) {
        guard let clip = store.clips.first(where: { $0.clipID == clipID }) else { return }
        let state = DropSuckState(
            folderID: folderID,
            clipType: clip.clipType,
            summary: clipSummary(for: clip)
        )
        dropSuckState = state
        dropSuckCollapsed = false

        DispatchQueue.main.async {
            guard dropSuckState?.id == state.id else { return }
            withAnimation(.timingCurve(0.18, 0.82, 0.2, 1, duration: 0.28)) {
                dropSuckCollapsed = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard dropSuckState?.id == state.id else { return }
            dropSuckState = nil
            dropSuckCollapsed = false
        }
    }

    private func clipSummary(for clip: ClipItemModel) -> String {
        let raw = (clip.textValue ?? clip.urlValue ?? clip.previewText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else {
            return clip.clipType.rawValue.capitalized
        }
        return String(raw.prefix(18))
    }

    @ViewBuilder
    private func folderContextMenu(for folder: ClipFolderModel) -> some View {
        if !folder.isSmartFolder {
            Button(L10n.string("ui.rename.folder", default: "Rename Folder")) {
                beginRename(folder)
            }
        }

        Menu(L10n.string("ui.folder.style", default: "Folder Style")) {
            ForEach(FolderColorMode.allCases, id: \.self) { mode in
                Button {
                    store.setFolderColorMode(id: folder.folderID, mode: mode)
                } label: {
                    HStack {
                        Text(mode.label)
                        if folder.colorMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu(L10n.string("ui.accent.color", default: "Accent Color")) {
            ForEach(FolderColorToken.allCases, id: \.self) { token in
                Button {
                    store.setFolderAccentColor(id: folder.folderID, color: token)
                } label: {
                    HStack {
                        Circle()
                            .fill(token.color)
                            .frame(width: 10, height: 10)
                        Text(token.label)
                        if folder.color == token {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button(CommonCopy.customColor()) {
                openFoldersSettings()
            }
        }

        Button(L10n.string("ui.customize.icon", default: "Customize Icon...")) {
            openFoldersSettings()
        }

        Menu(L10n.string("ui.fill.color", default: "Fill Color")) {
            ForEach(FolderColorToken.allCases, id: \.self) { token in
                Button {
                    store.setFolderFillColor(id: folder.folderID, color: token)
                } label: {
                    HStack {
                        Circle()
                            .fill(token.color)
                            .frame(width: 10, height: 10)
                        Text(token.label)
                        if folder.fillColor == token {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button(CommonCopy.customColor()) {
                openFoldersSettings()
            }
        }
        .disabled(folder.colorMode != .fill)

        Menu(L10n.string("ui.text.color", default: "Text Color")) {
            ForEach([FolderTextColorMode.auto, .white, .accent], id: \.self) { mode in
                Button {
                    store.setFolderTextColorMode(id: folder.folderID, mode: mode)
                } label: {
                    HStack {
                        Text(mode.label)
                        if folder.textColorMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Menu(L10n.string("ui.custom.text.color", default: "Custom Text Color")) {
                ForEach(FolderColorToken.allCases, id: \.self) { token in
                    Button {
                        store.setFolderCustomTextColor(id: folder.folderID, color: token)
                    } label: {
                        HStack {
                            Circle()
                                .fill(token.color)
                                .frame(width: 10, height: 10)
                            Text(token.label)
                            if folder.textColorMode == .custom && folder.customTextColor == token {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button(CommonCopy.customColor()) {
                    openFoldersSettings()
                }
            }
        }

        Divider()
        autoCategorizationLockMenuItem(for: folder)

        Button(CommonCopy.moveLeft()) {
            store.moveFolderLeft(id: folder.folderID)
        }
        .disabled(store.visibleFolders.first?.folderID == folder.folderID)

        Button(CommonCopy.moveRight()) {
            store.moveFolderRight(id: folder.folderID)
        }
        .disabled(store.visibleFolders.last?.folderID == folder.folderID)

        if folder.isSmartFolder, let category = folder.smartCategory {
            Divider()
            Button(L10n.string("ui.hide.from.tab.bar", default: "Hide from Tab Bar"), role: .destructive) {
                store.hideSmartCategory(category)
            }
        } else if store.canHideFolderFromTabs(folder) {
            Divider()
            Button(L10n.string("ui.hide.from.tab.bar", default: "Hide from Tab Bar")) {
                store.hideFolderFromTabs(id: folder.folderID)
            }
            if store.isSkillFolder(folder) {
                Button(L10n.string("ui.hide.all.skills", default: "Hide All Skills")) {
                    store.hideAllSkillFolders()
                }
            }
        }

        if folder.clips.count > 0 {
            Divider()
            Button(L10n.string("ui.clear.all.items", default: "Clear All Items"), role: .destructive) {
                FolderClearRequest.shared.request(
                    folder: folder,
                    accentColor: resolvedAccentColor(for: folder)
                )
            }
        }

        if folder.isSystem == false && !folder.isSmartFolder {
            Divider()
            Button(CommonCopy.deleteFolder(), role: .destructive) {
                FolderDeleteRequest.shared.request(
                    folder: folder,
                    accentColor: resolvedAccentColor(for: folder)
                )
            }
        }
    }

    @ViewBuilder
    private func autoCategorizationLockMenuItem(for folder: ClipFolderModel) -> some View {
        let lockLabel = folder.isAutoCategorizationLocked ? "Unlock Auto-Categorization" : "Lock Auto-Categorization"
        Button(lockLabel) {
            store.setAutoCategorizationLock(
                for: folder.folderID,
                locked: !folder.isAutoCategorizationLocked
            )
        }
    }

    private func scaleForFolderPill(justDropped: Bool, clipIsHovering: Bool) -> CGFloat {
        if justDropped { return 1.1 }
        if clipIsHovering { return 1.14 }
        return 1
    }

    private func successFillColor(justDropped: Bool, clipIsHovering: Bool) -> Color {
        if justDropped { return .white.opacity(0.28) }
        if clipIsHovering { return .white.opacity(0.14) }
        return .clear
    }

}

private struct FolderDropSuckGhostView: View {
    let clipType: ClipType
    let summary: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(headerGradient)
                .frame(height: 12)
                .overlay(alignment: .leading) {
                    Image(systemName: clipSymbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.leading, 6)
                }

            ZStack(alignment: .topLeading) {
                Color(nsColor: NSColor(white: 0.12, alpha: 1))
                Text(summary)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
            }
        }
        .frame(width: 88, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 4)
    }

    private var headerGradient: LinearGradient {
        // .color keeps its original gold gradient — the shared default is teal,
        // and this ghost's rendered look must not change.
        let colors = clipType == .color
            ? [Color(red: 0.86, green: 0.70, blue: 0.22), Color(red: 0.95, green: 0.82, blue: 0.34)]
            : ClipTypePresentation.headerGradientColors(for: clipType)
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private var clipSymbol: String {
        ClipTypePresentation.symbol(for: clipType)
    }
}
