import SwiftUI

// MARK: - Design System Colors

enum SettingsTheme {
    // Primary accent is intentionally neutral now: Jack uses black-and-white chrome.
    static let primaryAccent = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let primaryAccentLight = Color(red: 0.25, green: 0.25, blue: 0.27)
    static let primaryAccentDark = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let gold = primaryAccent
    static let goldLight = primaryAccentLight
    static let goldDark = primaryAccentDark
    
    // Backgrounds
    static let background = Color(red: 0.98, green: 0.98, blue: 0.97)
    static let cardBackground = Color.white
    static let sidebarBackground = Color(red: 0.96, green: 0.96, blue: 0.95)
    
    // Text colors
    static let textPrimary = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.47)
    static let textTertiary = Color(red: 0.65, green: 0.65, blue: 0.67)
    
    // Borders and dividers
    static let border = Color(red: 0.88, green: 0.88, blue: 0.88)
    static let divider = Color(red: 0.92, green: 0.92, blue: 0.92)
    
    // Shadows
    static let cardShadow = Color.black.opacity(0.06)
}

// MARK: - Light Settings Section

struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .tracking(0.8)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(SettingsTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: SettingsTheme.cardShadow, radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
            )
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Light Settings Row

struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String?
    // When provided, the ENTIRE row becomes a single click target that runs
    // this action — not just the trailing control. Used by the radio/toggle
    // convenience rows so users can click anywhere on the option, not only the
    // small circle/switch. Rows with sliders, pickers, or their own buttons
    // leave this nil so those controls keep handling their own gestures.
    let onTap: (() -> Void)?
    let content: Content

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        if let onTap = onTap {
            Button(action: onTap) {
                rowContent
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            if let icon = icon {
                ZStack {
                    Circle()
                        .fill(SettingsTheme.primaryAccent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.primaryAccent)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Fill gaps (spacer, padding) so taps anywhere on the row register, and
        // give a quiet hover cue that the whole row is interactive.
        .background((onTap != nil && isHovering) ? SettingsTheme.primaryAccent.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Selectable (radio) Settings Row

/// A single-select option row whose entire surface is clickable, with a radio
/// indicator on the trailing edge. Replaces the old pattern of wrapping just a
/// tiny circle in a Button so users can click anywhere on the option to pick it.
struct SelectableSettingsRow: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let isSelected: Bool
    let onSelect: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, icon: icon, onTap: onSelect) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? SettingsTheme.gold : SettingsTheme.textTertiary)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Toggle Settings Row

/// An on/off option row whose entire surface toggles the value. The switch is a
/// non-interactive indicator (the row owns the gesture), so clicking anywhere on
/// the row — label, subtitle, or switch — flips it.
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let isDisabled: Bool
    @Binding var isOn: Bool

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isDisabled: Bool = false,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isDisabled = isDisabled
        self._isOn = isOn
    }

    var body: some View {
        // When disabled, drop the row-level tap so the option can't be flipped
        // and there's no hover affordance suggesting it can.
        SettingsRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            onTap: isDisabled ? nil : { isOn.toggle() }
        ) {
            Toggle("", isOn: .constant(isOn))
                .toggleStyle(GoldToggleStyle())
                .allowsHitTesting(false)
        }
        .disabled(isDisabled)
    }
}

// MARK: - Light Settings Divider

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsTheme.divider)
            .frame(height: 1)
            .padding(.horizontal, 18)
    }
}

// MARK: - Primary Toggle Style

struct PrimaryToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? SettingsTheme.primaryAccent : Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: 44, height: 26)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
                
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

typealias GoldToggleStyle = PrimaryToggleStyle

// MARK: - Sidebar Item

struct SettingsSidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? SettingsTheme.primaryAccent : SettingsTheme.textSecondary)
                    .frame(width: 20)

                Text(tab.label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SettingsTheme.primaryAccent.opacity(0.12))
                            .matchedGeometryEffect(id: "sidebarHighlight", in: namespace)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented Picker

struct SettingsSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let namespace: Namespace.ID
    let label: (Option) -> String
    let action: (Option) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    action(option)
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                                        .matchedGeometryEffect(id: "segmentedPickerHighlight", in: namespace)
                                }
                            }
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(SettingsTheme.sidebarBackground)
        )
    }
}

// MARK: - Light View Mode Card

struct LightViewModeCard: View {
    let mode: ViewMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? SettingsTheme.primaryAccent.opacity(0.1) : SettingsTheme.sidebarBackground)
                        .frame(width: 72, height: 56)
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? SettingsTheme.primaryAccent : SettingsTheme.textSecondary)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? SettingsTheme.primaryAccent : SettingsTheme.border, lineWidth: isSelected ? 2 : 1)
                )
                
                Text(mode.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SettingsTheme.textPrimary : SettingsTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Header with Greeting

struct SettingsHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(SettingsTheme.textPrimary)

            Text(SettingsCopy.headerSubtitle())
                .font(.system(size: 14))
                .foregroundStyle(SettingsTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
    
    private var greetingText: String {
        SettingsCopy.greeting()
    }
}
