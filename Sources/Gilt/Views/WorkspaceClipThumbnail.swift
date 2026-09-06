import SwiftUI
import AppKit

/// Small square glyph for a clip in the workspace list/grid.
///
/// What it shows, by type:
/// - **link** → the site favicon (falls back to the link glyph until it loads
///   or if the clip has no favicon yet)
/// - **image** → an async-decoded thumbnail
/// - everything else → the type's SF Symbol
///
/// Image thumbnails load via `ThumbnailService.thumbnailAsync`, which decodes
/// off the main thread. That is what keeps the list/grid layout toggle smooth:
/// the synchronous decode path would freeze the UI while a screenful of cards
/// re-rendered.
struct WorkspaceClipGlyph: View {
    let clip: ClipItemModel
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 7
    var iconSize: CGFloat = 14

    @State private var thumbnail: NSImage?

    private var typeAccent: Color { workspaceClipTypeAccent(clip.clipType) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(typeAccent.opacity(0.18))
            content
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Re-run if the clip identity OR size changes (list vs detail use
        // different sizes). Cheap on a cache hit; off-main on a miss.
        .task(id: thumbnailTaskID) { await loadThumbnailIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch clip.clipType {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                typeIcon
            }
        case .link:
            if let faviconURL = clip.linkFaviconURL {
                AsyncImage(url: faviconURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    typeIcon
                }
                .padding(size * 0.2)
            } else {
                typeIcon
            }
        default:
            typeIcon
        }
    }

    private var typeIcon: some View {
        Image(systemName: workspaceClipTypeIcon(clip.clipType))
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(typeAccent)
    }

    private var thumbnailTaskID: String { "\(clip.clipID.uuidString)-\(Int(size))" }

    private func loadThumbnailIfNeeded() async {
        guard clip.clipType == .image, let data = clip.imageData else { return }
        if let cached = ThumbnailService.shared.cachedThumbnail(for: clip.clipID, maxDimension: size) {
            thumbnail = cached
            return
        }
        thumbnail = await ThumbnailService.shared.thumbnailAsync(
            for: clip.clipID,
            data: data,
            maxDimension: size
        )
    }
}

/// Edge-to-edge image fill for an image clip's grid cell.
///
/// Uses the `Color.clear` + `.overlay(...).clipped()` pattern on purpose: the
/// `Color.clear` adopts exactly the parent's bounded size, the image fills it
/// as an overlay, and `.clipped()` clips to those bounds. A plain
/// `Image.scaledToFill().frame(maxWidth: .infinity).clipped()` can let a wide
/// image push past the card width in some layouts — this cannot. Loads the
/// thumbnail off the main thread so grid toggles don't jank.
struct WorkspaceClipFillImage: View {
    let clip: ClipItemModel
    var maxDimension: CGFloat = 240

    @State private var thumbnail: NSImage?

    private var typeAccent: Color { workspaceClipTypeAccent(clip.clipType) }

    var body: some View {
        Color.clear
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(typeAccent.opacity(0.8))
                }
            }
            .clipped()
            .task(id: clip.clipID) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let data = clip.imageData else { return }
        if let cached = ThumbnailService.shared.cachedThumbnail(for: clip.clipID, maxDimension: maxDimension) {
            thumbnail = cached
            return
        }
        thumbnail = await ThumbnailService.shared.thumbnailAsync(
            for: clip.clipID,
            data: data,
            maxDimension: maxDimension
        )
    }
}
