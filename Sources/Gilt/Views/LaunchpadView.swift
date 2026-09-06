import SwiftUI

/// Shown in the grid view when there are no clips to display. Instead of an empty
/// void, it surfaces the handful of headline things Jack can do (with their
/// shortcuts) so dictation, meetings, notes, and the command palette get
/// discovered. Built from the shared `CommandCatalog`, so it never drifts from
/// what the palette offers.
struct LaunchpadView: View {
    @EnvironmentObject private var store: ClipboardStore

    private var features: [CommandAction] {
        CommandCatalog.actions(store: store).filter { $0.id != CommandCatalog.showClipboardID }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                paletteHero
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(features) { feature in
                        FeatureCard(feature: feature)
                    }
                }
                copyHint
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string("ui.welcome.to.jack", default: "Welcome to Jack"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            Text(L10n.string("ui.nothing.copied.yet.here.s.everything.jack.can.do", default: "Nothing copied yet. Here's everything Jack can do."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paletteHero: some View {
        Button {
            CommandPaletteWindowManager.shared.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.40, green: 0.52, blue: 0.96), Color(red: 0.48, green: 0.38, blue: 0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("menu.commandPalette", default: "Command Palette"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(L10n.string("ui.search.clips.notes.meetings.and.run.anything", default: "Search clips, notes, meetings, and run anything"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ShortcutPill(text: store.settings.commandPaletteShortcut.symbolString)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var copyHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Text("Copy anything and it lands here. Press \(store.settings.globalShortcut.symbolString) to summon Jack from any app.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

/// A single tappable feature tile on the launchpad.
private struct FeatureCard: View {
    let feature: CommandAction

    var body: some View {
        Button {
            feature.run()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle().fill(feature.accent.opacity(0.18))
                        Image(systemName: feature.systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(feature.accent.opacity(0.95))
                    }
                    .frame(width: 30, height: 30)
                    Spacer()
                    if let hint = feature.shortcutHint {
                        ShortcutPill(text: hint)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(feature.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Small key-cap pill used for shortcut hints on the launchpad.
private struct ShortcutPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.10)))
    }
}
