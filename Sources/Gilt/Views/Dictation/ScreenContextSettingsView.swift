import AppKit
import SwiftUI

/// Sub-page for the "screen context" dictation feature. Reads through the
/// shared `DictationStore` like the other Dictate sub-tabs.
///
/// Layout (top-to-bottom):
///   1. Master toggle.
///   2. Permission status row (Accessibility + Screen Recording).
///   3. Excluded-apps editor.
///
/// Capture mode is fixed at `.accessibilityWithOCRFallback` (the safest
/// default) — exposing the choice to end users was confusing, and the
/// fallback mode covers every app correctly without them having to think
/// about AX vs OCR.
struct ScreenContextSettingsView: View {
    @EnvironmentObject private var store: DictationStore
    @State private var pendingBundleID: String = ""
    @State private var permissionGranted: Bool = ScreenContextReader.hasScreenRecordingPermission()

    var body: some View {
        VStack(spacing: 18) {
            heroSection
            if store.settings.useScreenContext {
                permissionSection
                exclusionSection
            }
        }
        .onAppear {
            refreshPermission()
        }
    }

    // MARK: - Hero / master toggle

    private var heroSection: some View {
        SettingsSection(L10n.string("ui.screen.aware.dictation", default: "Screen-aware dictation")) {
            SettingsToggleRow(
                title: "Read my screen for context",
                subtitle: "Snapshots the frontmost window so transcription gets names, code symbols, and jargon right. On-device, never uploaded.",
                icon: "eye",
                isOn: Binding(
                    get: { store.settings.useScreenContext },
                    set: { newValue in
                        store.settings.useScreenContext = newValue
                        if newValue {
                            ScreenContextService.shared.ensurePermissionIfNeeded(
                                mode: store.settings.screenContextMode
                            )
                            refreshPermission()
                        }
                    }
                )
            )
        }
    }

    // MARK: - Permission

