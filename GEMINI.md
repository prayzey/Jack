# GEMINI.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**Jack** is a **macOS clipboard history manager** built with SwiftUI. It captures clipboard items, organizes them into folders, and provides quick-paste via a global hotkey (Ctrl+V). Inspired by the Paste app's two-zone card layout.

Renamed Gilt → Jack. See `AppBrand.swift` for what stays legacy (bundle ID, data folder, SPM target) vs what is Jack (display name, user copy, logs).

## Build & Run

This is a Swift Package Manager project (no Xcode project file). macOS 14+ required, Swift 6.2.

```bash
# Build
swift build

# Run
swift run Gilt

# Build release
swift build -c release
```

The SPM workspace is at `.swiftpm/xcode/package.xcworkspace` — open this in Xcode for GUI development.

### Building as .app Bundle

Use the bundled release scripts from `scripts/` when you need a real `.app` instead of a bare SwiftPM binary:

```bash
./scripts/build-app.sh
./scripts/build-app.sh release
```

For direct-download release work, also use:

```bash
./scripts/build-dmg.sh release
./scripts/notarize-release.sh release dmg
./scripts/publish-r2-release.sh
./scripts/update-sparkle-appcast.sh
```

## Architecture

**State-driven SwiftUI app with centralized store pattern.**

- **Entry point**: `Sources/Gilt/Jack.swift` — `@main` App struct, window config, keyboard shortcuts
- **Central state**: `ClipboardStore` (`Services/ClipboardStore.swift`) — `@MainActor ObservableObject` injected as `@EnvironmentObject`. Manages all clips, folders, search, settings, persistence, and coordinates with services.
- **Persistence**: JSON file at `~/Library/Application Support/Jack/Gilt.store`.

### Key Services

| Service | Role |
|---------|------|
| `ClipboardMonitor` | Polls `NSPasteboard` every 0.6s, produces `CapturedClip` with detected type (text/link/image/audio) |
| `GlobalHotKeyManager` | Carbon HIToolbox APIs for system-wide hotkey registration |
| `LinkMetadataService` | Actor-based async URL enrichment (titles, favicons), cached by domain |
| `AppWindowManager` | Window positioning, CVDisplayLink show/hide animations, resize coordination |
| `AppKitResizeHandle` | NSViewRepresentable drag handle — tracks mouse in screen coordinates for jitter-free resize |

### Data Model (`Models.swift`)

Core types: `ClipItem`, `ClipFolder`, `ClipType` (text/link/image/audio), `AppSettings`, `GlobalShortcut`, `FolderColorToken`. All Codable for JSON persistence.

### Views

- `ContentView` — Main layout: top rail + horizontal scrolling card strip + resize handle. Card sizing uses `GeometryReader` (not @State) for fluid resize.
- `ClipCardView` — Type-specific clip rendering with accent colors, drag-drop, double-tap paste
- `FolderTabsView` — Scrollable folder pills with context menus (rename/move/delete)
- `SettingsView` — Form-based settings panel
- `ShortcutRecorderField` — NSViewRepresentable for capturing keyboard shortcut input

### AppKit Bridge

`WindowAccessor` bridges SwiftUI to AppKit (`NSWindow` access). `AppKitResizeHandle` uses `window.trackEvents(matching:)` for screen-coordinate mouse tracking during resize. `AppDelegate` handles app lifecycle and crash logging.

## Key Patterns

- **Zero external dependencies** — uses only Apple frameworks (Foundation, AppKit, SwiftUI, OSLog, QuartzCore, Carbon.HIToolbox)
- **Swift concurrency** — actors for thread-safe services, async/await for URL fetching
- **Environment injection** — `ClipboardStore` flows through SwiftUI environment
- **Source directory layout**: `Sources/Gilt/{App, Models, Services, Views}/`

## Release Guardrail — SwiftPM Resource Bundle

Direct-download builds must include the generated SwiftPM resource bundle at:

- `Jack.app/Contents/Resources/Gilt_Gilt.bundle`

Why this matters:
- launch-time assets come from SwiftPM resources
- if the packaged `.app` omits this bundle, the app can crash on launch before any UI appears

Rules:
- do not treat `Sources/Gilt/Resources/` loose-file copies as a substitute for the SwiftPM bundle
- if you change packaging or resource loading, verify `scripts/build-app.sh` still fails when `Gilt_Gilt.bundle` is missing
- before publishing a release, verify the packaged app contains `Jack.app/Contents/Resources/Gilt_Gilt.bundle`
- keep `version.json`, `appcast.xml`, and the uploaded DMG URLs in sync

## Window Animation & Resize Architecture

### Show/Hide Animations
Window show/hide uses a **manual CVDisplayLink** animation loop (not NSAnimationContext) for buttery smooth frame-by-frame interpolation. Custom cubic bezier easing curves for deceleration (show) and acceleration (hide). Show: 0.35s, Hide: 0.28s. Hide keeps window fully opaque (no fade). Settings window auto-closes on hide.

### Interactive Resize — Critical Pattern
**Never use SwiftUI `DragGesture` for window resize.** SwiftUI gestures track in view-relative coordinates — calling `window.setFrame()` mid-drag shifts the coordinate origin, creating a feedback loop that causes jitter/shake.

Instead, use `AppKitResizeHandle` (NSViewRepresentable) which:
1. Tracks mouse in **screen coordinates** via `NSEvent.mouseLocation` (immune to frame changes)
2. Uses `window.trackEvents(matching:)` for a tight event loop at display refresh rate
3. Bypasses SwiftUI's gesture system entirely during drag

