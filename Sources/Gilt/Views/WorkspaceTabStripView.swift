import SwiftUI

struct WorkspaceTabStripView: View {
    @EnvironmentObject private var store: ClipboardStore

    private var goldAccent: Color { Color(red: 0.83, green: 0.66, blue: 0.26) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(store.workspaceSession.tabs) { tab in
                        WorkspaceTabChip(
                            tab: tab,
                            active: store.workspaceSession.selectedTabID == tab.id,
                            accent: goldAccent,
                            select: { store.selectWorkspaceTab(tab.id) },
                            close: { store.closeWorkspaceTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.trailing, 16)
        }
        .padding(.top, 14)
        .background(
            ZStack {
                // Window drag happens here. Window is no longer movable by
                // background so Kanban cards / note content can receive drags.
                // (The .titled style mask also gives us an automatic drag
                // region for the top ~28pt — this handle complements it.)
                WindowDragHandle()
                LinearGradient(
                    colors: [Color.white.opacity(0.02), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
        )
    }
}

private struct WorkspaceTabChip: View {
    let tab: WorkspaceTab
    let active: Bool
    let accent: Color
    let select: () -> Void
    let close: () -> Void

    @State private var hover = false
    @State private var hoverClose = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Text(tab.title)
                    .lineLimit(1)
                    .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(active ? 0.98 : 0.58))
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(hoverClose ? 0.9 : 0.45))
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(hoverClose ? 0.12 : 0)))
                }
                .buttonStyle(.plain)
                .onHover { hoverClose = $0 }
                .opacity(active || hover ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack(alignment: .bottom) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 10
                    )
                    .fill(active ? Color.white.opacity(0.07) : (hover ? Color.white.opacity(0.03) : Color.clear))

                    Rectangle()
                        .fill(active ? accent : Color.clear)
                        .frame(height: 1.5)
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
