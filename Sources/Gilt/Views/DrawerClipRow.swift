import AppKit
import SwiftUI

/// Compact horizontal row for a clip in the side drawer's vertical list.
/// Supports rich previews: color fills, link thumbnails, image thumbnails.
struct DrawerClipRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let item: ClipItemModel
    let isSelected: Bool

    // Double-tap detection
    @State private var lastTapTime: Date?

    private func clipboardFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        store.settings.clipboardUIFont(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }


    private var typeColor: Color {
        ClipTypePresentation.accentColor(
            for: item.clipType,
            settings: store.settings,
            linkPlatform: item.linkPlatform,
            parsedColor: parsedClipColor
        )
    }

    private var typeLabelColor: Color {
        ClipTypePresentation.headerLabelColors(
            for: item.clipType,
            settings: store.settings,
            parsedColor: parsedClipColor,
            colorHeaderUsesDarkText: colorHeaderUsesDarkText
        ).primary
    }

    private var parsedClipColor: (r: Double, g: Double, b: Double)? {
        guard item.clipType == .color else { return nil }
        let text = item.textValue ?? item.previewText
        return ContentClassifier.parseAnyColor(text)
    }

    private var colorHeaderUsesDarkText: Bool {
        guard let c = parsedClipColor else { return false }
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.55
    }

    // Width breakpoints for responsive layout
    // Below compact: hide host, duration, source icon, shrink thumbnail
    // Below tiny: hide thumbnail entirely
    private static let compactThreshold: CGFloat = 300
    private static let tinyThreshold: CGFloat = 240

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < Self.compactThreshold
            let isTiny = geo.size.width < Self.tinyThreshold

            HStack(spacing: isTiny ? 8 : 10) {
                // Leading thumbnail — hidden at tiny widths
                if !isTiny {
                    leadingThumbnail(compact: isCompact)
                }

                // Content preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(drawerDisplayText)
                        .font(clipboardFont(size: 12, weight: .regular))
                        .foregroundStyle(drawerTextColor)
                        .lineLimit(isCompact ? 1 : 2)

                    HStack(spacing: 4) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(metadataTextColor.opacity(0.8))
                        }

                        Text(item.clipType.rawValue.uppercased())
                            .font(clipboardFont(size: 9, weight: .bold))
                            .foregroundStyle(typeLabelColor.opacity(0.9))
                            .tracking(0.5)

                        if store.isMirroredNoteClip(item) {
                            Text(L10n.string("ui.note", default: "NOTE"))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.orange)
                        }

                        // Host + duration only when there's room
                        if !isCompact, item.clipType == .link {
                            if let host = linkHost {
                                Text(host)
                                    .font(clipboardFont(size: 9))
                                    .foregroundStyle(typeColor.opacity(0.45))
                                    .lineLimit(1)
                            }
                            if let duration = item.linkVideoDuration, !duration.isEmpty {
                                Text(duration)
                                    .font(clipboardFont(size: 9, weight: .bold, forceMonospaced: true))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Text("·")
                                .font(clipboardFont(size: 9))
                                .foregroundStyle(.white.opacity(0.25))
                        }

                        Text(timeAgo(item.createdAt))
                            .font(clipboardFont(size: 9))
                            .foregroundStyle(metadataTextColor.opacity(0.35))
                    }
                }

                Spacer(minLength: 2)

                // Source app icon — hidden at compact widths
                if !isCompact, let icon = store.iconForBundle(item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, isTiny ? 8 : 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? typeColor.opacity(0.6) : Color.white.opacity(0.06),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
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
            let isDoubleTap: Bool
            if let lastTime = lastTapTime,
               now.timeIntervalSince(lastTime) < 0.28 {
                isDoubleTap = true
            } else {
                isDoubleTap = false
            }
            lastTapTime = now

            if isDoubleTap {
                store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
            } else {
                // Preserve multi-selection so a follow-up double-tap pastes all items.
                let isInMultiSelection = store.selectedClipIDs.count > 1
                    && store.selectedClipIDs.contains(item.clipID)
                if !isInMultiSelection {
                    store.selectSingle(item.clipID)
                }
            }
        }
        .contextMenu {
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
        }
        .onDrag {
            ClipDragLifecycle.beginWithMouseReleaseRecovery()
            return ClipDragItemProvider.makeProvider(for: item)
        }
        .onAppear {
            store.fetchLinkMetadataIfNeeded(for: item)
        }
    }

    // MARK: - Layout Constants

    /// Whether this row has a visual thumbnail (determines row height).
    /// Keyed on data presence, not decode completion, so the row height doesn't
    /// jump from 44 to 56 when the async decode lands.
    private var hasThumbnail: Bool {
        switch item.clipType {
        case .color: return parsedClipColor != nil
        case .link: return item.linkThumbnailData != nil || item.linkFaviconURL != nil
        case .image: return item.imageData != nil
        default: return false
        }
    }

    /// Row height adapts to content — taller when showing a thumbnail
    private var rowHeight: CGFloat {
        hasThumbnail ? 56 : 44
    }

    // MARK: - Rich Leading Thumbnail

    @ViewBuilder
    private func leadingThumbnail(compact: Bool) -> some View {
        let thumbSize: CGFloat = compact ? 32 : 40
        let wideSize: CGFloat = compact ? 38 : 48

        switch item.clipType {
        case .color:
            colorThumbnail(size: thumbSize)
        case .link:
            linkThumbnail(thumbWidth: wideSize, thumbHeight: thumbSize)
        case .image:
            imageThumbnail(thumbWidth: wideSize, thumbHeight: thumbSize)
        default:
            EmptyView()
        }
    }

    /// Color type: rounded swatch filled with the parsed color
    @ViewBuilder
    private func colorThumbnail(size: CGFloat) -> some View {
        if let rgb = parsedClipColor {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }

    /// Link type: thumbnail image or favicon fallback
    @ViewBuilder
    private func linkThumbnail(thumbWidth: CGFloat, thumbHeight: CGFloat) -> some View {
        // Data-presence branch stays OUTSIDE the shared view: before
        // LinkMetadataService delivers linkThumbnailData (1-2s after copy) the
        // row must show the favicon fallback, never a pending fill, and once
        // data lands the shared view instantiates fresh and its decode fires.
        if let data = item.linkThumbnailData {
            AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: Self.thumbnailMaxDimension) { thumb in
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } pending: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.04))
                    .frame(width: thumbWidth, height: thumbHeight)
            } unavailable: {
                faviconFallback
            }
        } else {
            faviconFallback
        }
    }

    @ViewBuilder
    private var faviconFallback: some View {
        if let faviconURL = item.linkFaviconURL {
            AsyncImage(url: faviconURL) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(typeColor.opacity(0.15))
                    .overlay(
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundStyle(typeColor.opacity(0.5))
                    )
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    /// Image type: small thumbnail preview
    @ViewBuilder
    private func imageThumbnail(thumbWidth: CGFloat, thumbHeight: CGFloat) -> some View {
        if let data = item.imageData {
            AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: Self.thumbnailMaxDimension) { image in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } pending: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.04))
                    .frame(width: thumbWidth, height: thumbHeight)
            } unavailable: {
                EmptyView()
            }
        }
    }

    // MARK: - Row Background

    private var rowBackground: some ShapeStyle {
        if item.clipType == .color, let rgb = parsedClipColor {
            // Subtle color tint in the row background
            return AnyShapeStyle(
                Color(red: rgb.r, green: rgb.g, blue: rgb.b).opacity(isSelected ? 0.20 : 0.10)
            )
        }
        return AnyShapeStyle(
            isSelected
                ? typeColor.opacity(0.15)
                : Color(NSColor(white: 0.10, alpha: 0.85))
        )
    }

    // MARK: - Text Colors (adapt for color-type rows)

    private var drawerTextColor: Color {
        .white.opacity(0.9)
    }

    private var metadataTextColor: Color {
        .white
    }

    // MARK: - Image Decoding

    /// Both leading thumbnails decode at a fixed 48pt so the cache key never churns.
    private static let thumbnailMaxDimension: CGFloat = 48

    // MARK: - Display Helpers

    /// For links: show page title or full URL instead of just the domain.
    private var drawerDisplayText: String {
        if item.clipType == .link {
            if let title = item.linkPageTitle, !title.isEmpty {
                return title
            }
            return item.urlValue ?? item.previewText
        }
        return item.previewText
    }

    /// Extract a short host label for the subtitle line.
    private var linkHost: String? {
        guard item.clipType == .link,
              let urlString = item.urlValue,
              let url = URL(string: urlString),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
