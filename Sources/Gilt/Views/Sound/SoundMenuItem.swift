import SwiftUI

/// A full-width row at the bottom of the sound panel that behaves like a
/// macOS menu item: icon, title, optional detail, and a hover highlight.
/// Pass `trailing` for a switch instead of making the whole row a button.
struct SoundMenuItem<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovering = false

    var body: some View {
        let row = HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering && action != nil ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }

        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

extension SoundMenuItem where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String? = nil, action: (() -> Void)?) {
        self.init(symbol: symbol, title: title, detail: detail, action: action) { EmptyView() }
    }
}
