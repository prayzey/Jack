import AppKit
import SwiftUI

/// Exact edge/corner resize overlay for custom macOS windows.
///
/// Normal titled macOS windows get these hit zones from AppKit. Borderless
/// windows do not, so Quick Note and Workspace need to draw their own invisible
/// handles. Spacer-based layout keeps the middle of the window click-through;
/// only the narrow edge strips and corner boxes can intercept the mouse.
struct WindowFrameResizeOverlay: View {
    let edgeThickness: CGFloat
    let topEdgeThickness: CGFloat
    let cornerSize: CGFloat
    let minSize: CGSize
    var maxSize: CGSize = WindowResizeHandleMetrics.unboundedSize
    /// Width of a click-through gap punched into the center of the top edge.
    /// The window's drag region (title-bar grip) lives directly under the top
    /// edge, so without a gap the top-center resizes when the user meant to
    /// move the window. Leaving the corners + side segments as resize zones,
    /// the center falls through to the drag handle. 0 keeps a single full-width
    /// top edge (default for callers that don't host a top drag grip there).
    var topEdgeCenterGap: CGFloat = 0
    var onFrameChanged: ((NSRect) -> Void)? = nil
    var onResizeFinished: ((NSRect) -> Void)? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: cornerSize)
                        .allowsHitTesting(false)
                    if topEdgeCenterGap > 0 {
                        handle(.top)
                            .frame(height: topEdgeThickness)
                        Color.clear
                            .frame(width: topEdgeCenterGap)
                            .allowsHitTesting(false)
                        handle(.top)
                            .frame(height: topEdgeThickness)
                    } else {
                        handle(.top)
                            .frame(height: topEdgeThickness)
                    }
                    Color.clear
                        .frame(width: cornerSize)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: cornerSize)
                        .allowsHitTesting(false)
                    handle(.bottom)
                        .frame(height: edgeThickness)
                    Color.clear
                        .frame(width: cornerSize)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: cornerSize)
                        .allowsHitTesting(false)
                    handle(.left)
                        .frame(width: edgeThickness)
                    Color.clear
                        .frame(height: cornerSize)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: cornerSize)
                        .allowsHitTesting(false)
                    handle(.right)
                        .frame(width: edgeThickness)
                    Color.clear
                        .frame(height: cornerSize)
                        .allowsHitTesting(false)
                }
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    handle(.topLeft)
                        .frame(width: cornerSize, height: cornerSize)
                    Spacer(minLength: 0)
                    handle(.topRight)
                        .frame(width: cornerSize, height: cornerSize)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    handle(.bottomLeft)
                        .frame(width: cornerSize, height: cornerSize)
                    Spacer(minLength: 0)
                    handle(.bottomRight)
                        .frame(width: cornerSize, height: cornerSize)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(_ edge: WindowResizeEdge) -> some View {
        WindowFrameResizeHandle(
            edge: edge,
            minSize: minSize,
            maxSize: maxSize,
            onFrameChanged: onFrameChanged,
            onResizeFinished: onResizeFinished
        )
    }
}
