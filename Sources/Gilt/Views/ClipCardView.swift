import AppKit
import SwiftUI

// INVARIANT: Every clip card must maintain the two-zone vertical layout:
//   1. Header band (colored gradient strip with type label + timestamp + source icon)
//   2. Content area (dark body, NSColor(white: 0.12), with type-specific rendering)
// Do not flatten to a single-gradient card or merge zones. The header gradient color
// communicates clip type at a glance; the dark content area ensures readability.
// Both RadialClipNode and DrawerClipRow follow this same two-zone pattern.
struct ClipCardView: View {
    @EnvironmentObject private var store: ClipboardStore
    private let headerHeight: CGFloat = 42
    private let cardCornerRadius: CGFloat = 14

    let item: ClipItemModel
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    var onDragStarted: (() -> Void)? = nil
    var disableBuiltInDrag = false

    // Inline editing state
    @State private var inlineEditText = ""
    @FocusState private var inlineEditorFocused: Bool

    private func clipboardFont(size: CGFloat, weight: Font.Weight = .regular, forceMonospaced: Bool = false) -> Font {
        store.settings.clipboardUIFont(size: size, weight: weight, forceMonospaced: forceMonospaced)
    }

    private var isInlineEditing: Bool {
        store.inlineEditingClipID == item.clipID
    }

    private var canInsertSeparator: Bool {
        store.selectedFolder?.supportsSeparators ?? false
    }

