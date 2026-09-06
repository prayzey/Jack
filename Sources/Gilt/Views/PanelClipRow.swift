import AppKit
import SwiftUI

/// Vertical clip card used inside `PanelView`.
/// Keeps Jack's two-zone card language (colored header strip + dark body) but arranges
/// it in the Windows 11 clipboard-panel layout: ellipsis menu top-right, pin bottom-right.
struct PanelClipRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let item: ClipItemModel
    let isSelected: Bool

    @State private var lastTapTime: Date?

    /// Fixed decode target for the image preview so the cache key never churns.
    private static let imagePreviewMaxDimension: CGFloat = 160

    private var parsedClipColor: (r: Double, g: Double, b: Double)? {
        guard item.clipType == .color else { return nil }
        let text = item.textValue ?? item.previewText
        return ContentClassifier.parseAnyColor(text)
    }

    private var colorHeaderUsesDarkText: Bool {
        guard let c = parsedClipColor else { return false }
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.55
    }

    private var typeAccent: Color {
        ClipTypePresentation.accentColor(
            for: item.clipType,
            settings: store.settings,
            linkPlatform: item.linkPlatform,
            parsedColor: parsedClipColor
        )
    }

    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: ClipTypePresentation.headerGradientColors(
                for: item.clipType,
                settings: store.settings,
                linkPlatform: item.linkPlatform,
                parsedColor: parsedClipColor,
                colorHeaderUsesDarkText: colorHeaderUsesDarkText
            ),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var headerTextColor: Color {
        ClipTypePresentation.headerLabelColors(
            for: item.clipType,
            settings: store.settings,
            parsedColor: parsedClipColor,
            colorHeaderUsesDarkText: colorHeaderUsesDarkText
        ).primary
    }

    private var displayText: String {
        if item.clipType == .link {
            if let title = item.linkPageTitle, !title.isEmpty {
                return title
            }
            return item.urlValue ?? item.previewText
        }
        return item.previewText
    }

    private var linkHost: String? {
        guard item.clipType == .link,
              let urlString = item.urlValue,
              let url = URL(string: urlString),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func clipboardFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        store.settings.clipboardUIFont(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBand
            contentBand
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? typeAccent.opacity(0.95) : Color.white.opacity(0.06),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .contextMenu { contextMenu }
        .onDrag {
            ClipDragLifecycle.beginWithMouseReleaseRecovery()
            return ClipDragItemProvider.makeProvider(for: item)
        }
        .onAppear { store.fetchLinkMetadataIfNeeded(for: item) }
    }

    // MARK: - Header band (type label + timestamp + ellipsis)

    private var headerBand: some View {
        ZStack {
            headerGradient

            HStack(alignment: .center, spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(headerTextColor.opacity(0.95))
                }

                Text(item.clipType.rawValue.uppercased())
                    .font(clipboardFont(size: 10, weight: .bold))
                    .foregroundStyle(headerTextColor.opacity(0.92))
                    .tracking(0.6)

                Text(timeAgo(item.createdAt))
                    .font(clipboardFont(size: 9))
                    .foregroundStyle(headerTextColor.opacity(0.65))

                if store.isMirroredNoteClip(item) {
                    Text(L10n.string("ui.note", default: "NOTE"))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.25)))
                }

                Spacer(minLength: 4)

                if let icon = store.iconForBundle(item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .opacity(0.8)
                }

                Menu {
                    menuContents
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(headerTextColor.opacity(0.85))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 22)
                .fixedSize()
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 26)
    }

    // MARK: - Content band (preview + pin)

    private var contentBand: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                contentPreview

                if item.clipType == .link, let linkHost {
                    Text(linkHost)
                        .font(clipboardFont(size: 10))
                        .foregroundStyle(typeAccent.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
        .background(contentBackground)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.clipType {
        case .image:
            imagePreview
        case .color:
            colorPreview
        default:
            Text(displayText)
                .font(clipboardFont(size: 13, weight: .regular, forceMonospaced: isCodeLike))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isCodeLike: Bool {
        guard item.clipType == .text else { return false }
        let text = item.previewText
        return text.contains("{") || text.contains("func ") || text.contains("let ")
            || text.contains("import ") || text.contains("=>") || text.contains("//")
    }

    @ViewBuilder
    private var imagePreview: some View {
        // Data-presence branch stays OUTSIDE the shared view so late-arriving
        // data instantiates it fresh and the decode task fires.
        if let data = item.imageData {
            AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: Self.imagePreviewMaxDimension) { nsImage in
                HStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 0)
                }
            } pending: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            } unavailable: {
                imageTextFallback
            }
        } else {
            imageTextFallback
        }
    }

    private var imageTextFallback: some View {
        Text(displayText)
            .font(clipboardFont(size: 12))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(2)
    }

    @ViewBuilder
    private var colorPreview: some View {
        HStack(spacing: 10) {
            if let rgb = parsedClipColor {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
            Text(displayText)
                .font(clipboardFont(size: 13, weight: .medium, forceMonospaced: true))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var contentBackground: some ShapeStyle {
        if item.clipType == .color, let rgb = parsedClipColor {
            return AnyShapeStyle(Color(red: rgb.r, green: rgb.g, blue: rgb.b).opacity(0.12))
        }
        return AnyShapeStyle(Color(NSColor(white: 0.12, alpha: 0.95)))
    }

    // MARK: - Interaction

    private func handleTap() {
        if NSEvent.modifierFlags.contains(.command) {
            store.toggleSelection(item.clipID)
            lastTapTime = nil
            return
        }

        if store.settings.singleClickToPaste {
            lastTapTime = nil
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
            return
        }

        let now = Date()
        let isDoubleTap = lastTapTime.map { now.timeIntervalSince($0) < 0.28 } ?? false
        lastTapTime = now

        if isDoubleTap {
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
        } else {
            let inMultiSelection = store.selectedClipIDs.count > 1
                && store.selectedClipIDs.contains(item.clipID)
            if !inMultiSelection {
                store.selectSingle(item.clipID)
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        menuContents
    }

    @ViewBuilder
    private var menuContents: some View {
        let hasSelection = !store.selectedClipIDs.isEmpty
        let targetIDs = hasSelection ? store.selectedClipIDs : [item.clipID]
        let targetItems = store.clips.filter { targetIDs.contains($0.clipID) }
        let allPinned = !targetItems.isEmpty && targetItems.allSatisfy(\.isPinned)
        let browserPlan = store.browserActionPlan(primaryID: item.clipID)
        let emailPlan = store.emailActionPlan(primaryID: item.clipID)

        Button {
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: false)
        } label: {
            Label(CommonCopy.copy(), systemImage: "doc.on.doc")
        }

        Button {
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
        } label: {
            Label(CommonCopy.paste(), systemImage: "doc.on.clipboard")
        }

        Button {
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true, forcePlainText: true)
        } label: {
            Label(CommonCopy.pasteAsPlainText(), systemImage: "text.quote")
        }

        Button {
            store.openInBrowser(primaryID: item.clipID)
        } label: {
            Label(browserPlan?.menuLabel ?? "Open in Browser", systemImage: browserPlan?.systemImage ?? "safari")
        }
        .disabled(browserPlan == nil)

        Button {
            store.sendAsEmail(primaryID: item.clipID)
        } label: {
            Label(emailPlan?.menuLabel ?? "Send as Email", systemImage: "envelope")
        }
        .disabled(emailPlan == nil)

        Divider()

        Button {
            store.setPinned(!allPinned, for: targetIDs)
        } label: {
            Label(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin")
        }

        Divider()

        Button(role: .destructive) {
            store.deleteClips(targetIDs)
        } label: {
            Label(CommonCopy.delete(), systemImage: "trash")
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
