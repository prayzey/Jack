import AppKit
import SwiftUI

/// A compact clip preview for the radial menu ring layout.
/// Supports rich previews: color fills, link thumbnails, image thumbnails.
struct RadialClipNode: View {
    @EnvironmentObject private var store: ClipboardStore
    let item: ClipItemModel
    var nodeSize: CGSize = CGSize(width: 90, height: 70)
    @State private var isHovered = false

    private func clipboardFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        store.settings.clipboardUIFont(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }


    private var isSelected: Bool {
        store.selectedClipIDs.contains(item.clipID)
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

    var body: some View {
        VStack(spacing: 0) {
            // Type-colored header strip
            RoundedRectangle(cornerRadius: 0)
                .fill(
                    LinearGradient(
                        colors: [typeColor, typeColor.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: nodeSize.height * 0.2)
                .overlay(alignment: .leading) {
                    Text(item.clipType.rawValue.uppercased())
                        .font(clipboardFont(size: max(6, nodeSize.width * 0.078), weight: .bold))
                        .foregroundStyle(typeLabelColor.opacity(0.9))
                        .tracking(0.5)
                        .padding(.leading, 6)
                }
                .overlay(alignment: .trailing) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: max(6, nodeSize.width * 0.072), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.trailing, 6)
                    }
                }

            // Content preview — rich for color/link/image, text fallback otherwise
            richContentArea
                .background(contentBackground)
        }
        .frame(width: nodeSize.width, height: nodeSize.height)
        .clipShape(RoundedRectangle(cornerRadius: nodeSize.width * 0.11))
        .overlay(
            RoundedRectangle(cornerRadius: nodeSize.width * 0.11)
                .strokeBorder(
                    isSelected ? typeColor.opacity(0.95) : (isHovered ? typeColor.opacity(0.8) : Color.white.opacity(0.1)),
                    lineWidth: isSelected ? 2 : (isHovered ? 1.5 : 0.5)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            ClipDragLifecycle.beginWithMouseReleaseRecovery()
            return ClipDragItemProvider.makeProvider(for: item)
        }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                store.toggleSelection(item.clipID)
                store.lastCardTapTime = nil
                store.lastCardTapID = nil
                return
            }

            if store.settings.singleClickToPaste {
                store.lastCardTapTime = nil
                store.lastCardTapID = nil
                store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
                return
            }

            let now = Date()
            let isDoubleTap = store.lastCardTapID == item.clipID
                && store.lastCardTapTime.map({ now.timeIntervalSince($0) < 0.28 }) ?? false

            if isDoubleTap {
                store.lastCardTapTime = nil
                store.lastCardTapID = nil
                store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
            } else {
                store.lastCardTapTime = now
                store.lastCardTapID = item.clipID
                store.selectSingle(item.clipID)
            }
        }
        .contextMenu {
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
                store.setPinned(!item.isPinned, for: [item.clipID])
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
        }
        .help(radialTooltip)
        .onAppear {
            store.fetchLinkMetadataIfNeeded(for: item)
        }
    }

    // MARK: - Rich Content Area

    @ViewBuilder
    private var richContentArea: some View {
        switch item.clipType {
        case .color:
            colorContent
        case .link:
            linkContent
        case .image:
            imageContent
        default:
            textFallback
        }
    }

    /// Color: fill the content area with the parsed color, show hex label
    @ViewBuilder
    private var colorContent: some View {
        if let rgb = parsedClipColor {
            let luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
            let textColor: Color = luminance > 0.55 ? .black.opacity(0.8) : .white.opacity(0.9)

            ZStack {
                Color(red: rgb.r, green: rgb.g, blue: rgb.b)

                Text(item.previewText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(clipboardFont(size: max(7, nodeSize.width * 0.1), weight: .bold, forceMonospaced: true))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            textFallback
        }
    }

    /// Link: show thumbnail if available, otherwise favicon + title
    @ViewBuilder
    private var linkContent: some View {
        // Data-presence branch stays OUTSIDE the shared view so a late-arriving
        // link thumbnail instantiates it fresh and the decode task fires.
        if let data = item.linkThumbnailData {
            AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: thumbnailMaxDimension) { thumb in
                ZStack(alignment: .bottomLeading) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    // Scrim for text readability
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.7), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: nodeSize.height * 0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                    // Title overlay
                    if let title = item.linkPageTitle, !title.isEmpty {
                        Text(title)
                            .font(clipboardFont(size: max(6, nodeSize.width * 0.078), weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .padding(4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } pending: {
                Color(NSColor(white: 0.12, alpha: 1))
            } unavailable: {
                textFallback
            }
        } else {
            textFallback
        }
    }

    /// Image: show the clip image filling the content area
    @ViewBuilder
    private var imageContent: some View {
        if let data = item.imageData {
            AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: thumbnailMaxDimension) { nsImage in
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } pending: {
                Color(NSColor(white: 0.12, alpha: 1))
            } unavailable: {
                textFallback
            }
        } else {
            textFallback
        }
    }

    /// Default text preview
    private var textFallback: some View {
        VStack(spacing: 2) {
            Text(radialDisplayText)
                .font(clipboardFont(size: max(7, nodeSize.width * 0.1), weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
        }
        .background(Color(NSColor(white: 0.12, alpha: 1)))
    }

    /// Content area background — only shown for non-fill types
    @ViewBuilder
    private var contentBackground: some View {
        switch item.clipType {
        case .color, .link, .image:
            // These types fill their own background
            Color.clear
        default:
            Color(NSColor(white: 0.12, alpha: 1))
        }
    }

    // MARK: - Image Decoding

    /// Decode at the base (unscaled) node width. The 1.08x hover is a pure
    /// `scaleEffect` on the already-rendered image and must never feed into
    /// this dimension, or every hover would churn the cache key and re-decode.
    private var thumbnailMaxDimension: CGFloat { nodeSize.width }

    // MARK: - Display Helpers

    /// For links: show page title or full URL instead of just the domain.
    private var radialDisplayText: String {
        guard item.clipType == .link else { return item.previewText }
        if let title = item.linkPageTitle, !title.isEmpty {
            return title
        }
        return item.urlValue ?? item.previewText
    }

    /// Tooltip shows full URL for links so users can identify them on hover.
    private var radialTooltip: String {
        if item.clipType == .link, let url = item.urlValue {
            return String(url.prefix(100))
        }
        return String(item.previewText.prefix(100))
    }
}
