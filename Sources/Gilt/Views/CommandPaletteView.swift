import SwiftUI

/// The universal command palette: one search field over clipboard, notes,
/// meetings, reminders, and runnable actions. Hosted in a standalone borderless
/// window by `CommandPaletteWindowManager`; keyboard up/down/return/escape are
/// handled by that manager's event monitor so this view only renders state.
struct CommandPaletteView: View {
    @ObservedObject var model: CommandPaletteModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().overlay(Color.white.opacity(0.08))
            resultsList
            Divider().overlay(Color.white.opacity(0.06))
            footerHint
        }
        .frame(width: 640, height: 460)
        .background(paletteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _, _ in
            searchFocused = true
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            TextField("Search clips, notes, meetings, or type a command…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.95))
                .focused($searchFocused)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var resultsList: some View {
        if model.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.22))
                Text(L10n.string("common.noMatches", default: "No matches"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            if shouldShowHeader(at: index) {
                                sectionHeader(item.section)
                            }
                            CommandPaletteRow(item: item, isSelected: index == model.selectedIndex)
                                .id(index)
                                .onTapGesture { model.activate(item) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: CommandPaletteSection) -> some View {
        Text(section.title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.32))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }

    private var footerHint: some View {
        HStack(spacing: 14) {
            keyHint("↑↓", "Navigate")
            keyHint("↵", "Open")
            keyHint("esc", "Close")
            Spacer()
            if !model.items.isEmpty {
                Text("\(model.items.count) result\(model.items.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var paletteBackground: some View {
        LinearGradient(
            colors: [Color(white: 0.12), Color(white: 0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func shouldShowHeader(at index: Int) -> Bool {
        guard model.items.indices.contains(index) else { return false }
        if index == 0 { return true }
        return model.items[index].section != model.items[index - 1].section
    }
}
