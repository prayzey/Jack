import SwiftUI

/// A picker tile for one `DictationPillTheme` — renders a tiny live-style
/// preview of the pill with the theme's palette applied, plus the theme name
/// underneath. Tapping the parent commits the selection.
///
/// The preview uses a static 7×3 grid (no audio data) with three columns lit
/// to a stair-step pattern so each swatch shows off the lit + dim cell colors
/// against the pill background.
struct DictationPillThemeSwatch: View {
    let theme: DictationPillTheme
    let isSelected: Bool

    private var palette: DictationPillPalette { theme.palette }

    var body: some View {
        VStack(spacing: 8) {
            pillPreview
            Text(theme.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SettingsTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? SettingsTheme.primaryAccent : SettingsTheme.divider,
                    lineWidth: isSelected ? 1.6 : 0.5
                )
        )
        // Rasterize the entire swatch into a single offscreen layer so the
        // grid's 21 cells (and the pill's gradient + shadow) get composited
        // exactly once at first render. Subsequent scroll ticks just blit
        // the cached texture instead of recomposing the layer tree —
        // dramatically faster when 20+ swatches are on screen at once.
        .drawingGroup()
    }

    private var pillPreview: some View {
        HStack(spacing: 6) {
            staticGrid
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.pillTop, palette.pillBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.pillBorder, lineWidth: 0.6)
        )
        .shadow(color: palette.pillShadow.opacity(0.7), radius: 4, y: 2)
        .frame(maxWidth: .infinity)
    }

    /// A frozen 7×3 grid showing a stair-step lit pattern so the swatch
    /// previews both the lit + dim cell colors at a glance.
    ///
    /// No per-cell shadow — 5pt squares can't show a soft glow legibly
    /// anyway, and the per-cell shadow was the main reason scrolling the
    /// theme grid lagged (21 separate shadow ops × 20+ swatches).
    private var staticGrid: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(isLit(row: row, col: col) ? palette.gridLit : palette.gridDim)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Stair pattern: rightmost columns light their top cell; left columns
    /// only light the bottom. Visually mirrors a voice peaking at the
    /// "now" edge of the rolling waveform.
    private func isLit(row: Int, col: Int) -> Bool {
        let threshold = 2 - col / 3  // col 0..2 → 2, 3..5 → 1, 6 → 0
        return row >= threshold
    }
}
