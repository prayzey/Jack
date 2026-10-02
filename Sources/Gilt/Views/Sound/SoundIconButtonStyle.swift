import SwiftUI

/// Small round glyph button for the sound panel (mute, play, next): quiet at
/// rest, a soft circle on hover, a firmer one while pressed.
struct SoundIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        SoundIconButtonBody(configuration: configuration, isActive: isActive)
    }
}

private struct SoundIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isActive: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(Color.primary.opacity(
                    configuration.isPressed ? 0.16 : (isHovering || isActive ? 0.08 : 0)
                ))
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}
