import SwiftUI

/// Builds its content only when SwiftUI asks for this view's body.
///
/// Wrap `.contextMenu` contents in this. A plain `.contextMenu { menu }` runs the
/// menu builder inside the parent's body, so every card computed its menu
/// (full clip scans, image data) on every store change, even with no menu open.
/// With hundreds of cards that froze the main thread for seconds.
struct DeferredView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}
