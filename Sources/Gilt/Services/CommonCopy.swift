import Foundation

/// Shared app-owned action labels used across menus, cards, and settings.
/// Prefer these over hard-coded English so language overrides stay consistent.
enum CommonCopy {
    static func copy(locale: Locale? = nil) -> String {
        L10n.string("common.copy", default: "Copy", locale: locale)
    }

    static func paste(locale: Locale? = nil) -> String {
        L10n.string("common.paste", default: "Paste", locale: locale)
    }

    static func cut(locale: Locale? = nil) -> String {
        L10n.string("common.cut", default: "Cut", locale: locale)
    }

    static func selectAll(locale: Locale? = nil) -> String {
        L10n.string("common.selectAll", default: "Select All", locale: locale)
    }

    static func delete(locale: Locale? = nil) -> String {
        L10n.string("common.delete", default: "Delete", locale: locale)
    }

    static func rename(locale: Locale? = nil) -> String {
        L10n.string("common.rename", default: "Rename", locale: locale)
    }

    static func reset(locale: Locale? = nil) -> String {
        L10n.string("common.reset", default: "Reset", locale: locale)
    }

    static func remove(locale: Locale? = nil) -> String {
        L10n.string("common.remove", default: "Remove", locale: locale)
    }

    static func clear(locale: Locale? = nil) -> String {
        L10n.string("common.clear", default: "Clear", locale: locale)
    }

    static func cancel(locale: Locale? = nil) -> String {
        L10n.string("common.cancel", default: "Cancel", locale: locale)
    }

    static func save(locale: Locale? = nil) -> String {
        L10n.string("common.save", default: "Save", locale: locale)
    }

    static func add(locale: Locale? = nil) -> String {
        L10n.string("common.add", default: "Add", locale: locale)
    }

    static func show(locale: Locale? = nil) -> String {
        L10n.string("common.show", default: "Show", locale: locale)
    }

    static func hide(locale: Locale? = nil) -> String {
        L10n.string("common.hide", default: "Hide", locale: locale)
    }

    static func open(locale: Locale? = nil) -> String {
        L10n.string("common.open", default: "Open", locale: locale)
    }

    static func download(locale: Locale? = nil) -> String {
        L10n.string("common.download", default: "Download", locale: locale)
    }

    static func settings(locale: Locale? = nil) -> String {
        L10n.string("common.settings", default: "Settings", locale: locale)
    }

    static func style(locale: Locale? = nil) -> String {
        L10n.string("common.style", default: "Style", locale: locale)
    }

    static func color(locale: Locale? = nil) -> String {
        L10n.string("common.color", default: "Color", locale: locale)
    }

    static func icon(locale: Locale? = nil) -> String {
        L10n.string("common.icon", default: "Icon", locale: locale)
    }

    static func name(locale: Locale? = nil) -> String {
        L10n.string("common.name", default: "Name", locale: locale)
    }

    static func activate(locale: Locale? = nil) -> String {
        L10n.string("common.activate", default: "Activate", locale: locale)
    }

    static func position(locale: Locale? = nil) -> String {
        L10n.string("common.position", default: "Position", locale: locale)
    }

    static func shortcut(locale: Locale? = nil) -> String {
        L10n.string("common.shortcut", default: "Shortcut", locale: locale)
    }

    static func permissions(locale: Locale? = nil) -> String {
        L10n.string("common.permissions", default: "Permissions", locale: locale)
    }

    static func accessibility(locale: Locale? = nil) -> String {
        L10n.string("common.accessibility", default: "Accessibility", locale: locale)
    }

    static func wallpaper(locale: Locale? = nil) -> String {
        L10n.string("common.wallpaper", default: "Wallpaper", locale: locale)
    }

    static func behavior(locale: Locale? = nil) -> String {
        L10n.string("common.behavior", default: "Behavior", locale: locale)
    }

    static func surface(locale: Locale? = nil) -> String {
        L10n.string("common.surface", default: "Surface", locale: locale)
    }

    static func font(locale: Locale? = nil) -> String {
        L10n.string("common.font", default: "Font", locale: locale)
    }