Card sizing uses `GeometryReader` to respond to actual available space — no `@State` or `NotificationCenter` round-trips during resize. The window has `preservesContentDuringLiveResize = true`.

### Window Presentation Rules — Critical

The main app window is a **bottom-of-screen tray** (dock-level, not a standard window). This creates constraints on how secondary UI (sheets, modals, onboarding) can be presented:

- **Never use `.sheet()` on ContentView.** SwiftUI sheets attach to their parent window. Since the parent is a narrow bottom tray, any sheet renders squashed inside the tray rather than centered on screen.
- **Never use `.fullScreenCover()` on ContentView** — same parent-window problem.
- **For standalone UI (onboarding, first-run, alerts):** Create a separate `NSWindow` via `AppWindowManager` and present it independently. Hide the tray while the standalone window is shown. See `AppWindowManager.presentOnboarding(store:)` for the pattern.
- **For in-context UI (settings, confirmations):** Use the existing `Settings` scene (separate window) or AppKit `NSPanel`/`NSAlert` presented independently of the tray window.
- **The tray window has special properties** (`.dockWindow + 1` level, hidden title bar, no resize, auto-hides on deactivate). Any window presented relative to it inherits or is affected by these properties. Always present secondary windows as standalone.

### Card Content Scaling
Text line limits scale dynamically with card height (`availableHeight / lineHeight`). All content types use `frame(maxHeight: .infinity)` to fill available space — no dead space at bottom when expanded.

## Design System

The UI follows a **Paste app** aesthetic: dark translucent container, colored type-coded cards, clean horizontal layout. All new features must follow these conventions.

### Card Layout (Two-Zone)

Every clip card has exactly two zones stacked vertically:

1. **Header band** (36px): Colored gradient strip — type label (uppercase bold 11pt, 0.6 tracking) + timestamp (10pt) on left, source app icon (20x20) on right
2. **Content area**: Dark body (`NSColor(white: 0.12)`) with 10px padding — type-specific rendering
3. **Footer overlay** (bottom-right, 9pt): Character count or image dimensions

Content rendering per type:
- **Text**: 13pt system font (monospaced 12pt if code-like — detected by `{`, `func `, `let `, `import `, `//`, `=>`). Line limit scales with card height.
- **Link**: Favicon (20x20) + page title + host below
- **Image**: `scaledToFill` with 6px corner radius
- **Audio**: Waveform bar visualization (20 bars, seeded heights from item ID)

### Type Color Palette

Each `ClipType` has a consistent color identity used for header gradients, selection borders, and accents:

| Type | Header Gradient (L→R) | Accent Color (for selection/highlights) |
|------|----------------------|----------------------------------------|
| Text | `(0.30,0.36,0.82)` → `(0.48,0.38,0.90)` | `(0.40, 0.52, 0.96)` blue-purple |
| Link | `(0.18,0.62,0.42)` → `(0.24,0.72,0.52)` | `(0.30, 0.78, 0.55)` green |
| Image | `(0.82,0.26,0.38)` → `(0.90,0.34,0.44)` | `(0.93, 0.38, 0.48)` pink-red |
| Audio | `(0.88,0.48,0.18)` → `(0.94,0.56,0.24)` | `(0.96, 0.58, 0.28)` orange |

When adding new `ClipType` variants, always define both a header gradient and an accent color.

### Selection & Borders

- Selected: **type accent color** border, 2.5px, 95% opacity
- Unselected: white 8% border, 0.5px
- Never use white borders for selection

### Container Background

Layered dark background:
- Base: Dark gradient (0.08 → 0.12 → 0.16 luminance, warm tint toward bottom-right)
- Layer: Warm radial vignette from bottom-trailing
- Top: `.ultraThinMaterial` at 15% opacity
- Corner radius: 16px

### Top Rail (left → right)

1. Magnifying glass icon (standalone button, expands search field on tap)
2. Search text field (visible only when focused or has text, 180px capsule)
3. Folder tabs (scrollable pills)
4. Spacer
5. Ellipsis `...` menu (contains Settings)

### Folder Pills

- Capsule with colored dot (12px) + name (12pt)
- Selected: white 30% fill, bold, full white text
- Unselected: white 6% fill, semibold, 75% white text
- Padding: 14h × 8v, `+` button 26x26

### Spacing & Sizing Constants

- Card corner radius: **14px**
- Card gap: **12px**
- Card shadow: `black 35%, radius 8, y 4`
- Resize handle: 44×4px capsule, white 18%, 24px hit target (AppKit mouse tracking)
- Container padding: 14px horizontal

### Typography Rules

- Use `Font.system(size:weight:design:)` only — no custom fonts
- Monospaced design only for code-like text content
- Text hierarchy through white opacity: labels 1.0, body 0.9, secondary 0.5–0.75, captions 0.35
- Never use colored text on dark backgrounds

### Interaction Model

- **Single tap**: Toggle selection
- **Double tap** (< 0.28s gap): Copy + paste to active app
- **Drag**: Cards draggable via NSItemProvider (UUID string), drop onto folder pills
- **Folder double-tap**: Inline rename

### Design Rules

- Maintain the two-zone card structure — never flatten to single-gradient cards
- Every clip type must use the color palette above
- Dark-on-dark: content areas use very dark grays, never pure black or white
- All cards show footer caption (char count / dimensions)
- Scroll indicators hidden on the clip strip
- New UI elements should use white at varying opacity for foreground, not bright colors
