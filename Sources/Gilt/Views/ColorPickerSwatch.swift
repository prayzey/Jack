import SwiftUI

/// Row of 7 preset token circles + 1 native ColorPicker circle at the end.
/// Used in the Settings Folders tab for accent/fill/text color selection.
struct ColorPickerSwatch: View {
    let selected: ResolvedColor
    let onSelectToken: (FolderColorToken) -> Void
    let onSelectHex: (String) -> Void

    @State private var pickerColor: Color = .gray

    var body: some View {
        HStack(spacing: 5) {
            ForEach(FolderColorToken.allCases, id: \.self) { token in
                let isSelected: Bool = {
                    if case .token(let t) = selected { return t == token }
                    return false
                }()

                Button {
                    onSelectToken(token)
                } label: {
                    Circle()
                        .fill(token.color)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }

            // Native color picker circle
            let isCustomSelected: Bool = {
                if case .hex = selected { return true }
                return false
            }()

            ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isCustomSelected ? 0.8 : 0), lineWidth: 2)
                        .frame(width: 18, height: 18)
                )
                .onChange(of: pickerColor) { _, newColor in
                    onSelectHex(newColor.hexString)
                }
                .onAppear {
                    if case .hex(let h) = selected {
                        pickerColor = Color(hex: h)
                    }
                }
        }
    }
}