    private var permissionSection: some View {
        SettingsSection(L10n.string("ui.permissions", default: "Permissions")) {
            VStack(spacing: 0) {
                SettingsRow(
                    title: "Accessibility",
                    subtitle: "Required to read the frontmost app's text. Already used for paste-to-active-app.",
                    icon: "person.crop.circle.badge.checkmark"
                ) {
                    Text(AccessibilityService.isTrusted() ? "Granted" : "Needed")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                AccessibilityService.isTrusted()
                                    ? Color.green.opacity(0.18)
                                    : Color.orange.opacity(0.18)
                            )
                        )
                        .foregroundStyle(
                            AccessibilityService.isTrusted() ? Color.green : Color.orange
                        )
                }

                if store.settings.screenContextMode.needsScreenRecording {
                    SettingsDivider()

                    SettingsRow(
                        title: "Screen Recording",
                        subtitle: "Required only when Accessibility can't read the active app. Jack will ask the first time it's needed.",
                        icon: "rectangle.dashed.badge.record"
                    ) {
                        HStack(spacing: 8) {
                            Text(permissionGranted ? "Granted" : "Needed")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        permissionGranted
                                            ? Color.green.opacity(0.18)
                                            : Color.orange.opacity(0.18)
                                    )
                                )
                                .foregroundStyle(permissionGranted ? Color.green : Color.orange)
                            if !permissionGranted {
                                Button(L10n.string("ui.open.settings", default: "Open Settings")) {
                                    ScreenContextReader.openScreenRecordingSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Excluded apps

    private var exclusionSection: some View {
        SettingsSection(L10n.string("ui.apps.to.skip", default: "Apps to skip")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("ui.jack.won.t.read.these.apps.password..3b5a40", default: "Jack won't read these apps. Password managers are excluded by default."))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.settings.screenContextExcludedBundleIDs.isEmpty {
                    Text(L10n.string("ui.no.apps.excluded", default: "No apps excluded."))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedExclusions.enumerated()), id: \.element) { index, bundle in
                            excludedRow(bundle)
                            if index < sortedExclusions.count - 1 {
                                Rectangle()
                                    .fill(SettingsTheme.divider)
                                    .frame(height: 0.5)
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .background(SettingsTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
                    )
                }

                addFooter
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    /// Sorted alphabetically by resolved app name (case-insensitive) so the
    /// list reads as a directory of products, not a sea of reverse-DNS.
    private var sortedExclusions: [String] {
        store.settings.screenContextExcludedBundleIDs.sorted {
            ExclusionLookup.displayName(for: $0).localizedCaseInsensitiveCompare(
                ExclusionLookup.displayName(for: $1)
            ) == .orderedAscending
        }
    }

    /// One row in the excluded list — small leading icon (from the installed
    /// app if available, otherwise a neutral generic glyph), the friendly
    /// app name on top, the bundle ID dimmed and small underneath. Remove
    /// button is a hover-revealed × on the right.
    @ViewBuilder
    private func excludedRow(_ bundleID: String) -> some View {
        ExclusionRow(
            bundleID: bundleID,
            displayName: ExclusionLookup.displayName(for: bundleID),
            icon: ExclusionLookup.icon(for: bundleID)
        ) {
            store.settings.screenContextExcludedBundleIDs.remove(bundleID)
        }
    }

    /// Footer with the input + add buttons. Reworked so the input doesn't
    /// dominate — it's clearly a secondary affordance below the list.
    private var addFooter: some View {
        HStack(spacing: 8) {
            TextField("Add a bundle ID (com.example.app)", text: $pendingBundleID)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsTheme.border, lineWidth: 0.5)
                )
                .onSubmit { commitPendingExclusion() }

            Button(L10n.string("ui.add", default: "Add")) { commitPendingExclusion() }
                .disabled(pendingBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderless)
                .controlSize(.small)

            Button {
                if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                    store.settings.screenContextExcludedBundleIDs.insert(id)
                }
            } label: {
                Label(L10n.string("ui.use.frontmost.app", default: "Use frontmost app"), systemImage: "rectangle.inset.filled.on.rectangle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Add the app that's currently in front")
        }
    }

    private func commitPendingExclusion() {
        let trimmed = pendingBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.settings.screenContextExcludedBundleIDs.insert(trimmed)
        pendingBundleID = ""
    }

    // MARK: - Helpers

    private func refreshPermission() {
        permissionGranted = ScreenContextReader.hasScreenRecordingPermission()
    }
}

// MARK: - Exclusion row

/// One row in the "Apps to skip" list. Two-line layout: friendly app name on
/// top, bundle ID dimmed underneath, with a small app icon on the leading
/// side. The remove button only appears on hover so the resting state stays
/// quiet — same convention as note rows elsewhere in the app.
private struct ExclusionRow: View {
    let bundleID: String
    let displayName: String
    let icon: NSImage?
    let onRemove: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.textPrimary)
                    .lineLimit(1)
                Text(bundleID)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(SettingsTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
            .allowsHitTesting(hover)
            .help("Remove from list")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .background(hover ? SettingsTheme.divider.opacity(0.4) : .clear)
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            // Neutral fallback — a quiet rounded rectangle with the first
            // letter of the bundle ID's last component. Better than a
            // generic question-mark icon at row scale.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(SettingsTheme.divider)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(ExclusionLookup.fallbackInitial(for: bundleID))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(SettingsTheme.textSecondary)
                )
        }
    }
}

// MARK: - Bundle-ID lookup

/// Resolves bundle IDs to friendly names + icons via the local LaunchServices
/// database. Cheap, but cached so a list of 20 excluded apps doesn't probe
/// the disk on every render pass.
@MainActor
private enum ExclusionLookup {
    /// Cached `[bundleID: (name, icon)]`. `NSImage?` is a class type so the
    /// cache survives between renders without copying icon data.
    private static var cache: [String: (name: String, icon: NSImage?)] = [:]

    static func displayName(for bundleID: String) -> String {
        resolve(bundleID).name
    }

    static func icon(for bundleID: String) -> NSImage? {
        resolve(bundleID).icon
    }

    static func fallbackInitial(for bundleID: String) -> String {
        let component = bundleID.components(separatedBy: ".").last ?? bundleID
        return String(component.prefix(1)).uppercased()
    }

    private static func resolve(_ bundleID: String) -> (name: String, icon: NSImage?) {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            // Fall back to a pretty title from the bundle ID itself so the
            // first row always reads as a name, not a UUID.
            let derived = derivedName(from: bundleID)
            cache[bundleID] = (derived, nil)
            return (derived, nil)
        }
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = (name, icon)
        return (name, icon)
    }

    /// Pretty-print "com.agilebits.onepassword7" → "Onepassword7" so a
    /// not-installed app still gets a readable label.
    private static func derivedName(from bundleID: String) -> String {
        let last = bundleID.components(separatedBy: ".").last ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
