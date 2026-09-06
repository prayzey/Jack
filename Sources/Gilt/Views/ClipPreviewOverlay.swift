import AppKit
import SwiftUI

/// Full-content preview overlay shown when pressing Space on a selected clip.
/// Supports inline text editing for text and link clips.
struct ClipPreviewOverlay: View {
    @EnvironmentObject private var store: ClipboardStore
    let item: ClipItemModel

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.white.opacity(0.1))
            content
            footer
        }
        .background(Color(nsColor: NSColor(white: 0.10, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(typeAccentColor.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Close / back
            Button {
                if isEditing {
                    isEditing = false
                } else {
                    store.previewingClipID = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isEditing ? "xmark" : "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isEditing ? "Cancel" : "Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Spacer()

            // Type badge
            Text(typeLabel)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(typeAccentColor)

            Spacer()

            // Action buttons
            if isEditing {
                Button {
                    store.updateClipText(item.clipID, newText: editText)
                    isEditing = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.string("settings.kanban.assist.save", default: "Save"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(typeAccentColor)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    if canEdit {
                        Button {
                            beginEditing()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        // Transform menu (text-based clips only)
                        transformMenu
                    }

                    Button {
                        store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: false)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    // Paste as plain text
                    Button {
                        store.loadSelectedOrSingleToClipboard(primaryID: item.clipID, autoPaste: true, forcePlainText: true)
                    } label: {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Paste as Plain Text")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            headerGradient.opacity(0.3)
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isEditing {
            editingContent
        } else {
            readOnlyContent
        }
    }

    private var editingContent: some View {
        TextEditor(text: $editText)
            .font(looksLikeCode ? .system(size: 13, design: .monospaced) : .system(size: 13))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var readOnlyContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Group {
                switch item.clipType {
                case .text:
                    previewText
                case .link:
                    previewLink
                case .image:
                    previewImage
                case .audio:
                    previewAudio
                case .color:
                    previewColor
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewText: some View {
        let fullText = item.textValue ?? item.previewText
        return Text(fullText)
            .font(looksLikeCode ? .system(size: 13, design: .monospaced) : .system(size: 13))
            .foregroundStyle(.white.opacity(0.9))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var previewLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let faviconURL = item.linkFaviconURL {
                AsyncImage(url: faviconURL) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let title = item.linkPageTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
            }

            if let url = item.urlValue {
                Text(url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(typeAccentColor.opacity(0.8))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var previewImage: some View {
        // AsyncClipThumbnail's clipID-matched state is what fixed the overlay's
        // stale-image bug: switching the previewed clip from A to B used to keep
        // showing A's full image (and A's failure flag) under B's metadata.
        if let data = item.imageData {
            AsyncClipThumbnail(clipID: item.clipID, data: data, tier: .full) { nsImage in
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } pending: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            } unavailable: {
                imageUnavailableText
            }
        } else {
            imageUnavailableText
        }
    }

    private var imageUnavailableText: some View {
        Text(L10n.string("ui.image.data.unavailable", default: "Image data unavailable"))
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.5))
    }

    private var previewAudio: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<30, id: \.self) { i in
                    let seed = abs(sin(Double(i) * 1.8 + Double(item.clipID.hashValue % 100)))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(typeAccentColor.opacity(0.6))
                        .frame(width: 4, height: CGFloat(8 + seed * 36))
                }
            }
            .frame(height: 44)

            Text(item.previewText)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var previewColor: some View {
        let text = item.textValue ?? item.previewText
        let rgb = ContentClassifier.parseAnyColor(text)
        let parsedColor = rgb.map { Color(red: $0.r, green: $0.g, blue: $0.b) }

        return VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(parsedColor ?? Color(nsColor: NSColor(white: 0.2, alpha: 1)))
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Source app
            HStack(spacing: 5) {
                if let icon = store.iconForBundle(item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(item.sourceAppName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Stats
            HStack(spacing: 8) {
                if item.clipType == .image, let dims = ThumbnailService.shared.dimensions(for: item.clipID) {
                    Text(dims)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                } else if let text = item.textValue ?? item.previewText as String? {
                    Text("\(text.count) chars")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Text(ClipRelativeTimeFormatter.string(from: item.createdAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
    }

    // MARK: - Helpers

    private var canEdit: Bool {
        ClipboardStore.canInlineEdit(item.clipType)
    }

    private var looksLikeCode: Bool {
        item.contentTags.contains(.code)
    }

    private var typeLabel: String {
        ClipTypePresentation.label(for: item.clipType, linkPlatform: item.linkPlatform)
    }

    private var parsedClipColor: (r: Double, g: Double, b: Double)? {
        guard item.clipType == .color else { return nil }
        let text = item.textValue ?? item.previewText
        return ContentClassifier.parseAnyColor(text)
    }

    private var typeAccentColor: Color {
        ClipTypePresentation.accentColor(
            for: item.clipType,
            settings: store.settings,
            linkPlatform: item.linkPlatform,
            parsedColor: parsedClipColor
        )
    }

    private var parsedClipLuminance: Double {
        guard let c = parsedClipColor else { return 0.5 }
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    private var colorHeaderUsesDarkText: Bool {
        parsedClipLuminance > 0.55
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

    private func beginEditing() {
        guard canEdit else { return }
        editText = item.textValue ?? item.urlValue ?? item.previewText
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editorFocused = true
        }
    }

    @ViewBuilder
    private var transformMenu: some View {
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
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Transform Text")
    }

}
