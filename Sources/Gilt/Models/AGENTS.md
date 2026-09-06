# Models Directory

This directory contains all data models for Jack (Swift module `Gilt`). The app uses SwiftData for persistence with two `@Model` classes, plus a rich set of enums and structs in `Models.swift` for settings, types, and configuration. User-facing names use Jack; persistence keys may still say Gilt — see `AppBrand.swift`.

## Files

| File | Role |
|------|------|
| `Models.swift` | Central model definitions: `ClipType`, `ViewMode`, `AppSettings`, `BackgroundTheme`, `GlobalShortcut`, `SmartCategory`, `ContentTag`, folder color types, and legacy migration structs. |
| `ClipItemModel.swift` | SwiftData `@Model` for individual clipboard items. Primary persistent entity. |
| `ClipFolderModel.swift` | SwiftData `@Model` for folders (both user-created and smart/system). |
| `LinkPlatform.swift` | Enum of recognized link platforms (YouTube, GitHub, Spotify, etc.) with host detection and display metadata for rich link previews. |

## SwiftData Models

### ClipItemModel

The primary persistent entity. Key properties:
- `clipID: UUID` -- stable identifier (SwiftData's implicit `id` is internal)
- `typeRaw: String` -- maps to `ClipType` via computed `clipType`
- `previewText`, `textValue`, `urlValue` -- content fields
- `imageData: Data?` -- stored with `@Attribute(.externalStorage)` for large blobs
- `linkPageTitle`, `linkFaviconURLString`, `linkThumbnailData`, `linkDescriptionText`, `linkPlatformRaw`, `linkVideoDuration` -- rich link metadata (persisted to avoid re-fetching)
- `contentTagsRaw: String` -- comma-separated `ContentTag` raw values, with computed `contentTags: Set<ContentTag>`
- `isSensitive: Bool`, `sensitiveExpiresAt: Date?` -- credential detection + auto-expiry
- `detectedLanguageRaw: String?` -- detected programming language for code clips
- `sortOrder: Int` -- manual drag-to-reorder. Higher values appear first (newest).
- `folders: [ClipFolderModel]` -- inverse relationship

### ClipFolderModel

Folders with rich color customization:
- `folderID: UUID`, `name: String`, `isSystem: Bool`
- Color properties stored as raw strings: `colorRaw`, `colorModeRaw`, `fillColorRaw`, `textColorModeRaw`, `customTextColorRaw`. Supports both `FolderColorToken` names and hex color strings.
- `smartCategoryRaw: String?` -- links to `SmartCategory` for auto-sorted smart folders
- `sortOrder: Int` -- display order
- `clips: [ClipItemModel]` -- relationship to clips
- Static `clipboardID` -- the built-in "Clipboard" system folder UUID

## Core Enums

### ViewMode

```swift
enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case tray     // "Bottom shelf with horizontal scroll"
    case drawer   // "Side panel with vertical list"
    case grid     // "Floating window with card grid"
    case radial   // "Quick-access ring at cursor"
}
```

Has `label`, `icon` (SF Symbol name), and `description` properties. Stored in `AppSettings.viewMode`, defaults to `.tray`.

### ClipType

```swift
enum ClipType: String, Codable, CaseIterable {
    case text, link, image, audio, color
}
```

Determines card rendering, header gradient colors, and accent colors throughout the UI.

### SmartCategory

Seven auto-categorization buckets: `code`, `images`, `links`, `contacts`, `colors`, `addresses`, `sensitive`. Each has a deterministic `folderID` (hardcoded UUID), a `folderColor`, a `defaultFillGradient`, and a `systemImage`. Smart folders are created/maintained by `ClipboardStore` based on `SmartCategorySettings` toggles.

### ContentTag

Sub-type annotations detected by `ContentClassifier`: `code`, `email`, `phoneNumber`, `colorValue`, `credential`, `address`. Stored as comma-separated raw values in `ClipItemModel.contentTagsRaw`.

## AppSettings

Central settings struct, persisted as JSON in UserDefaults under key `"GiltAppSettings"`. All properties use `decodeIfPresent` with defaults for backward compatibility.

Key properties:
- `viewMode: ViewMode` -- active view mode (default: `.tray`)
- `backgroundTheme: BackgroundTheme` -- UI theme (auric, obsidian, midnight, forest, ember, glass, vibrancy, scenic, custom)
- `backgroundOpacity: Double` -- theme opacity (0-1)
- `backgroundWallpaper: BackgroundWallpaper` -- wallpaper selection
- `globalShortcut: GlobalShortcut` -- hotkey config (default: Ctrl+V)
- `historyRetention: HistoryRetention` -- day/week/month/forever
- `smartCategories: SmartCategorySettings` -- per-category enable/disable toggles
- `hasCompletedOnboarding: Bool` -- gates onboarding display
- `pasteToActiveApp: Bool` -- auto-paste behavior
- `launchAtLogin: Bool`, `showInMenuBar: Bool` -- system integration

Important: `AppSettings.didSet` in `ClipboardStore` triggers `persistSettings()` AND calls `AppWindowManager.shared.switchMode()` if `viewMode` changed. This is the reactive link between settings and window management.

## Background Theming

`BackgroundTheme` enum defines 9 themes. Each has:
- `gradientColors: [Color]` -- 3-stop gradient
- `vignetteColor: Color` -- radial vignette overlay
- `materialOpacityMultiplier: Double` -- blur material strength
- Special modes: `vibrancy` (real NSVisualEffectView), `scenic` (wallpaper-primary), `custom` (user-defined gradient via `GradientSpec`)

## Legacy Migration

`ClipItem` and `ClipFolder` structs (marked as legacy) exist solely for one-time migration from the old JSON-based persistence (`state.json`) to SwiftData. They should not be used for new features.
