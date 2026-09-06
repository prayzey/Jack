import SwiftUI

/// Per-pane scrim levels that keep the workspace readable over any wallpaper.
///
/// The workspace paints a wallpaper full-bleed under everything via
/// `WorkspaceSurfaceBackground`, but each column in the three-pane layout sits
/// on top of that wallpaper and needs its own dark surface so titles,
/// eyebrows, and labels never lose contrast against bright images.
///
/// Three intensities are tuned for the three-pane layout:
/// - `.strong` — sidebar. Navigation MUST always be readable. ~92%/94%.
/// - `.medium` — list column. Wallpaper hints through; rows stay legible. ~80%/82%.
/// - `.light`  — detail column. Wallpaper is most visible here; the lighter
///   scrim still gives body text a quiet surface to land on. ~62%/70%.
///
/// Why a gradient instead of a solid: a vertical gradient (slightly darker at
/// the bottom) gives the surface a tiny sense of weight without making it
/// look like a flat plate. The `.ultraThinMaterial` underneath picks up a
/// subtle wash of wallpaper colour so the room still feels like one room.
enum WorkspaceScrimLevel {
    case strong, medium, light

    var topOpacity: Double {
        switch self {
        case .strong: return 0.92
        case .medium: return 0.80
        case .light:  return 0.62
        }
    }

    var bottomOpacity: Double {
        switch self {
        case .strong: return 0.94
        case .medium: return 0.82
        case .light:  return 0.70
        }
    }
}

struct WorkspaceScrim: ViewModifier {
    let level: WorkspaceScrimLevel

    // Cool near-black tuned to read as "panel" rather than "void". A pure
    // #000 scrim looks like a hole punched in the wallpaper; this dark navy
    // sits more naturally next to coloured imagery.
    private var topColor: Color {
        Color(red: 0.045, green: 0.055, blue: 0.075).opacity(level.topOpacity)
    }
    private var bottomColor: Color {
        Color(red: 0.030, green: 0.040, blue: 0.060).opacity(level.bottomOpacity)
    }

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                // Native vibrancy lets the wallpaper colour wash through
                // subtly while giving text a frosted base to land on.
                Rectangle().fill(.ultraThinMaterial)

                // The dark gradient on top is what guarantees contrast.
                LinearGradient(
                    colors: [topColor, bottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

extension View {
    /// Applies a tuned dark scrim so this pane is readable over any workspace
    /// wallpaper. See `WorkspaceScrimLevel` for the three intensities.
    func workspaceScrim(_ level: WorkspaceScrimLevel) -> some View {
        modifier(WorkspaceScrim(level: level))
    }
}
