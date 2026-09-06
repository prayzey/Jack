import SwiftUI

/// Compact inline gradient editor: preview bar + two ColorPickers (start/end) + angle slider.
struct GradientPickerView: View {
    @Binding var spec: GradientSpec

    @State private var color1: Color
    @State private var color2: Color
    @State private var angle: Double

    init(spec: Binding<GradientSpec>) {
        _spec = spec
        let s = spec.wrappedValue
        _color1 = State(initialValue: Color(hex: s.color1))
        _color2 = State(initialValue: Color(hex: s.color2))
        _angle = State(initialValue: s.angle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Gradient preview bar
            RoundedRectangle(cornerRadius: 6)
                .fill(spec.linearGradient)
                .frame(height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            HStack(spacing: 12) {
                // Start color
                VStack(spacing: 2) {
                    Text(L10n.string("ui.start", default: "Start"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    ColorPicker("", selection: $color1, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 22, height: 22)
                }

                // End color
                VStack(spacing: 2) {
                    Text(L10n.string("ui.end", default: "End"))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    ColorPicker("", selection: $color2, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 22, height: 22)
                }

                // Angle slider
                VStack(alignment: .leading, spacing: 2) {
                    Text("Angle \(Int(angle))°")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Slider(value: $angle, in: 0...360, step: 15)
                        .frame(minWidth: 80)
                }
            }
        }
        .onChange(of: color1) { _, newValue in
            spec.color1 = newValue.hexString
        }
        .onChange(of: color2) { _, newValue in
            spec.color2 = newValue.hexString
        }
        .onChange(of: angle) { _, newValue in
            spec.angle = newValue
        }
    }
}
