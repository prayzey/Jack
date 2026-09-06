# App Directory

This directory contains app-level infrastructure: window management, lifecycle handling, hotkey registration, and SwiftUI-to-AppKit bridging.

## Files

| File | Role |
|------|------|
| `AppWindowManager.swift` | Central window management singleton. Handles multi-mode windows, show/hide animations, resize, and onboarding presentation. |
| `AppDelegate.swift` | NSApplicationDelegate. Sets activation policy to `.regular`, loads app icon from Resources, installs crash logging, unregisters hotkey on terminate. |
| `GlobalHotKeyManager.swift` | Carbon HIToolbox API wrapper for system-wide hotkey registration. Singleton. Converts key press events to `AppWindowManager.toggleWindow()` calls. |
| `SettingsNavigation.swift` | Utility enum for cross-window Settings tab navigation via NotificationCenter + UserDefaults. |
| `WindowAccessor.swift` | Lightweight NSViewRepresentable that resolves the hosting NSWindow reference for SwiftUI views. Used by ContentView to call `AppWindowManager.shared.bind(window:)`. |

## AppWindowManager -- Deep Dive

`AppWindowManager` is the most complex file in the codebase (~1000 lines). It is a `@MainActor` singleton that coordinates all window behavior.

### Multi-Mode Window Management

The manager maintains two window sources:
- **Tray window**: The SwiftUI `WindowGroup` window, bound via `bind(window:)`. Stored in `self.window`.
- **Mode windows**: Standalone `BorderlessKeyWindow` instances for drawer, grid, and radial modes. Stored in `modeWindows: [ViewMode: NSWindow]`.

The `activeViewMode` property tracks which mode is current. All toggle/show/hide logic checks this to determine which window to operate on.

### Key Methods

| Method | What It Does |
|--------|--------------|
| `switchMode(to:store:)` | Hides current mode window, sets `activeViewMode`, creates new mode window if needed via `createModeWindow()`. Does NOT show the window (that happens on next toggle). |
| `createModeWindow(for:store:)` | Creates a `BorderlessKeyWindow` hosting the mode's root view (`SideDrawerView`, `FloatingGridView`, or `RadialMenuView`) with `ClipboardStore` injected as `@EnvironmentObject`. Configures window properties per mode (movable, level, collection behavior). |
| `targetFrameForMode(_:)` | Computes the target frame for each mode: tray = full-width bottom shelf, drawer = right edge full height, grid = centered 580x500, radial = 400x400 centered on cursor. |
| `toggleWindow(source:)` | Main entry point for show/hide. Determines target window from `activeViewMode`, captures `previousApp` for focus restoration, delegates to `showModeWindow()` or `hideModeWindow()`. |
| `showModeWindow(_:trace:)` | Per-mode show animation. Tray slides up, drawer slides in from right, grid/radial fade in. All use CVDisplayLink frame animation. |
| `hideModeWindow(_:trace:reason:)` | Per-mode hide animation. Tray slides down, drawer slides out right, grid/radial fade out. Preserves Settings windows. |
| `prepareForSettingsPresentation(source:)` | Marks settings preview active, lowers mode window levels to `.normal`, and temporarily disables click-outside dismiss so users can interact with Settings while still seeing live mode previews. |
| `setDrawerWidth(_:)` | Updates drawer width (clamped 220-500) and repositions drawer window in real time during resize. |
| `hideAndRestoreFocus(targetApp:)` | Hides window and reactivates the previously-focused app (used after paste). |

### Animation Architecture

Show/hide animations use a **manual CVDisplayLink** loop for frame-by-frame interpolation (not NSAnimationContext). This delivers buttery smooth 60fps+ animation.

Key animation properties:
- `animationWindow` -- the window being animated (may differ from `self.window` for non-tray modes)
- `startFrameAnimation()` -- sets up CVDisplayLink with from/to frame, from/to alpha, duration, and easing curve
- `displayLinkTick()` -- called each frame, computes eased progress, updates window frame and alpha
- `showEase()` / `hideEase()` -- cubic bezier easing. Show decelerates to stop. Hide accelerates off-screen.
- Show: 0.30s with alpha 0->1. Hide: 0.24s with alpha 1->0. Alpha transitions mask macOS frame-constraining artifacts.

Performance tracking: frame pacing (min/max/avg delta), dropped frame count, request-to-first-frame latency. All logged via OSLog.

### Click-Outside Dismiss

Grid and radial modes install global and local mouse-down monitors via `installClickOutsideMonitors(for:)`. If a click lands outside the window frame, the window is hidden. Monitors are removed on hide.

When Settings preview is active, click-outside monitors are intentionally suppressed so clicks in the Settings window do not dismiss grid/radial.

### Settings Preview Coordination

`AppWindowManager` observes Settings window focus/close notifications. While Settings is visible:
- `settingsPreviewActive = true`
- Mode windows (tray/drawer/grid/radial) use `.normal` level instead of `dockWindow + 1`
- This keeps Settings on top while preserving a live preview of appearance changes

When Settings closes, levels are restored and click-outside monitors are re-enabled for visible grid/radial windows.

### Onboarding Window

`presentOnboarding(store:)` creates a standalone 820x560 `BorderlessKeyWindow` hosting `OnboardingView`, centered on screen. The tray window is hidden while onboarding is visible. `dismissOnboarding()` retains the dismissed window to avoid hosting-hierarchy teardown crashes, then shows the tray.

### Tray Window Configuration

The tray window has special properties (set in `configureWindow()`):
- Level: `dockWindow + 1` (above dock, below alerts)
- Hidden title bar, no standard buttons, not resizable, not movable
- `canJoinAllSpaces`, `fullScreenAuxiliary`
- `preservesContentDuringLiveResize = true`
- `hidesOnDeactivate = false` (app manages visibility manually)

Auto-hide on resign active is handled via `NSApplication.didResignActiveNotification`, with guards for internal drag operations and onboarding visibility.

### BorderlessKeyWindow

Private `NSWindow` subclass that overrides `canBecomeKey` and `canBecomeMain` to return `true`. Required because borderless windows cannot become key by default, which blocks keyboard input.

### Critical Pattern: No SwiftUI DragGesture for Resize

SwiftUI `DragGesture` tracks in view-relative coordinates. Calling `window.setFrame()` during a drag shifts the coordinate origin, creating a feedback loop that causes jitter/shake. All resize handles use AppKit-level mouse tracking in screen coordinates instead. See `AppKitResizeHandle` and `DrawerResizeHandle` in the Views directory.
