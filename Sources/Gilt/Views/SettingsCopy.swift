import Foundation

// Keep settings-shell copy centralized here so future AI passes can localize or
// rewrite wording without diffing the large Settings view for every string edit.
enum SettingsCopy {
    static func managerLabel(locale: Locale? = nil) -> String {
        L10n.string("settings.sidebar.managerLabel", default: "Clipboard Manager", locale: locale)
    }

    static func doneButtonTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.sidebar.done", default: "Done", locale: locale)
    }

    static func headerSubtitle(locale: Locale? = nil) -> String {
        L10n.string("settings.header.subtitle", default: "Customize your Jack experience", locale: locale)
    }

    static func appLanguageTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.general.appLanguage.title", default: "App Language", locale: locale)
    }

    static func appLanguageSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.appLanguage.subtitle",
            default: "Choose the language Jack should use throughout the app",
            locale: locale
        )
    }

    static func trackpadRevealSectionTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.general.trackpadReveal.section", default: "Trackpad Reveal", locale: locale)
    }

    static func trackpadRevealBottomEdgeTitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.trackpadReveal.bottomEdge.title",
            default: "Two-finger swipe up at bottom edge",
            locale: locale
        )
    }

    static func trackpadRevealBottomEdgeSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.trackpadReveal.bottomEdge.subtitle",
            default: "Reveal Jack when your pointer is near the bottom of the screen and you swipe upward",
            locale: locale
        )
    }

    static func trackpadRevealBottomCenterTitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.trackpadReveal.bottomCenter.title",
            default: "Two-finger swipe up at bottom center",
            locale: locale
        )
    }

    static func trackpadRevealBottomCenterSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.trackpadReveal.bottomCenter.subtitle",
            default: "Use a tighter bottom-center zone if you want fewer accidental reveals",
            locale: locale
        )
    }

    static func trackpadRevealPrimaryNote(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.trackpadReveal.primaryNote",
            default: "These are optional extras. Your keyboard shortcut stays the main way to open Jack.",
            locale: locale
        )
    }

    static func trackpadRevealThreeFingerNote(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.general.trackpadReveal.threeFingerNote",
            default: "Global three-finger swipe is not exposed through Apple's supported macOS APIs, so Jack keeps this to the supported two-finger reveal gestures above.",
            locale: locale
        )
    }

    static func greeting(for date: Date = Date(), fullName: String = NSFullUserName(), calendar: Calendar = .current, locale: Locale? = nil) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting = greetingWord(forHour: hour, locale: locale)
        guard let firstName = fullName.split(separator: " ").first, !firstName.isEmpty else {
            return greeting
        }
        return "\(greeting), \(firstName)"
    }

    static func eraseHistoryAlertTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.alert.eraseHistory.title", default: "Erase Clipboard History?", locale: locale)
    }

    static func eraseHistoryAlertConfirm(locale: Locale? = nil) -> String {
        L10n.string("settings.alert.eraseHistory.confirm", default: "Erase", locale: locale)
    }

    static func cancelButtonTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.alert.cancel", default: "Cancel", locale: locale)
    }

    static func eraseHistoryAlertMessage(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.alert.eraseHistory.message",
            default: "This removes all saved clips and can't be undone.",
            locale: locale
        )
    }

    static func deleteFolderAlertTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.alert.deleteFolder.title", default: "Delete Folder?", locale: locale)
    }

    static func deleteFolderAlertConfirm(locale: Locale? = nil) -> String {
        L10n.string("settings.alert.deleteFolder.confirm", default: "Delete", locale: locale)
    }

    static func deleteFolderAlertMessage(folderName: String, locale: Locale? = nil) -> String {
        let template = L10n.string(
            "settings.alert.deleteFolder.message",
            default: "Delete \"%@\" and remove it from any clips using it?",
            locale: locale
        )
        return String(format: template, locale: locale ?? .current, folderName)
    }

    private static func greetingWord(forHour hour: Int, locale: Locale? = nil) -> String {
        switch hour {
        case 5..<12:
            return L10n.string("settings.greeting.morning", default: "Good morning", locale: locale)
        case 12..<17:
            return L10n.string("settings.greeting.afternoon", default: "Good afternoon", locale: locale)
        case 17..<22:
            return L10n.string("settings.greeting.evening", default: "Good evening", locale: locale)
        default:
            return L10n.string("settings.greeting.night", default: "Good night", locale: locale)
        }
    }

    // MARK: - Appearance / Quick Note / Workspace

    static func wallpaperDragHint(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.wallpaper.dragHint",
            default: "Drag to reposition or use sliders below",
            locale: locale
        )
    }

    static func paperTypeTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.quickNote.paperType.title", default: "Paper Type", locale: locale)
    }

    static func paperTypeSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.quickNote.paperType.subtitle",
            default: "Overlay the note surface with lines, dots, or a grid",
            locale: locale
        )
    }

    static func fontFamilySubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.quickNote.fontFamily.subtitle",
            default: "Apple's system families plus three premium fonts, or upload your own",
            locale: locale
        )
    }

    static func workspaceDesign(locale: Locale? = nil) -> String {
        L10n.string("settings.appearance.workspaceDesign", default: "Workspace Design", locale: locale)
    }

    static func workspaceBackground(locale: Locale? = nil) -> String {
        L10n.string("settings.appearance.workspaceBackground", default: "Workspace Background", locale: locale)
    }

    static func workspaceBehavior(locale: Locale? = nil) -> String {
        L10n.string("settings.appearance.workspaceBehavior", default: "Workspace Behavior", locale: locale)
    }

    static func saveGradientPreset(locale: Locale? = nil) -> String {
        L10n.string("settings.appearance.saveGradientPreset", default: "Save Gradient Preset", locale: locale)
    }

    // MARK: - General

    static func appSection(locale: Locale? = nil) -> String {
        L10n.string("settings.general.appSection", default: "App", locale: locale)
    }

    static func startupMenu(locale: Locale? = nil) -> String {
        L10n.string("settings.general.startupMenu", default: "Startup & Menu", locale: locale)
    }

    static func pasteBehavior(locale: Locale? = nil) -> String {
        L10n.string("settings.general.pasteBehavior", default: "Paste Behavior", locale: locale)
    }

    static func history(locale: Locale? = nil) -> String {
        L10n.string("settings.general.history", default: "History", locale: locale)
    }

    static func notesVault(locale: Locale? = nil) -> String {
        L10n.string("settings.general.notesVault", default: "Notes Vault", locale: locale)
    }

    static func autoDetect(locale: Locale? = nil) -> String {
        L10n.string("settings.general.autoDetect", default: "Auto-Detect", locale: locale)
    }

    // MARK: - Categories / Folders

    static func smartFoldersHint(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.categories.smartFoldersHint",
            default: "Smart folders appear automatically when matching content is detected.",
            locale: locale
        )
    }

    static func sensitiveContent(locale: Locale? = nil) -> String {
        L10n.string("settings.categories.sensitiveContent", default: "Sensitive Content", locale: locale)
    }

    static func smartCategories(locale: Locale? = nil) -> String {
        L10n.string("settings.categories.smartCategories", default: "Smart Categories", locale: locale)
    }

    static func yourFolders(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.yourFolders", default: "Your Folders", locale: locale)
    }

    static func noCustomFolders(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.empty", default: "No custom folders yet", locale: locale)
    }

    static func createNewFolder(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.createNew", default: "Create New Folder", locale: locale)
    }

    static func hiddenFromTabBar(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.hiddenFromTabBar", default: "Hidden from Tab Bar", locale: locale)
    }

    static func aiSkills(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.aiSkills", default: "AI Skills", locale: locale)
    }

    static func skillFoldersTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.skillFolders.title", default: "Skill Folders", locale: locale)
    }

    static func skillFoldersSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.folders.skillFolders.subtitle",
            default: "Import skills from AI coding tools on your Mac",
            locale: locale
        )
    }

    static func noAIToolsFound(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.folders.noAITools",
            default: "No AI coding tools found on this Mac",
            locale: locale
        )
    }

    static func addCustomFolderTitle(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.addCustomFolder.title", default: "Add Custom Folder", locale: locale)
    }

    static func addCustomFolderSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.folders.addCustomFolder.subtitle",
            default: "Choose any folder containing skills or rules",
            locale: locale
        )
    }

    static func bulkApplyTo(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.bulk.applyTo", default: "Apply To", locale: locale)
    }

    static func bulkChanges(locale: Locale? = nil) -> String {
        L10n.string("settings.folders.bulk.changes", default: "Changes", locale: locale)
    }

    static func bulkSelectHint(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.folders.bulk.selectHint",
            default: "Select folders above to apply changes",
            locale: locale
        )
    }

    static func bulkSelectedCount(_ count: Int, locale: Locale? = nil) -> String {
        let template = L10n.string(
            "settings.folders.bulk.selectedCount",
            default: "%lld selected",
            locale: locale
        )
        return String(format: template, locale: locale ?? .current, count)
    }

    static func skillsCount(_ count: Int, locale: Locale? = nil) -> String {
        let key = count == 1 ? "settings.folders.skillsCount" : "settings.folders.skillsCount.plural"
        let defaultValue = count == 1 ? "%lld skill" : "%lld skills"
        let template = L10n.string(key, default: defaultValue, locale: locale)
        return String(format: template, locale: locale ?? .current, count)
    }

    // MARK: - Advanced / License / Storage

    static func storage(locale: Locale? = nil) -> String {
        L10n.string("settings.advanced.storage", default: "Storage", locale: locale)
    }

    static func currentExecutable(_ path: String, locale: Locale? = nil) -> String {
        let template = L10n.string(
            "settings.advanced.currentExecutable",
            default: "Current executable: %@",
            locale: locale
        )
        return String(format: template, locale: locale ?? .current, path)
    }

    static func bundleID(_ id: String, locale: Locale? = nil) -> String {
        let template = L10n.string(
            "settings.advanced.bundleID",
            default: "Bundle ID: %@",
            locale: locale
        )
        return String(format: template, locale: locale ?? .current, id)
    }

    static func imageTextSearch(locale: Locale? = nil) -> String {
        L10n.string("settings.advanced.imageTextSearch", default: "Image Text Search", locale: locale)
    }

    static func grantAccess(locale: Locale? = nil) -> String {
        L10n.string("settings.advanced.grantAccess", default: "Grant Access", locale: locale)
    }

    static func licenseEnterKey(locale: Locale? = nil) -> String {
        let template = L10n.string(
            "settings.license.enterKey",
            default: "Enter your license key to unlock %@.",
            locale: locale
        )
        return String(format: template, locale: locale ?? .current, AppBrand.displayName)
    }

    static func licenseNoLicense(locale: Locale? = nil) -> String {
        L10n.string("settings.license.noLicense", default: "Don't have a license?", locale: locale)
    }

    static func licenseBuyForTen(locale: Locale? = nil) -> String {
        let template = L10n.string(
            "settings.license.buyForTen",
            default: "Buy %@ for $10",
            locale: locale
        )
        return String(format: template, locale: locale ?? .current, AppBrand.displayName)
    }

    static func licenseThisMac(locale: Locale? = nil) -> String {
        L10n.string("settings.license.thisMac", default: "This Mac", locale: locale)
    }

    static func licenseSwitchingMacs(locale: Locale? = nil) -> String {
        L10n.string("settings.license.switchingMacs", default: "Switching Macs?", locale: locale)
    }

    static func licenseSwitchingMacsBody(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.license.switchingMacs.body",
            default: "Remove the license from this Mac to free up a slot for another computer.",
            locale: locale
        )
    }

    static func removeLicense(locale: Locale? = nil) -> String {
        L10n.string("settings.license.removeLicense", default: "Remove License", locale: locale)
    }

    static func storageLivesHereTitle(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.storage.livesHere.title",
            default: "Your Clipboard Lives Here",
            locale: locale
        )
    }

    static func storageLivesHereBody(locale: Locale? = nil) -> String {
        L10n.string(
            "settings.storage.livesHere.body",
            default: "One private database on this Mac. Nothing syncs to the cloud.",
            locale: locale
        )
    }

    static func revealInFinder(locale: Locale? = nil) -> String {
        L10n.string("settings.storage.revealInFinder", default: "Reveal in Finder", locale: locale)
    }
}
