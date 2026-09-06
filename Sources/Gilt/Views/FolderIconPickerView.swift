import AppKit
import SwiftUI

struct FolderIconPickerView: View {
    let folder: ClipFolderModel
    let accentColor: Color
    var onSelectIcon: (FolderIcon?) -> Void
    var useLightTheme: Bool = false

    @State private var customGlyph = ""
    @FocusState private var glyphFieldFocused: Bool

    private let presetSymbols = [
        "folder", "bookmark", "star", "heart", "bolt", "paperplane",
        "tray.full", "briefcase", "terminal", "paintpalette", "music.note", "lock"
    ]
    
    // Theme-aware colors
    private var textPrimary: Color { useLightTheme ? SettingsTheme.textPrimary : .white }
    private var textSecondary: Color { useLightTheme ? SettingsTheme.textSecondary : .white.opacity(0.6) }
    private var textTertiary: Color { useLightTheme ? SettingsTheme.textTertiary : .white.opacity(0.35) }
    private var pillBackground: Color { useLightTheme ? SettingsTheme.sidebarBackground : Color.white.opacity(0.04) }
    private var pillBackgroundSelected: Color { useLightTheme ? SettingsTheme.gold.opacity(0.15) : Color.white.opacity(0.15) }
    private var iconCircleBackground: Color { useLightTheme ? SettingsTheme.sidebarBackground : Color.white.opacity(0.04) }
    private var iconCircleBackgroundSelected: Color { useLightTheme ? SettingsTheme.gold.opacity(0.12) : Color.white.opacity(0.14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if folder.smartCategory != nil {
                    iconButton(L10n.string("ui.default", default: "Default"), selected: folder.folderIconRaw == nil) {
                        customGlyph = ""
                        onSelectIcon(nil)
                    }
                } else {
                    iconButton(L10n.string("backgroundWallpaper.none.label", default: "None"), selected: folder.customFolderIcon == nil) {
                        customGlyph = ""
                        onSelectIcon(nil)
                    }
                }

                ForEach(presetSymbols, id: \.self) { symbol in
                    iconCircle(selected: folder.customFolderIcon == .symbol(symbol)) {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accentColor)
                    } action: {
                        customGlyph = ""
                        onSelectIcon(.symbol(symbol))
                    }
                }
            }

            Button {
                glyphFieldFocused = true
                DispatchQueue.main.async {
                    NSApp.orderFrontCharacterPalette(nil)
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(useLightTheme ? textPrimary.opacity(0.7) : .white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(accentColor.opacity(useLightTheme ? 0.12 : 0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(useLightTheme ? accentColor.opacity(0.25) : .white.opacity(0.12), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help("Open emoji picker")

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("ui.optional.manual.entry", default: "Optional manual entry"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(textTertiary)
                    .tracking(0.4)

                TextField("Paste an emoji or 1-2 characters", text: $customGlyph)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: 220)
                    .focused($glyphFieldFocused)
                    .onChange(of: customGlyph) { _, newValue in
                        let limited = String(newValue.prefix(2))
                        if limited != newValue {
                            customGlyph = limited
                            return
                        }
                        let trimmed = limited.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSelectIcon(trimmed.isEmpty ? nil : .glyph(trimmed))
                    }
            }
        }
        .onAppear {
            if case .glyph(let glyph) = folder.customFolderIcon {
                customGlyph = glyph
            }
        }
        .onChange(of: folder.folderIconRaw) { _, _ in
            if case .glyph(let glyph) = folder.customFolderIcon {
                customGlyph = glyph
            } else {
                customGlyph = ""
            }
        }
    }

    private func iconButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? textPrimary : textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? pillBackgroundSelected : pillBackground))
        }
        .buttonStyle(.plain)
    }

    private func iconCircle<Content: View>(
        selected: Bool,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(selected ? iconCircleBackgroundSelected : iconCircleBackground)
                )
                .overlay(
                    Circle()
                        .strokeBorder(accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.4)
                )
        }
        .buttonStyle(.plain)
    }
}
