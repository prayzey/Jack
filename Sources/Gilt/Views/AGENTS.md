# Views Directory

This directory contains all SwiftUI views for Jack (Swift module `Gilt`). The app supports four distinct view modes, each with its own layout and interaction model, plus shared components, settings, and onboarding. All user-visible strings should say Jack, not Gilt.

## Multi-View Mode Architecture

Jack supports four view modes controlled by `ViewMode` enum (in Models.swift). The user selects their preferred mode in Settings or Onboarding, stored in `AppSettings.viewMode`. When the mode changes, `ClipboardStore.settings.didSet` triggers `AppWindowManager.shared.switchMode()` which creates/shows the appropriate window.

### Tray Mode (default)

Bottom-of-screen shelf with horizontal card scrolling. Uses the SwiftUI `WindowGroup` window.

| File | Role |
|------|------|
| `ContentView.swift` | Main tray layout: resize handle + top rail (search, folder tabs, menu) + horizontal clip strip. Binds to tray window via `WindowAccessor`. |
| `ClipCardView.swift` | Type-specific clip card (text/link/image/audio/color). Two-zone layout: colored header band + dark content area. Shared by tray and grid modes. |
| `FolderTabsView.swift` | Scrollable horizontal folder pills with context menus (rename, reorder, delete). Supports drag-drop of clips onto folders. |
| `AppKitResizeHandle.swift` | NSViewRepresentable vertical resize handle. Tracks mouse Y in screen coordinates via `window.trackEvents()` to avoid SwiftUI DragGesture jitter. |
| `ClipPreviewOverlay.swift` | Full-content preview overlay triggered by Space key on selected clip. Supports inline text editing. |

### Drawer Mode

Right-edge side panel with vertical clip list. Created as a standalone `BorderlessKeyWindow`.

| File | Role |
|------|------|
| `SideDrawerView.swift` | Vertical layout: header + search + folder pills + scrollable clip list using `DrawerClipRow`. |
| `DrawerClipRow.swift` | Compact horizontal row for each clip: type color strip + preview text + metadata + source app icon. Double-tap to paste. |
| `DrawerResizeHandle.swift` | NSViewRepresentable horizontal resize handle on left edge. Tracks mouse X in screen coordinates. Calls `AppWindowManager.shared.setDrawerWidth()`. |

### Grid Mode

Centered floating window with card grid. Created as a standalone `BorderlessKeyWindow`.

| File | Role |
|------|------|
| `FloatingGridView.swift` | `LazyVGrid` of clips using adaptive columns (150-190px). Reuses `ClipCardView` at 170x160px. Top search bar, bottom folder pills. Fixed 580x500 frame. Includes adaptive chrome contrast so search/title/close remain legible against bright or dark themed/wallpaper backgrounds. Click-outside dismisses when Settings preview is not active. |

### Radial Mode

Quick-access ring of recent clips appearing at cursor position. Created as a standalone `BorderlessKeyWindow`.

| File | Role |
|------|------|
| `RadialMenuView.swift` | Circular layout with up to 8 clips arranged in a ring (140px radius). Uses `AuricBackground` clipped to a circle, so radial is fully theme/wallpaper-aware (including wallpaper pan offsets). Center hub opens Settings. Click-outside dismisses when Settings preview is not active. 400x400 frame. |
| `RadialClipNode.swift` | Compact clip preview (90x70) for ring position. Simplified two-zone card: type-colored header strip + content preview. Single tap = instant paste + dismiss. Hover scales up 1.08x. |

### Shared Components

| File | Role |
|------|------|
| `AuricBackground.swift` | `ViewModifier` providing the themed layered background shared across all modes. Handles theme variants: gradient, vibrancy (real NSVisualEffectView), scenic (wallpaper-primary), and custom. Also contains `PositionedWallpaperImage` for pan-offset wallpaper rendering (both X and Y axes) used by tray/drawer/grid/radial. |
| `ModeSettingsLink.swift` | Reusable Settings button for standalone modes (drawer/grid/radial). Uses `SettingsLink` and coordinates with `AppWindowManager.prepareForSettingsPresentation()` so Settings stays in front without losing live view preview. |
| `ViewModePickerCard.swift` | Reusable card for selecting a `ViewMode`. Used in both Settings and Onboarding. Shows icon, label, and description with gold accent when selected. Has `compact` flag for different contexts. |

### Settings & Configuration