    var body: some View {
        // Keep card layout deterministic: fixed header row + flexible content row.
        VStack(spacing: 0) {
            headerBand
                .frame(maxWidth: .infinity)
                .layoutPriority(2)

            contentArea
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .layoutPriority(0)
                .clipped()
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .compositingGroup()
        .overlay(alignment: .bottomLeading) {
            if !isInlineEditing {
                actionChips
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isInlineEditing {
                footerCaption
                    .padding(8)
            }
        }
        // Inline edit save/cancel pill — floats at bottom of card
        .overlay(alignment: .bottom) {
            if isInlineEditing {
                inlineEditControls
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay {
            if store.aiBusyClipIDs.contains(item.clipID) {
                aiBusyOverlay
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(
                    isInlineEditing ? typeAccentColor.opacity(0.8) :
                    isSelected ? typeAccentColor.opacity(0.95) : Color.white.opacity(0.08),
                    lineWidth: isInlineEditing ? 2 : isSelected ? 2.5 : 0.5
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .modifier(ConditionalDragModifier(
            enabled: !disableBuiltInDrag,
            item: item,
            onDragStarted: onDragStarted,
            preview: {
                ClipDragPreview(
                    clipType: item.clipType,
                    previewText: item.previewText,
                    accentColor: typeAccentColor
                )
            }
        ))
        .onTapGesture {
            // Suppress tap gestures while inline editing — let the TextEditor handle clicks
            guard !isInlineEditing else { return }

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
                // If this card is already part of a multi-selection, preserve
                // the selection so a follow-up double-tap can paste all items.
                let isInMultiSelection = store.selectedClipIDs.count > 1
                    && store.selectedClipIDs.contains(item.clipID)
                if !isInMultiSelection {
                    store.selectSingle(item.clipID)
                }
            }
        }
        .contextMenu { clipContextMenu }
        .onAppear {
            store.fetchLinkMetadataIfNeeded(for: item)
        }
        .onChange(of: store.inlineEditingClipID) { _, newID in
            if newID == item.clipID {
                inlineEditText = item.textValue ?? item.urlValue ?? item.previewText
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    inlineEditorFocused = true
                }
            } else {
                inlineEditorFocused = false
            }
        }
        .onExitCommand {
            if isInlineEditing {
                cancelInlineEdit()
            }
        }
    }

    // MARK: - Header Band

    private var headerBand: some View {
        let labelColors = ClipTypePresentation.headerLabelColors(
            for: item.clipType,
            settings: store.settings,
            parsedColor: parsedClipColor,
            colorHeaderUsesDarkText: colorHeaderUsesDarkText
        )

        return ZStack {
            headerGradient

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(typeLabel)
                            .font(clipboardFont(size: 11, weight: .bold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(labelColors.primary)

                        if store.isMirroredNoteClip(item) {
                            Text(L10n.string("ui.note", default: "NOTE"))
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.22)))
                                .foregroundStyle(Color.orange)
                        }
                    }

                    Text(ClipRelativeTimeFormatter.string(from: item.createdAt))
                        .font(clipboardFont(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(labelColors.secondary)
                }
                .layoutPriority(2)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(labelColors.primary.opacity(0.9))
                        .padding(.trailing, 4)
                }

                if item.isSensitive {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.95, green: 0.57, blue: 0.20))
                        .padding(.trailing, 4)
                }

                if let icon = store.iconForBundle(item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "app.badge")
                        .font(.system(size: 14))
                        .foregroundStyle(labelColors.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: headerHeight, maxHeight: headerHeight)
        .clipped()
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: NSColor(white: 0.12, alpha: 1))

            if isInlineEditing {
                inlineEditorContent
            } else {
                Group {
                    switch item.clipType {
                    case .image:
                        imageContent
                    case .link:
                        linkContent
                    case .audio:
                        audioContent
                    case .color:
                        colorContent
                    case .text:
                        textContent
                    }
                }
                .padding(contentPadding)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    // MARK: - Inline Editor

    private var inlineEditorContent: some View {
        TextEditor(text: $inlineEditText)
            .font(looksLikeCode ? clipboardFont(size: 12, forceMonospaced: true) : clipboardFont(size: 13))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .focused($inlineEditorFocused)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 28) // room for save/cancel icons
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onKeyPress(.return, phases: .down) { keyPress in
                guard keyPress.modifiers.contains(.command) else { return .ignored }
                commitInlineEdit()
                return .handled
            }
    }

    private func commitInlineEdit() {
        store.updateClipText(item.clipID, newText: inlineEditText)
        store.inlineEditingClipID = nil
        inlineEditorFocused = false
    }

    private func cancelInlineEdit() {
        store.inlineEditingClipID = nil
        inlineEditorFocused = false
    }

    private var inlineEditControls: some View {
        HStack(spacing: 8) {
            // Cancel (x)
            Button {
                cancelInlineEdit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")

            // Save (checkmark)
            Button {
                commitInlineEdit()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(typeAccentColor)
            }
            .buttonStyle(.plain)
            .help("Save (⌘Return)")
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        // GeometryReader pins preview rendering to the content box so intrinsic image size
        // never feeds back into card layout.
        GeometryReader { geo in
            // Data-presence branch stays OUTSIDE the shared view: the thumbnail
            // view is instantiated only once bytes exist, so its decode task
            // fires with a fresh identity when data arrives late.
            if let data = item.imageData {
                AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: cardWidth) { image in
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } pending: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.04))
                        .frame(width: geo.size.width, height: geo.size.height)
                } unavailable: {
                    imageUnavailableText(size: geo.size)
                }
            } else {
                imageUnavailableText(size: geo.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imageUnavailableText(size: CGSize) -> some View {
        Text(L10n.string("ui.image.preview.unavailable", default: "Image preview unavailable"))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Link Content (Rich Previews)

    private var linkContent: some View {
        // Creative previews for link-type clips that are really dev references.
        // The same content can arrive as .link or .text depending on how the user copied it:
        //   - Browser address bar → NSPasteboardTypeURL → .link (even for localhost:3000)
        //   - Text editor / terminal → plain string → .text
        //   - Some apps put "wow.md" as a URL because .md is a valid TLD (Moldova)
        // We check both urlValue and the underlying text to catch all cases.
        let url = item.urlValue ?? item.previewText
        if let pattern = CreativeTextPattern.detect(in: url) {
            return AnyView(creativeContent(for: pattern, text: url))
        }

        return AnyView(
            GeometryReader { geo in
                // Data-presence branch stays OUTSIDE the shared view (see imageContent).
                // A link clip renders before LinkMetadataService delivers its
                // thumbnail 1-2s after copy; instantiating the shared view only
                // once data exists is what makes the late decode fire.
                if let data = item.linkThumbnailData {
                    AsyncClipThumbnail(clipID: item.clipID, data: data, maxDimension: cardWidth) { thumbnail in
                        linkThumbnailCard(thumbnail: thumbnail, size: geo.size)
                    } pending: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.04))
                            .frame(width: geo.size.width, height: geo.size.height)
                    } unavailable: {
                        linkTextCardFallback(size: geo.size)
                    }
                } else {
                    linkTextCardFallback(size: geo.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    private func linkTextCardFallback(size: CGSize) -> some View {
        linkTextCard
            .padding(10)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Thumbnail-based link card: image fills content area, text overlays at bottom
    private func linkThumbnailCard(thumbnail: NSImage, size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail fills everything
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()

            // Gradient scrim at bottom for text readability
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.3),
                    .init(color: .black.opacity(0.88), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size.height * 0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            // Bottom text overlay
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    linkFaviconSmall
                    Text(linkTitle)
                        .font(clipboardFont(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if let host = linkDisplayURL {
                    Text(host)
                        .font(clipboardFont(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(8)

            // Duration badge — bottom-right, floating above scrim
            if let duration = item.linkVideoDuration, !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.black.opacity(0.80))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Text-only link card: favicon + title + description + host
    private var linkTextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                linkFaviconLarge
                Text(linkTitle)
                    .font(clipboardFont(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
            }

            // OG description
            if let desc = item.linkDescriptionText, !desc.isEmpty {
                let maxLines = max(2, Int((cardHeight - headerHeight - 70) / 16))
                Text(desc)
                    .font(clipboardFont(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(maxLines)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if let host = linkDisplayURL {
                Text(host)
                    .font(clipboardFont(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Link Favicon Helpers

    @ViewBuilder
    private var linkFaviconSmall: some View {
        if let faviconURL = item.linkFaviconURL {
            AsyncImage(url: faviconURL) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.15))
            }
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder
    private var linkFaviconLarge: some View {
        if let faviconURL = item.linkFaviconURL {
            AsyncImage(url: faviconURL) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// Display URL: strips protocol, shows host + path (e.g., "github.com/apple/swift")
    private var linkDisplayURL: String? {
        guard let raw = item.urlValue, let url = URL(string: raw) else { return nil }
        guard let host = url.host(percentEncoded: false) else { return nil }
        let path = url.path
        // Strip trailing slash, combine host + path
        let cleanPath = path == "/" ? "" : path
        let display = host + cleanPath
        // Remove www. prefix for cleaner display
        if display.hasPrefix("www.") {
            return String(display.dropFirst(4))
        }
        return display
    }

    private var audioContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(typeAccentColor.opacity(0.6))
                        .frame(width: 3, height: waveformHeight(for: i))
                }
            }
            .frame(height: 30)

            Text(item.previewText)
                .font(clipboardFont(size: 12))
                .lineLimit(nil)
                .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var textContent: some View {
        let text = item.textValue ?? item.previewText

        // Creative preview for special patterns (localhost URLs, file paths)
        if let pattern = CreativeTextPattern.detect(in: text) {
            return AnyView(creativeContent(for: pattern, text: text))
        }

        let availableHeight = cardHeight - headerHeight - 20 // header + padding
        let fontSize: CGFloat = looksLikeCode
            ? 12
            : clipTextDisplayFontSize(
                characterCount: item.previewText.count,
                availableWidth: cardWidth - contentPadding * 2,
                availableHeight: availableHeight
            )
        let lineHeight: CGFloat = fontSize * 1.35
        let maxLines = max(3, Int(availableHeight / lineHeight))

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                if item.contentTags.contains(.colorValue) {
                    colorSwatchRow
                }

                Text(item.previewText)
                    .font(looksLikeCode ? clipboardFont(size: fontSize, forceMonospaced: true) : clipboardFont(size: fontSize, weight: fontSize >= 18 ? .medium : .regular))
                    .lineSpacing(fontSize >= 16 ? fontSize * 0.18 : 0)
                    .lineLimit(maxLines)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .animation(.easeOut(duration: 0.12), value: fontSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    @ViewBuilder
    private func creativeContent(for pattern: CreativeTextPattern, text: String) -> some View {
        switch pattern {
        case .localhost(let port, let path):
            LocalhostPreview(port: port, path: path, fullText: text)
        case .filePath(let filename, let ext):
            FilePathPreview(filename: filename, ext: ext)
        }
    }

    private var colorContent: some View {
        let text = item.textValue ?? item.previewText
        let rgb = ContentClassifier.parseAnyColor(text)
        let parsedColor = rgb.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
        let luminance = rgb.map { 0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b } ?? 0.5
        let textColor: Color = luminance > 0.55 ? .black.opacity(0.85) : .white.opacity(0.95)

        return ZStack {
            if let fill = parsedColor {
                fill
            } else {
                Color(nsColor: NSColor(white: 0.12, alpha: 1))
            }

            VStack(spacing: 4) {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var colorSwatchRow: some View {
        let text = item.textValue ?? item.previewText
        if let rgb = ContentClassifier.parseHexColor(text) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Footer

    private var footerCaption: some View {
        Group {
            if let dimensions = decodedClipImageDimensions {
                Text(dimensions)
            } else if item.clipType == .link || item.clipType == .color || item.clipType == .audio {
                EmptyView()
            } else if let text = item.textValue ?? item.previewText as String? {
                Text("\(text.count) chars")
            }
        }
        .font(clipboardFont(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.35))
    }

    // MARK: - Color Parsing for Color-Type Cards

    /// Parses the actual hex/rgb color from a color-type clip, returns (r, g, b) in 0…1
    private var parsedClipColor: (r: Double, g: Double, b: Double)? {
        guard item.clipType == .color else { return nil }
        let text = item.textValue ?? item.previewText
        return ContentClassifier.parseAnyColor(text)
    }

    /// Luminance of the parsed clip color (for readability decisions)
    private var parsedClipLuminance: Double {
        guard let c = parsedClipColor else { return 0.5 }
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    /// Whether header text should be dark (for light color cards)
    private var colorHeaderUsesDarkText: Bool {
        parsedClipLuminance > 0.55
    }

    // MARK: - Helpers

    private var typeLabel: String {
        ClipTypePresentation.label(for: item.clipType, linkPlatform: item.linkPlatform)
    }

    private var typeAccentColor: Color {
        ClipTypePresentation.accentColor(
            for: item.clipType,
            settings: store.settings,
            linkPlatform: item.linkPlatform,
            parsedColor: parsedClipColor
        )
    }

    private var headerGradient: LinearGradient {
        ClipTypePresentation.headerGradient(
            for: item.clipType,
            settings: store.settings,
            linkPlatform: item.linkPlatform,
            parsedColor: parsedClipColor,
            colorHeaderUsesDarkText: colorHeaderUsesDarkText
        )
    }

    private var isSelected: Bool {
        store.selectedClipIDs.contains(item.clipID)
    }

    /// Edge-to-edge for thumbnails, color cards, and links (links handle padding internally)
    private var contentPadding: CGFloat {
        if item.clipType == .color { return 0 }
        if item.clipType == .link { return 0 }
        return 10
    }

    private var linkTitle: String {
        if let pageTitle = item.linkPageTitle, !pageTitle.isEmpty {
            return pageTitle
        }
        return item.urlValue ?? item.previewText
    }

    private var looksLikeCode: Bool {
        item.contentTags.contains(.code)
    }

    // MARK: - Action Chips

    private var actionChips: some View {
        let actions = item.clipType == .link ? [] : store.suggestedActions(for: item)
        return HStack(spacing: 4) {
            ForEach(Array(actions.prefix(3).enumerated()), id: \.offset) { _, action in
                actionChip(action)
            }
        }
    }

    private func actionChip(_ action: SuggestedAction) -> some View {
        let icon: String = {
            switch action.type {
            case .call: return "phone"
            case .email: return "envelope"
            case .openURL: return "arrow.up.right"
            case .openMaps: return "map"
            case .colorSwatch: return "paintpalette"
            case .language: return "chevron.left.forwardslash.chevron.right"
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(action.label)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .onTapGesture {
            if action.type == .openURL, let url = URL(string: action.value) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        let seed = abs(sin(Double(index) * 1.8 + Double(item.clipID.hashValue % 100)))
        return CGFloat(6 + seed * 22)
    }

    @MainActor
    private var decodedClipImageDimensions: String? {
        guard item.clipType == .image else { return nil }
        if let cached = ThumbnailService.shared.dimensions(for: item.clipID) {
            return cached
        }
        // Metadata-only read (CGImageSource properties), no bitmap decode.
        guard let data = item.imageData else { return nil }
        return ThumbnailService.shared.dimensions(for: item.clipID, data: data)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var clipContextMenu: some View {
        let hasSelection = !store.selectedClipIDs.isEmpty
        let targetCount = hasSelection ? store.selectedClipIDs.count : 1
        let targetIDs = hasSelection ? store.selectedClipIDs : [item.clipID]
        let targetItems = store.clips.filter { targetIDs.contains($0.clipID) }
        let allPinned = !targetItems.isEmpty && targetItems.allSatisfy(\.isPinned)
        let anyPinned = targetItems.contains(where: \.isPinned)
        let browserPlan = store.browserActionPlan(primaryID: item.clipID)
        let emailPlan = store.emailActionPlan(primaryID: item.clipID)
        let imageData = item.clipType == .image ? item.imageData : nil

        // Copy
        Button {
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: false)
        } label: {
            Label(targetCount > 1 ? "Copy \(targetCount) Items" : "Copy", systemImage: "doc.on.doc")
        }

        // Paste
        Button {
            store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true)
        } label: {
            Label(CommonCopy.paste(), systemImage: "doc.on.clipboard")
        }

        // Paste as Plain Text
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

        if let imageData {
            Divider()

            Menu {
                ForEach(ImageExportFormat.allCases, id: \.displayName) { format in
                    Button {
                        ImageClipActionService.shared.exportImage(
                            imageData,
                            as: format,
                            suggestedBaseName: imageExportBaseName
                        )
                    } label: {
                        Label(format.displayName, systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Label(L10n.string("ui.export.as", default: "Export As"), systemImage: "square.and.arrow.down")
            }

            Menu {
                ForEach(ImageExportFormat.allCases, id: \.displayName) { format in
                    Button {
                        ImageClipActionService.shared.copyImage(imageData, as: format)
                    } label: {
                        Label(format.displayName, systemImage: "doc.on.doc")
                    }
                }
            } label: {
                Label(L10n.string("ui.copy.as", default: "Copy As"), systemImage: "doc.on.doc")
            }

            Button {
                DispatchQueue.main.async {
                    ImageClipActionService.shared.quickShareImage(imageData)
                }
            } label: {
                Label(L10n.string("ui.quick.share", default: "Quick Share"), systemImage: "square.and.arrow.up")
            }

            Button {
                ImageClipActionService.shared.revealLastExportedFile()
            } label: {
                Label(L10n.string("ui.reveal.exported.image.in.finder", default: "Reveal Exported Image in Finder"), systemImage: "folder")
            }
            .disabled(!ImageClipActionService.shared.hasLastExportedFile)
        }

        Divider()

        if allPinned {
            Button {
                store.setPinned(false, for: targetIDs)
            } label: {
                Label(targetCount > 1 ? "Unpin \(targetCount) Items" : "Unpin", systemImage: "pin.slash")
            }
        } else if anyPinned {
            Button {
                store.setPinned(true, for: targetIDs)
            } label: {
                Label(targetCount > 1 ? "Pin \(targetCount) Items" : "Pin", systemImage: "pin")
            }
            Button {
                store.setPinned(false, for: targetIDs)
            } label: {
                Label(targetCount > 1 ? "Unpin \(targetCount) Items" : "Unpin", systemImage: "pin.slash")
            }
        } else {
            Button {
                store.setPinned(true, for: targetIDs)
            } label: {
                Label(targetCount > 1 ? "Pin \(targetCount) Items" : "Pin", systemImage: "pin")
            }
        }

        Divider()

        // Add to folder — show all folders, checkmark ones the clip is already in
        let clipFolderIDs = Set(item.folders.map(\.folderID))
        Menu {
            ForEach(store.folders, id: \.folderID) { folder in
                let alreadyIn = clipFolderIDs.contains(folder.folderID)
                Button {
                    if hasSelection {
                        for clipID in store.selectedClipIDs {
                            store.addClip(clipID, to: folder.folderID)
                        }
                    } else {
                        store.addClip(item.clipID, to: folder.folderID)
                    }
                } label: {
                    if alreadyIn {
                        Label(folder.displayName, systemImage: "checkmark.circle.fill")
                    } else {
                        Label(folder.displayName, systemImage: "folder")
                    }
                }
                .disabled(alreadyIn)
            }
        } label: {
            Label(L10n.string("ui.add.to.folder", default: "Add to Folder"), systemImage: "folder.badge.plus")
        }

        // Quick Look
        Button {
            store.openPreview(for: item.clipID)
        } label: {
            Label(L10n.string("ui.quick.look", default: "Quick Look"), systemImage: "space")
        }

        // Edit (text/link/color only) — inline editing directly in the card
        if ClipboardStore.canInlineEdit(item.clipType) {
            Button {
                store.startInlineEdit(for: item.clipID)
            } label: {
                Label(L10n.string("ui.edit", default: "Edit"), systemImage: "pencil")
            }

            // Transform submenu (text-based clips only)
            transformSubmenu
        }

        // On-device AI actions (macOS 26 + Apple Intelligence). Hidden entirely when the model
        // can't run or the clip has no usable text, so it never dangles as a dead menu item.
        if store.aiClipActionsAvailable, store.aiHasUsableText(item) {
            aiSubmenu
        }

        Divider()

        // Select / deselect
        if isSelected {
            Button {
                store.toggleSelection(item.clipID)
            } label: {
                Label(L10n.string("ui.deselect", default: "Deselect"), systemImage: "checkmark.circle")
            }
        } else {
            Button {
                store.toggleSelection(item.clipID)
            } label: {
                Label(L10n.string("ui.select", default: "Select"), systemImage: "circle")
            }
        }

        Divider()

        if canInsertSeparator {
            // Separators are scoped to folders, not the top-level Clipboard inbox.
            Button {
                store.addSeparator(afterClipID: item.clipID)
            } label: {
                Label(L10n.string("ui.insert.separator.after", default: "Insert Separator After"), systemImage: "minus")
            }

            Divider()
        }

        // Delete
        Button(role: .destructive) {
            if hasSelection {
                store.deleteClips(store.selectedClipIDs)
            } else {
                store.deleteClip(item.clipID)
            }
        } label: {
            Label(targetCount > 1 ? "Delete \(targetCount) Items" : "Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var transformSubmenu: some View {
        Menu {
            ForEach(Array(TextTransform.groupedForMenu.enumerated()), id: \.offset) { groupIndex, entry in
                if groupIndex > 0 {
                    Divider()
                }
                ForEach(entry.transforms, id: \.rawValue) { transform in
                    Button {
                        store.transformClipText(item.clipID, transform: transform)
                    } label: {
                        Label(transform.label, systemImage: transform.icon)
                    }
                }
            }
        } label: {
            Label(L10n.string("ui.transform", default: "Transform"), systemImage: "wand.and.stars")
        }
    }

    @ViewBuilder
    private var aiSubmenu: some View {
        Menu {
            ForEach(AITextAction.allCases) { action in
                Button {
                    store.runAITextAction(action, on: item.clipID)
                } label: {
                    Label(action.label, systemImage: action.icon)
                }
            }

            Divider()

            Button {
                store.aiExtractActionItems(item.clipID)
            } label: {
                Label(L10n.string("ai.action.actionItems", default: "Extract Action Items"), systemImage: "checklist")
            }

            if store.settings.aiReminderExtractionEnabled {
                Button {
                    store.aiCreateReminder(from: item.clipID)
                } label: {
                    Label(L10n.string("ai.action.reminder", default: "Create Reminder"), systemImage: "bell.badge")
                }
            }

            Divider()

            Button {
                store.aiRetitleClip(item.clipID)
            } label: {
                Label(L10n.string("ai.action.retitle", default: "Rename with AI"), systemImage: "character.cursor.ibeam")
            }
        } label: {
            Label(L10n.string("ai.menu.title", default: "AI Tools"), systemImage: "sparkles")
        }
    }

    private var aiBusyOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(L10n.string("ai.card.thinking", default: "Thinking…"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .transition(.opacity)
        .allowsHitTesting(true)
    }

    private var imageExportBaseName: String {
        let trimmed = (item.title.isEmpty ? item.previewText : item.title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Image" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            return "jack-image-\(formatter.string(from: item.createdAt))"
        }
        return trimmed
    }
}

// MARK: - Drag Preview

struct ClipDragPreview: View {
    let clipType: ClipType
    let previewText: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: typeSymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            Text(shortLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.7))
        )
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    private var shortLabel: String {
        let raw = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return ClipTypePresentation.label(for: clipType) }
        let firstLine = raw.components(separatedBy: .newlines).first ?? raw
        return String(firstLine.prefix(24)) + (firstLine.count > 24 ? "…" : "")
    }

    private var typeSymbol: String {
        ClipTypePresentation.symbol(for: clipType)
    }
}

// MARK: - Conditional Drag Modifier

/// Applies `.onDrag` only when enabled, allowing parent views to use `.draggable()` instead.
private struct ConditionalDragModifier<Preview: View>: ViewModifier {
    let enabled: Bool
    let item: ClipItemModel
    let onDragStarted: (() -> Void)?
    @ViewBuilder let preview: () -> Preview

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                onDragStarted?()
                return ClipDragItemProvider.makeProvider(for: item)
            } preview: {
                preview()
            }
        } else {
            content
        }
    }
}
