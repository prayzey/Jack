import SwiftUI

/// Dedicated Settings tab that gathers every preference related to Jack's
/// menu bar item: visibility, custom text, formatting, and the keyboard /
/// interaction tips that live alongside those toggles. Keeping this in its
/// own view (a) shrinks the giant SettingsView.swift, (b) gives the user a
/// focused place to discover all menu bar behaviors in one screen.
struct MenuBarSettingsTab: View {
    @EnvironmentObject private var store: ClipboardStore

    /// Live-updating focus tracker for the text field so the toolbar buttons
    /// can keep typing experience smooth (re-focus the field after a wrap so
    /// the user can keep editing without an extra click).
    @FocusState private var textFieldFocused: Bool

    /// Lightweight Combine-less state for wallpaper drag preview while the
    /// user is interactively positioning a wallpaper — committed back to
    /// settings when the drag ends.
    @StateObject private var wallpaperPreviewState = WallpaperPreviewState()

    private var popoverAppearanceBinding: Binding<QuickNoteAppearance> {
        Binding(
            get: { store.settings.menuBarPopoverAppearance },
            set: { store.settings.menuBarPopoverAppearance = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSection(L10n.string("ui.menu.bar.item", default: "Menu Bar Item")) {
                showInMenuBarRow
                SettingsDivider()
                customTextToggleRow
                if showCustomTextEnabled {
                    customTextEditor
                    SettingsDivider()
                    menuBarTextColorRow
                }
            }

            popoverDisplaySection

            popoverAppearanceSection

            SettingsSection(L10n.string("ui.tips", default: "Tips")) {
                tipRow(
                    icon: "hand.draw",
                    title: "Move it around",
                    body: "Hold ⌘ (Command) and drag the menu bar item to reposition it. macOS remembers where you put it."
                )
                SettingsDivider()
                tipRow(
                    icon: "cursorarrow.click.badge.clock",
                    title: "Shift-click to clear",
                    body: "Hold Shift and click the menu bar item to clear the custom text instantly."
                )
                SettingsDivider()
                tipRow(
                    icon: "rectangle.and.text.magnifyingglass",
                    title: "Hover to see the full text",
                    body: "If your text is longer than the menu bar can show, hover over the item to see the full string."
                )
                SettingsDivider()
                tipRow(
                    icon: "square.and.arrow.down",
                    title: "Drag text onto it",
                    body: "Drag selected text from any app and drop it on the menu bar item to set it as your text."
                )
                SettingsDivider()
                tipRow(
                    icon: "square.and.arrow.up",
                    title: "Send from any app",
                    body: "Select text in any app, right-click → Services → \"Send to \(AppBrand.displayName)\" to set it."
                )
            }
        }
    }

    // MARK: - Popover appearance

    /// The customization the user asked for: own theme, own wallpaper, own
    /// opacity, separate from Quick Note. Reuses Quick Note's appearance
    /// type because the rendering pipeline already speaks that vocabulary,
    /// but it's a totally independent stored value.
    private var popoverAppearanceSection: some View {
        SettingsSection(L10n.string("ui.popover.appearance", default: "Popover Appearance")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("ui.style.how.the.menu.bar.editor.popove.8f46c4", default: "Style how the menu bar editor popover looks. This is independent of your Quick Note theme."))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                QuickNoteStylePickerView(selection: popoverAppearanceBinding.style)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)

            SettingsDivider()

            SettingsRow(
                title: "Card Opacity",
                subtitle: "How solid or translucent the popover surface feels",
                icon: "circle.lefthalf.filled"
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsTheme.textTertiary)
                    Slider(value: popoverAppearanceBinding.surfaceOpacity, in: 0.55...1)
                        .tint(SettingsTheme.gold)
                        .frame(width: 150)
                    Image(systemName: "square.dashed")
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsTheme.textTertiary)
                }
            }

            SettingsDivider()

            wallpaperRow

            if store.settings.menuBarPopoverAppearance.backgroundWallpaper != .none {
                SettingsDivider()
                cardOverWallpaperRow
            }

            SettingsDivider()

            resetToDefaultsRow
        }
    }

    private var wallpaperRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(SettingsTheme.primaryAccent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SettingsTheme.primaryAccent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("ui.wallpaper", default: "Wallpaper"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Text(L10n.string("ui.pick.a.background.image.for.the.editor.popover", default: "Pick a background image for the editor popover"))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                }

                Spacer()
            }

            SurfaceWallpaperSettingsView(
                wallpaper: popoverAppearanceBinding.backgroundWallpaper,
                customFilename: popoverAppearanceBinding.customWallpaperFilename,
                offsetX: popoverAppearanceBinding.wallpaperOffsetX,
                offsetY: popoverAppearanceBinding.wallpaperOffsetY,
                previewState: wallpaperPreviewState,
                previewAspectRatio: 16.0 / 10.0,
                previewTint: .clear,
                onPickCustom: pickCustomWallpaper
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var cardOverWallpaperRow: some View {
        SettingsRow(
            title: "Card Over Wallpaper",
            subtitle: "How much the tinted surface shows over the wallpaper",
            icon: "photo.on.rectangle"
        ) {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsTheme.textTertiary)
                Slider(value: popoverAppearanceBinding.cardOpacityOverWallpaper, in: 0...1)
                    .tint(SettingsTheme.gold)
                    .frame(width: 150)
                Image(systemName: "square.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsTheme.textTertiary)
            }
        }
    }

    private var resetToDefaultsRow: some View {
        SettingsRow(
            title: "Reset Appearance",
            subtitle: "Revert popover style, wallpaper, and opacity to defaults",
            icon: "arrow.counterclockwise"
        ) {
            Button(L10n.string("ui.reset", default: "Reset")) {
                var defaults = QuickNoteAppearance()
                defaults.surfaceOpacity = 0.92
                defaults.paperType = .blank
                store.settings.menuBarPopoverAppearance = defaults
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    /// Opens the standard macOS open panel for picking an image. Matches the
    /// flow Quick Note uses so the file ends up in the same custom-wallpaper
    /// directory and can be loaded by `BackgroundWallpaper.loadImage`.
    private func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        if panel.runModalInFront() == .OK, let url = panel.url {
            if let filename = BackgroundWallpaper.importCustomImage(from: url) {
                var appearance = store.settings.menuBarPopoverAppearance
                appearance.backgroundWallpaper = .custom
                appearance.customWallpaperFilename = filename
                store.settings.menuBarPopoverAppearance = appearance
            }
        }
    }

    // MARK: - Rows

    private var showInMenuBarRow: some View {
        SettingsToggleRow(
            title: "Show in menu bar",
            subtitle: "Display \(AppBrand.displayName) in the menu bar",
            icon: "menubar.rectangle",
            isDisabled: store.settings.hideFromDock,
            isOn: $store.settings.showInMenuBar
        )
    }

    private var customTextToggleRow: some View {
        SettingsToggleRow(
            title: "Custom text",
            subtitle: "Show your own text instead of the \(AppBrand.displayName) icon",
            icon: "textformat",
            isDisabled: !store.settings.showInMenuBar,
            isOn: $store.settings.menuBarShowCustomText
        )
    }

    private var showCustomTextEnabled: Bool {
        store.settings.menuBarShowCustomText && store.settings.showInMenuBar
    }

    // Align with SettingsRow's internal padding (horizontal: 18) so the
    // editor block sits inside the section card cleanly instead of slamming
    // against the rounded corner.
    private var customTextEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Live preview — what the user types renders here exactly like
            // it will appear in the menu bar (markdown applied, truncated,
            // sitting on a dark menu-bar-style strip). Saves the user from
            // glancing at their actual menu bar every keystroke.
            MenuBarTextPreview(
                text: store.settings.menuBarCustomText,
                placeholder: "Your menu bar text will appear here",
                textColor: menuBarPreviewTextColor
            )

            formattingToolbar

            TextField(
                "e.g. Focus: ship v1.2",
                text: $store.settings.menuBarCustomText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(SettingsTheme.textPrimary)
            .focused($textFieldFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.border, lineWidth: 1))

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("Up to 30 characters. Supports **bold**, *italic*, and ~~strikethrough~~. Use the buttons above or type the markdown yourself.")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Popover Display (message mode)

    /// Toggle + textarea for "message mode" — when on, the popover stops
    /// being an editor and turns into a static, read-only message box.
    /// Independent of `menuBarCustomText` so the user can keep a short
    /// label in the bar and a longer note in the popover.
    private var popoverDisplaySection: some View {
        SettingsSection(L10n.string("ui.popover.display", default: "Popover Display")) {
            popoverTextColorRow
            SettingsDivider()
            popoverAutoTextColorRow
            SettingsDivider()
            SettingsToggleRow(
                title: "Use popover as a message box",
                subtitle: "Replace the input field with a static message. The menu bar text stays editable above",
                icon: "text.bubble",
                isOn: $store.settings.menuBarPopoverShowMessage
            )

            if store.settings.menuBarPopoverShowMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("ui.popover.message", default: "Popover message"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .tracking(0.6)
                        .textCase(.uppercase)

                    TextEditor(text: $store.settings.menuBarPopoverMessage)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsTheme.textPrimary)
                        .frame(minHeight: 90)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.border, lineWidth: 1))

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Supports markdown (**bold**, *italic*, ~~strikethrough~~). The Settings + More buttons stay visible at the bottom of the popover so you're never stuck.")
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
    }

    private var popoverPreviewTextColor: Color {
        store.settings.resolvedMenuBarPopoverTextColor(
            appearance: store.settings.menuBarPopoverAppearance
        )
    }

    private var popoverTextColorRow: some View {
        SettingsRow(
            title: "Popover text color",
            subtitle: popoverTextColorSubtitle,
            icon: "paintpalette"
        ) {
            HStack(spacing: 10) {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { popoverPreviewTextColor },
                        set: { store.settings.menuBarPopoverTextColorHex = $0.hexString }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 36)

                if store.settings.menuBarPopoverTextColorHex != nil {
                    Button(L10n.string("ui.reset", default: "Reset")) {
                        store.settings.menuBarPopoverTextColorHex = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var popoverTextColorSubtitle: String {
        if store.settings.menuBarPopoverTextColorHex != nil {
            return "Custom. Tap the swatch to change or clear"
        }
        if store.settings.menuBarPopoverAppearance.autoTextColorOnWallpaper {
            return "Auto-matched to the popover background. Pick a swatch to override"
        }
        return "Labels, input field, and hints in the menu bar popover"
    }

    private var popoverAutoTextColorRow: some View {
        SettingsToggleRow(
            title: "Auto text color",
            subtitle: "Pick light or dark text from the popover wallpaper, style, and card opacity",
            icon: "wand.and.stars",
            isDisabled: store.settings.menuBarPopoverTextColorHex != nil,
            isOn: popoverAppearanceBinding.autoTextColorOnWallpaper
        )
    }

    private var menuBarPreviewTextColor: Color {
        if let hex = store.settings.menuBarTextColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return .white
    }

    private var menuBarTextColorRow: some View {
        SettingsRow(
            title: "Menu Bar Text Color",
            subtitle: store.settings.menuBarTextColorHex == nil
                ? "Uses the system menu bar colour"
                : "Custom. Tap the swatch to change or clear",
            icon: "character.cursor.ibeam"
        ) {
            HStack(spacing: 10) {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { menuBarPreviewTextColor },
                        set: { store.settings.menuBarTextColorHex = $0.hexString }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 36)

                if store.settings.menuBarTextColorHex != nil {
                    Button(L10n.string("ui.reset", default: "Reset")) {
                        store.settings.menuBarTextColorHex = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Formatting toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 8) {
            formatButton(
                symbol: "bold",
                accessibilityLabel: "Bold",
                wrapper: "**"
            )
            formatButton(
                symbol: "italic",
                accessibilityLabel: "Italic",
                wrapper: "*"
            )
            formatButton(
                symbol: "strikethrough",
                accessibilityLabel: "Strikethrough",
                wrapper: "~~"
            )
            Spacer()
            Button {
                store.settings.menuBarCustomText = ""
                textFieldFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Clear text")
            .disabled(store.settings.menuBarCustomText.isEmpty)
        }
    }

    private func formatButton(
        symbol: String,
        accessibilityLabel: String,
        wrapper: String
    ) -> some View {
        Button {
            applyWrapper(wrapper)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(SettingsTheme.border, lineWidth: 1)
                )
                .foregroundStyle(SettingsTheme.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    /// Wrap the whole current text (or insert wrappers at the end if empty)
    /// with the given markdown delimiter. This is simpler than tracking a
    /// selection range across SwiftUI TextField focus changes, and matches
    /// non-technical users' expectation: "click bold, my text is bold."
    private func applyWrapper(_ wrapper: String) {
        let current = store.settings.menuBarCustomText
        if current.isEmpty {
            // Insert delimiters so the user can type between them.
            store.settings.menuBarCustomText = wrapper + wrapper
        } else if current.hasPrefix(wrapper) && current.hasSuffix(wrapper) && current.count > wrapper.count * 2 {
            // Already wrapped — strip the delimiters off so the button acts
            // like a real toggle.
            let stripped = current
                .dropFirst(wrapper.count)
                .dropLast(wrapper.count)
            store.settings.menuBarCustomText = String(stripped)
        } else {
            store.settings.menuBarCustomText = wrapper + current + wrapper
        }
        textFieldFocused = true
    }

    // MARK: - Tip rows

    private func tipRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(SettingsTheme.primaryAccent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.primaryAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// MARK: - Live preview

/// Renders the user's menu bar text the same way it will appear in the
/// macOS menu bar — dark strip background, the system menu bar font,
/// markdown styling for **bold**, *italic*, ~~strikethrough~~, truncated
/// at 30 characters with an ellipsis. Lives in Settings so the user can
/// iterate on their text without bouncing eyes up to the actual menu bar.
struct MenuBarTextPreview: View {
    let text: String
    let placeholder: String
    var textColor: Color = .white

    private static let maxLength = 30

    /// Trim + truncate exactly as `MenuBarTextItemController` does so the
    /// preview can't drift from the real rendering.
    private var displayString: String {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count > Self.maxLength else { return stripped }
        let endIndex = stripped.index(stripped.startIndex, offsetBy: Self.maxLength - 1)
        return stripped[..<endIndex] + "\u{2026}"
    }

    /// SwiftUI's `Text` accepts an `AttributedString` parsed from markdown,
    /// which gives us bold/italic/strikethrough rendering with the same
    /// inline grammar the real menu bar uses. If parsing fails (malformed
    /// markdown mid-typing) we fall back to plain text so the preview
    /// never disappears on the user.
    private var renderedText: Text {
        let raw = displayString
        if raw.isEmpty {
            return Text(placeholder)
                .foregroundColor(textColor.opacity(0.35))
        }
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed).foregroundColor(textColor)
        }
        return Text(raw).foregroundColor(textColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("ui.preview", default: "PREVIEW"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.8)

            // Mock menu bar strip — narrow, dark, full-width, with the
            // text positioned roughly where it sits in a real status item.
            HStack(spacing: 12) {
                renderedText
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Couple of decorative system glyphs on the right to make
                // it visually obvious this is "a menu bar," not just any
                // text strip.
                Image(systemName: "battery.75")
                Image(systemName: "wifi")
                Image(systemName: "magnifyingglass")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.10), Color(white: 0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