| File | Role |
|------|------|
| `SettingsView.swift` | Tabbed settings panel (Appearance, General, Categories, Folders, Advanced). Presented as a separate SwiftUI `Settings` scene window. Contains view mode picker, theme selector, shortcut config, retention controls, and a 2D wallpaper position preview (drag + horizontal/vertical sliders) with per-mode preview aspect switching. |
| `ShortcutRecorderField.swift` | NSViewRepresentable text field that captures keyboard shortcut input (modifier + key). Converts NSEvent modifiers to Carbon modifier flags for `GlobalHotKeyManager`. |
| `ColorPickerSwatch.swift` | Row of preset color token circles + native ColorPicker. Used in folder customization. |
| `GradientPickerView.swift` | Inline gradient editor: preview bar + two ColorPickers (start/end) + angle slider. For custom background gradients. |
| `PresetLibraryView.swift` | Horizontal scroll of saved color/gradient presets. Tap to apply, right-click to delete. |

### Onboarding

| File | Role |
|------|------|
| `OnboardingView.swift` | 6-step onboarding flow: Welcome, How It Works, Permissions (Accessibility), Setup (shortcut config), Style (view mode picker using `ViewModePickerCard`), Ready. Presented in a standalone 820x560 `BorderlessKeyWindow` via `AppWindowManager.presentOnboarding()`. |

## Key Patterns

### EnvironmentObject Injection
All views receive `ClipboardStore` via `@EnvironmentObject`. The store is created in `JackApp` and injected at the root. Mode windows created by `AppWindowManager.createModeWindow()` also inject the store into their root views.

### Two-Zone Card Structure
Every clip card (full-size in `ClipCardView`, compact in `RadialClipNode`) follows a two-zone layout:
1. **Header band**: Colored gradient strip with type label, timestamp, source app icon
2. **Content area**: Dark body (`NSColor(white: 0.12)`) with type-specific rendering

### Type Color Palette
Each `ClipType` has consistent colors used for header gradients, selection borders, and accents:
- **Text**: Blue-purple `(0.40, 0.52, 0.96)`
- **Link**: Green `(0.30, 0.78, 0.55)`
- **Image**: Pink-red `(0.93, 0.38, 0.48)`
- **Audio**: Orange `(0.96, 0.58, 0.28)`
- **Color**: Purple `(0.70, 0.40, 0.90)`

### Interaction Model
- **Single tap**: Toggle selection (Cmd+click for multi-select)
- **Double tap** (< 0.28s gap): Copy to clipboard + paste to active app
- **Drag**: Cards draggable via `NSItemProvider` (UUID string), drop onto folder pills
- **Space**: Preview overlay (tray mode)
- **Escape**: Dismiss window (all modes)
- **Return**: Paste selected clip (grid/radial)

### Window Presentation Rules
The tray window is a bottom-of-screen dock-level window with special properties. This creates constraints:
- **Never use `.sheet()` on ContentView** -- sheets attach to parent window and render squashed inside the narrow tray
- **Never use `.fullScreenCover()` on ContentView** -- same parent-window problem
- **For standalone UI** (onboarding, modals): Create a separate `NSWindow` via `AppWindowManager` and present independently
- **For in-context UI** (settings): Use the separate `Settings` scene window
- **Workspace confirmations must attach to the workspace window.** The workspace runs above normal windows, so plain `NSAlert.runModal()` can appear behind it. Use `WindowAccessor` to capture the host `NSWindow`, call `beginSheetModal(for:)`, and set the alert level above the parent as a fallback.

### Wallpaper Positioning (All Modes)
- Wallpaper offsets are normalized to `0...1` for both `wallpaperOffsetX` and `wallpaperOffsetY`.
- `WallpaperPositionPreview` in Settings supports 2D drag and dedicated horizontal/vertical sliders.
- The Settings preview supports mode-shaped aspect ratios (tray, drawer, grid, radial) so users can tune composition for each layout.
- Use `ClipboardStore.updateWallpaperOffsetLive(x:y:)` for live preview during drag/slider edits, then commit to persisted settings when editing ends.

### Resize Architecture
**Never use SwiftUI `DragGesture` for window resize.** SwiftUI gestures track in view-relative coordinates. Calling `window.setFrame()` mid-drag shifts the coordinate origin, creating a feedback loop that causes jitter.

Instead, `AppKitResizeHandle` and `DrawerResizeHandle` use NSViewRepresentable with `window.trackEvents(matching:)` to track mouse in screen coordinates, which are immune to frame changes.