    static func spacing(locale: Locale? = nil) -> String {
        L10n.string("common.spacing", default: "Spacing", locale: locale)
    }

    static func status(locale: Locale? = nil) -> String {
        L10n.string("common.status", default: "Status", locale: locale)
    }

    static func linked(locale: Locale? = nil) -> String {
        L10n.string("common.linked", default: "Linked", locale: locale)
    }

    static func manage(locale: Locale? = nil) -> String {
        L10n.string("common.manage", default: "Manage", locale: locale)
    }

    static func fast(locale: Locale? = nil) -> String {
        L10n.string("common.fast", default: "Fast", locale: locale)
    }

    static func accurate(locale: Locale? = nil) -> String {
        L10n.string("common.accurate", default: "Accurate", locale: locale)
    }

    static func replace(locale: Locale? = nil) -> String {
        L10n.string("common.replace", default: "Replace", locale: locale)
    }

    static func erase(locale: Locale? = nil) -> String {
        L10n.string("common.erase", default: "Erase", locale: locale)
    }

    static func activeBadge(locale: Locale? = nil) -> String {
        L10n.string("common.active", default: "ACTIVE", locale: locale)
    }

    static func horizontal(locale: Locale? = nil) -> String {
        L10n.string("common.horizontal", default: "Horizontal", locale: locale)
    }

    static func vertical(locale: Locale? = nil) -> String {
        L10n.string("common.vertical", default: "Vertical", locale: locale)
    }

    static func leftRight(locale: Locale? = nil) -> String {
        L10n.string("common.leftRight", default: "Left/Right", locale: locale)
    }

    static func upDown(locale: Locale? = nil) -> String {
        L10n.string("common.upDown", default: "Up/Down", locale: locale)
    }

    static func accent(locale: Locale? = nil) -> String {
        L10n.string("common.accent", default: "Accent", locale: locale)
    }

    static func textMode(locale: Locale? = nil) -> String {
        L10n.string("common.textMode", default: "Text Mode", locale: locale)
    }

    static func textColor(locale: Locale? = nil) -> String {
        L10n.string("common.textColor", default: "Text Color", locale: locale)
    }

    static func family(locale: Locale? = nil) -> String {
        L10n.string("common.family", default: "Family", locale: locale)
    }

    static func viewMode(locale: Locale? = nil) -> String {
        L10n.string("common.viewMode", default: "View Mode", locale: locale)
    }

    static func pasteAsPlainText(locale: Locale? = nil) -> String {
        L10n.string("common.pasteAsPlainText", default: "Paste as Plain Text", locale: locale)
    }

    static func moveLeft(locale: Locale? = nil) -> String {
        L10n.string("common.moveLeft", default: "Move Left", locale: locale)
    }

    static func moveRight(locale: Locale? = nil) -> String {
        L10n.string("common.moveRight", default: "Move Right", locale: locale)
    }

    static func customColor(locale: Locale? = nil) -> String {
        L10n.string("common.customColor", default: "Custom Color...", locale: locale)
    }

    static func matchFolder(locale: Locale? = nil) -> String {
        L10n.string("common.matchFolder", default: "Match Folder", locale: locale)
    }

    static func clearAll(locale: Locale? = nil) -> String {
        L10n.string("common.clearAll", default: "Clear all", locale: locale)
    }

    static func noMatches(locale: Locale? = nil) -> String {
        L10n.string("common.noMatches", default: "No matches", locale: locale)
    }

    static func nothingHereYet(locale: Locale? = nil) -> String {
        L10n.string("common.nothingHereYet", default: "Nothing here yet", locale: locale)
    }

    static func newNote(locale: Locale? = nil) -> String {
        L10n.string("common.newNote", default: "New note", locale: locale)
    }

    static func deleteFolder(locale: Locale? = nil) -> String {
        L10n.string("common.deleteFolder", default: "Delete Folder", locale: locale)
    }

    static func inputVolume(locale: Locale? = nil) -> String {
        L10n.string("common.inputVolume", default: "Input volume", locale: locale)
    }
}
