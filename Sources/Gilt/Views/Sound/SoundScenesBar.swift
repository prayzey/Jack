import SwiftUI

/// Saved sound setups as chips that wrap onto new lines: click one to apply
/// it, "Save Scene" to keep the current levels under a name, right-click a
/// chip to delete it.
struct SoundScenesBar: View {
    let scenes: [SoundScene]
    let currentID: SoundScene.ID?
    let onApply: (SoundScene.ID) -> Void
    let onSave: (String) -> Void
    let onDelete: (SoundScene.ID) -> Void

    private static let chipHeight: CGFloat = 20

    @State private var isNaming = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        SoundFlowLayout(spacing: 5) {
            ForEach(scenes) { scene in
                let isCurrent = scene.id == currentID
                Button { onApply(scene.id) } label: {
                    Text(scene.name)
                        .font(.system(size: 11, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .frame(height: Self.chipHeight)
                        .background(Capsule().fill(Color.primary.opacity(isCurrent ? 0.16 : 0.06)))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(L10n.string("ui.sound.scene.delete", default: "Delete Scene"), role: .destructive) { onDelete(scene.id) }
                }
            }
            if isNaming {
                TextField(L10n.string("ui.sound.scene.name.placeholder", default: "Focus"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .focused($nameFocused)
                    .frame(width: 84)
                    .padding(.horizontal, 8)
                    .frame(height: Self.chipHeight)
                    .background(Capsule().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
                    .onSubmit(save)
                    .onExitCommand { isNaming = false }
                    .onAppear { nameFocused = true }
            } else {
                Button {
                    name = ""
                    isNaming = true
                } label: {
                    // Once there are scenes, a bare "+" keeps them on one line.
                    Label(L10n.string("ui.sound.scene.save", default: "Save Scene"), systemImage: "plus")
                        .labelStyle(scenes.isEmpty ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                        .font(.system(size: 11, weight: .medium))
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, scenes.isEmpty ? 8 : 6)
                        .frame(minWidth: Self.chipHeight)
                        .frame(height: Self.chipHeight)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(L10n.string("ui.sound.scene.save.help", default: "Save the current app volumes so you can switch back to them"))
            }
        }
        .animation(.snappy(duration: 0.18), value: isNaming)
        .animation(.snappy(duration: 0.18), value: scenes)
    }

    private func save() {
        onSave(name)
        isNaming = false
    }
}

/// Lets the save chip switch between icon-only and icon-and-title.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
