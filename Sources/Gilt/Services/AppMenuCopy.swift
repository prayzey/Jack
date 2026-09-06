import Foundation

/// Menu bar, command menu, and Edit-menu labels. Brand name stays `AppBrand.displayName`.
enum AppMenuCopy {
    static func checkForUpdates(locale: Locale? = nil) -> String {
        L10n.string("menu.checkForUpdates", default: "Check for Updates...", locale: locale)
    }

    static func about(locale: Locale? = nil) -> String {
        let template = L10n.string("menu.about", default: "About %@", locale: locale)
        return String(format: template, locale: locale ?? .current, AppBrand.displayName)
    }

    static func settingsEllipsis(locale: Locale? = nil) -> String {
        L10n.string("menu.settingsEllipsis", default: "Settings...", locale: locale)
    }

    static func toggleApp(locale: Locale? = nil) -> String {
        let template = L10n.string("menu.toggleApp", default: "Toggle %@", locale: locale)
        return String(format: template, locale: locale ?? .current, AppBrand.displayName)
    }

    static func commandPalette(locale: Locale? = nil) -> String {
        L10n.string("menu.commandPalette", default: "Command Palette", locale: locale)
    }

    static func quickNote(locale: Locale? = nil) -> String {
        L10n.string("menu.quickNote", default: "Quick Note", locale: locale)
    }

    static func voiceCompose(locale: Locale? = nil) -> String {
        L10n.string("menu.voiceCompose", default: "Voice Compose", locale: locale)
    }

    static func openWorkspace(locale: Locale? = nil) -> String {
        L10n.string("menu.openWorkspace", default: "Open Workspace", locale: locale)
    }

    static func openMeetings(locale: Locale? = nil) -> String {
        L10n.string("menu.openMeetings", default: "Open Meetings", locale: locale)
    }

    static func transcribeAudioFile(locale: Locale? = nil) -> String {
        L10n.string("menu.transcribeAudioFile", default: "Transcribe Audio File…", locale: locale)
    }

    static func copyCurrentNote(locale: Locale? = nil) -> String {
        L10n.string("menu.copyCurrentNote", default: "Copy Current Note to Clipboard", locale: locale)
    }

    static func saveCurrentNoteAsClip(locale: Locale? = nil) -> String {
        L10n.string("menu.saveCurrentNoteAsClip", default: "Save Current Note as Clip", locale: locale)
    }

    static func pasteFirstClip(locale: Locale? = nil) -> String {
        L10n.string("menu.pasteFirstClip", default: "Paste First Clip", locale: locale)
    }

    static func pasteSecondClip(locale: Locale? = nil) -> String {
        L10n.string("menu.pasteSecondClip", default: "Paste Second Clip", locale: locale)
    }

    static func pasteThirdClip(locale: Locale? = nil) -> String {
        L10n.string("menu.pasteThirdClip", default: "Paste Third Clip", locale: locale)
    }

    static func sendFeedback(locale: Locale? = nil) -> String {
        L10n.string("menu.sendFeedback", default: "Send Feedback…", locale: locale)
    }

    static func reportBug(locale: Locale? = nil) -> String {
        L10n.string("menu.reportBug", default: "Report a Bug…", locale: locale)
    }

    static func requestFeature(locale: Locale? = nil) -> String {
        L10n.string("menu.requestFeature", default: "Request a Feature…", locale: locale)
    }

    static func showApp(shortcutSymbol: String, locale: Locale? = nil) -> String {
        let template = L10n.string("menu.showAppShortcut", default: "Show %@  %@", locale: locale)
        return String(format: template, locale: locale ?? .current, AppBrand.displayName, shortcutSymbol)
    }

    static func hideJack(locale: Locale? = nil) -> String {
        L10n.string("menu.hideJack", default: "Hide Jack", locale: locale)
    }

    static func summonJack(locale: Locale? = nil) -> String {
        L10n.string("menu.summonJack", default: "Summon Jack", locale: locale)
    }

    static func quitApp(locale: Locale? = nil) -> String {
        let template = L10n.string("menu.quitApp", default: "Quit %@", locale: locale)
        return String(format: template, locale: locale ?? .current, AppBrand.displayName)
    }

    static func settingsWindowTitle(locale: Locale? = nil) -> String {
        let template = L10n.string("menu.settingsWindowTitle", default: "%@ Settings", locale: locale)
        return String(format: template, locale: locale ?? .current, AppBrand.displayName)
    }
}
