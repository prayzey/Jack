import SwiftUI

/// Horizontal scroll of saved color/gradient presets. Tap to apply, right-click to delete.
struct PresetLibraryView: View {
    let presets: [ColorPreset]
    let onApply: (ColorPreset) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        if presets.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presets) { preset in
                        presetCircle(preset)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func presetCircle(_ preset: ColorPreset) -> some View {
        let fillStyle: AnyShapeStyle = {
            if let grad = GradientSpec(rawString: preset.rawValue) {
                return AnyShapeStyle(grad.linearGradient)
            } else {
                let color = ResolvedColor(rawString: preset.rawValue).color
                return AnyShapeStyle(color)
            }
        }()

        Button {
            onApply(preset)
        } label: {
            Circle()
                .fill(fillStyle)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .help(preset.name)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(preset.id)
            } label: {
                Label(L10n.string("ui.delete.preset", default: "Delete Preset"), systemImage: "trash")
            }
        }
    }
}
