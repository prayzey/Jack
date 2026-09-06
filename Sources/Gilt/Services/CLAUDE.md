# Services Directory

This directory contains the core business logic services for Jack (Swift module `Gilt`). All services are `@MainActor` (except `LinkMetadataService` which is an actor). Use `AppBrand.displayName` in user-visible errors; keep legacy paths/IDs per `AppBrand.swift`.

## Files

| File | Role |
|------|------|
| `ClipboardStore.swift` | Central state manager. `@MainActor ObservableObject` that owns all clips, folders, settings, and coordinates with all other services. |
| `ClipboardMonitor.swift` | Polls `NSPasteboard.general` every 0.6s for new clipboard content. Produces `CapturedClip` structs. |
| `ContentClassifier.swift` | Static pattern-matching classifier. Analyzes clip content for smart categorization (code, emails, phone numbers, credentials, colors, addresses). Detects programming languages. |
| `LinkMetadataService.swift` | Actor-based async URL enrichment. Fetches page titles, favicons, og:image thumbnails, video durations. Caches by URL (max 200 entries). |
| `AccessibilityService.swift` | Thin wrapper around `AXIsProcessTrustedWithOptions` for checking/requesting macOS Accessibility permission. Used by onboarding and settings. |

## ClipboardStore -- Central State Manager

The largest file in the codebase (~1800 lines). `ClipboardStore` is the single source of truth, injected into all views via `@EnvironmentObject`.

### Key Published Properties

| Property | Type | Purpose |
|----------|------|---------|
| `clips` | `[ClipItemModel]` | All clipboard items. `didSet` invalidates filtered clips cache. |
| `folders` | `[ClipFolderModel]` | All folders (system, smart, user). |
| `selectedFolderID` | `UUID` | Active folder filter. `didSet` clears selection and preview, invalidates filter. |
| `searchText` | `String` | Search query. `didSet` schedules debounced filter invalidation. |
| `selectedClipIDs` | `Set<UUID>` | Multi-selection set. |
| `filteredClips` | `[ClipItemModel]` | Cached filtered + sorted clips (read-only published). |
| `previewingClipID` | `UUID?` | Clip shown in preview overlay. |
| `settings` | `AppSettings` | All app settings. **Critical**: `didSet` calls `persistSettings()` AND `switchMode()` if viewMode changed. |

### Initialization Sequence

On init, `ClipboardStore`:
1. Creates SwiftData `ModelContainer` at `~/Library/Application Support/Jack/Gilt.store`
2. Migrates from legacy JSON (`state.json`) if present
3. Loads settings from UserDefaults
4. Refreshes folders and clips from SwiftData
5. Ensures system folder ("Clipboard") and all smart folders exist
6. Prunes expired clips by retention policy
7. Rebuilds smart folder cache
8. Starts sensitive data expiry timer
9. Syncs launch-at-login with system state
10. Starts `ClipboardMonitor` and registers global hotkey

### Clip Ingestion Flow

1. `ClipboardMonitor` detects pasteboard change, creates `CapturedClip`
2. `ClipboardStore.ingest(captured:)` receives it
3. Deduplication check (skips if identical to most recent clip)
4. Creates `ClipItemModel`, assigns to "Clipboard" folder
5. Runs `ContentClassifier.classify()` for smart categorization
6. Routes to smart folders based on matched categories
7. Kicks off async `LinkMetadataService` enrichment for links
8. Persists to SwiftData (batched/coalesced for performance)

### Settings Reactivity

The `settings` property has a critical `didSet`:
```swift
didSet {
    persistSettings()
    if oldValue.viewMode != settings.viewMode {
        AppWindowManager.shared.switchMode(to: settings.viewMode, store: self)
    }
}
```

This means any view that modifies `store.settings.viewMode` automatically triggers mode switching through the store -> window manager chain. No manual coordination needed.

### Key Methods

- `ingest(captured:)` -- processes new clipboard items
- `loadSelectedOrSingleToClipboard(primaryID:autoPaste:)` -- copies clip to pasteboard and optionally pastes to frontmost app
- `quickPaste(index:)` -- paste Nth clip via Cmd+1/2/3
- `deleteClips(_:)` -- removes clips from SwiftData
- `moveClips(_:to:)` -- assigns clips to a folder
- `copySelectionOnly()` -- copies selected clips without pasting
- `selectSingle(_:)` / `toggleSelection(_:)` -- selection management
- `persistSettings()` -- JSON-encodes `AppSettings` to UserDefaults
- `setGlobalShortcut(_:)` -- updates hotkey via `GlobalHotKeyManager`
- `setRetention(_:)` -- updates history retention and prunes
- `iconForBundle(_:)` -- cached source app icon lookup

## ClipboardMonitor

Simple timer-based pasteboard monitor:
- Polls `NSPasteboard.general.changeCount` every 0.6s (with 0.1s tolerance)
- Detects content type: PNG/TIFF -> image, URL scheme -> link, audio markers (.mp3/.wav/spotify) -> audio, otherwise -> text
- Produces `CapturedClip` struct passed to `ClipboardStore.ingest()`

## ContentClassifier

Static classifier with no instance state. Entry point: `ContentClassifier.classify(item:)` returns `ContentClassification`.

Detection capabilities:
- **Code**: Language-specific syntax patterns for Swift, Python, JavaScript, TypeScript, HTML, CSS, SQL, Go, Rust, Ruby, Java, Shell
- **Credentials**: API keys, tokens, passwords, SSH keys, AWS credentials
- **Email addresses**: RFC-compliant regex detection
- **Phone numbers**: International and domestic format detection
- **Color values**: Hex colors, RGB/HSL, named CSS colors
- **Street addresses**: Multi-line address pattern matching
- **Suggested actions**: Contextual quick actions (call, email, open URL, open in Maps, color swatch, language badge)

## LinkMetadataService

Swift actor (thread-safe without `@MainActor`). Singleton via `LinkMetadataService.shared`.

- Fetches HTML from URLs with browser-like User-Agent header
- Parses `og:title`, `og:description`, `og:image`, `twitter:image` meta tags
- Platform-specific thumbnail extraction (YouTube, Spotify, GitHub, etc.)
- Downloads and caches thumbnail image data
- Caches results by full URL (max 200 entries)
- 6-second timeout per request

## AccessibilityService

Simple enum with static methods:
- `isTrusted()` -- checks if Accessibility permission is granted
- `requestPrompt()` -- shows system permission dialog
- `openSettings()` -- opens System Settings > Privacy > Accessibility
