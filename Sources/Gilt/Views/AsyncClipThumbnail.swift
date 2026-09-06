import AppKit
import SwiftUI

/// Shared async image decoding for clip thumbnails and full-size previews.
///
/// Consolidates the hand-rolled decode pattern that was copied across
/// ClipCardView, DrawerClipRow, PanelClipRow, RadialClipNode, ClipPreviewOverlay,
/// and WorkspaceClipDetailView. Callers keep their own no-data branches and pass
/// non-optional `data`: the view is only instantiated once image bytes exist, so
/// when LinkMetadataService delivers a link thumbnail 1-2s after copy, the fresh
/// view identity fires `.task` and decodes. (The old per-view task ids were keyed
/// on clipID/size only, so they never re-fired when data arrived late and the
/// row showed a permanent placeholder.)
struct AsyncClipThumbnail<Content: View, Pending: View, Unavailable: View>: View {
    /// Which ThumbnailService cache tier to decode into.
    enum Tier {
        /// Downsampled via CGImageSource at `maxDimension` points.
        case thumbnail
        /// Full-resolution `NSImage(data:)`, cached under the "-full" key.
        case full
    }

    let clipID: UUID
    let data: Data
    var maxDimension: CGFloat = 0
    var tier: Tier = .thumbnail
    @ViewBuilder let content: (NSImage) -> Content
    @ViewBuilder let pending: () -> Pending
    @ViewBuilder let unavailable: () -> Unavailable

    // The clipID stored alongside the image is the key design point: it keeps a
    // stale image visible while the SAME clip re-decodes at a new size
    // (flicker-free resize), but can never show a DIFFERENT clip's image when
    // this view is reused for another item. ClipPreviewOverlay had exactly that
    // bug: switching the previewed clip from A to B kept showing A's full image
    // under B's metadata.
    @State private var loaded: (clipID: UUID, image: NSImage)?
    // UUID-keyed rather than a Bool so a failure recorded for clip A can never
    // mislabel clip B as unavailable during the render gap before B's task runs.
    @State private var decodeFailedClipID: UUID?

    /// Decode dimension = maxDimension rounded UP to the next multiple of 64
    /// points. ClipCardView passes a continuously-varying cardWidth during live
    /// window resize; an unquantized dimension changes the task id and
    /// ThumbnailService cache key every half-point, spawning hundreds of
    /// redundant background decodes per drag and churning the NSCache.
    /// Quantizing makes the whole drag hit one bucket. Fixed-size callers just
    /// decode one bucket up (48 -> 64), which is visually identical.
    private var decodeDimension: CGFloat {
        max(64, ceil(maxDimension / 64) * 64)
    }

    /// Re-runs the decode when the clip, tier, or quantized pixel bucket changes.
    private var taskID: String {
        switch tier {
        case .thumbnail: return "\(clipID.uuidString)-\(Int(decodeDimension * 2))"
        case .full: return "\(clipID.uuidString)-full"
        }
    }

    /// Cache peek first (never blocks), then the last async decode, but only if
    /// that decode belongs to the clip currently displayed.
    @MainActor
    private var resolvedImage: NSImage? {
        let cached: NSImage?
        switch tier {
        case .thumbnail:
            cached = ThumbnailService.shared.cachedThumbnail(for: clipID, maxDimension: decodeDimension)
        case .full:
            cached = ThumbnailService.shared.cachedFullImage(for: clipID)
        }
        if let cached { return cached }
        return loaded?.clipID == clipID ? loaded?.image : nil
    }

    var body: some View {
        Group {
            if let image = resolvedImage {
                content(image)
            } else if decodeFailedClipID == clipID {
                unavailable()
            } else {
                pending()
            }
        }
        .task(id: taskID) {
            let image: NSImage?
            switch tier {
            case .thumbnail:
                image = await ThumbnailService.shared.thumbnailAsync(for: clipID, data: data, maxDimension: decodeDimension)
            case .full:
                image = await ThumbnailService.shared.fullImageAsync(for: clipID, data: data)
            }
            if let image {
                // ALWAYS persist the result, even on an instant cache hit. The
                // service NSCache (60MB / 200 entries, shared with the "-full"
                // tier where one 5K screenshot can evict the whole thumbnail
                // tier) can evict at any time; if the view kept nothing, a later
                // body render would find neither cache nor state and show a
                // permanent placeholder because the task id never changes.
                loaded = (clipID, image)
                decodeFailedClipID = nil
            } else {
                // A cancelled task (superseded id, view gone) also returns nil;
                // it must not record a failure the replacement task would have
                // to race to clear.
                guard !Task.isCancelled else { return }
                // Only flag failure when nothing is on screen for this clip, so
                // a stale-size image keeps showing rather than flipping to
                // failure text mid-resize.
                decodeFailedClipID = resolvedImage == nil ? clipID : nil
            }
        }
    }
}
