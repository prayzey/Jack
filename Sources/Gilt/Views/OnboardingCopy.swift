import Foundation

struct OnboardingHowItWorksCardCopy: Equatable {
    let number: String
    let title: String
    let description: String
}

// Keep onboarding copy out of the animation-heavy view so future AI edits can
// change wording without accidentally disturbing layout, timing, or transitions.
enum OnboardingCopy {
    static func tabTitles(locale: Locale? = nil) -> [String] {
        [
            L10n.string("onboarding.tab.welcome", default: "Welcome", locale: locale),
            L10n.string("onboarding.tab.howItWorks", default: "How It Works", locale: locale),
            L10n.string("onboarding.tab.permissions", default: "Permissions", locale: locale),
            L10n.string("onboarding.tab.setup", default: "Setup", locale: locale),
            L10n.string("onboarding.tab.style", default: "Style", locale: locale),
            L10n.string("onboarding.tab.ready", default: "Ready", locale: locale),
        ]
    }

    static func primaryActionTitle(isLastStep: Bool, accessibilityGranted: Bool, locale: Locale? = nil) -> String {
        if isLastStep {
            return accessibilityGranted
                ? L10n.string("onboarding.action.start", default: "Start Using Jack", locale: locale)
                : L10n.string("onboarding.action.grantAccessibility", default: "Grant Accessibility to Start", locale: locale)
        }
        return L10n.string("onboarding.action.continue", default: "Continue", locale: locale)
    }

    static func welcomeTagline(locale: Locale? = nil) -> String {
        L10n.string("onboarding.welcome.tagline", default: "Your clipboard, elevated.", locale: locale)
    }

    static func welcomeHints(locale: Locale? = nil) -> [String] {
        [
            L10n.string("onboarding.welcome.hint.capture", default: "Every copy, remembered.", locale: locale),
            L10n.string("onboarding.welcome.hint.organize", default: "Organized into folders.", locale: locale),
            L10n.string("onboarding.welcome.hint.shortcut", default: "One shortcut away.", locale: locale),
        ]
    }

    static func languageTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.language.title", default: "App Language", locale: locale)
    }

    static func languageSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.language.subtitle",
            default: "Pick the language you want to use. You can change this later in Settings.",
            locale: locale
        )
    }

    static func howItWorksTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.howItWorks.title", default: "How Jack Works", locale: locale)
    }

    static func howItWorksSubtitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.howItWorks.subtitle", default: "Three steps, zero effort.", locale: locale)
    }

    static func howItWorksCards(locale: Locale? = nil) -> [OnboardingHowItWorksCardCopy] {
        [
            .init(
                number: "01",
                title: L10n.string("onboarding.howItWorks.capture.title", default: "Intelligent Capture", locale: locale),
                description: L10n.string(
                    "onboarding.howItWorks.capture.description",
                    default: "Jack silently preserves everything you copy, from code to images.",
                    locale: locale
                )
            ),
            .init(
                number: "02",
                title: L10n.string("onboarding.howItWorks.shelf.title", default: "The Visual Shelf", locale: locale),
                description: L10n.string(
                    "onboarding.howItWorks.shelf.description",
                    default: "Access your history through a beautiful, organized overlay.",
                    locale: locale
                )
            ),
            .init(
                number: "03",
                title: L10n.string("onboarding.howItWorks.action.title", default: "Instant Action", locale: locale),
                description: L10n.string(
                    "onboarding.howItWorks.action.description",
                    default: "Double-tap or hit Enter to paste directly into your active app.",
                    locale: locale
                )
            ),
        ]
    }

    static func permissionsTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.title", default: "Permissions", locale: locale)
    }

    static func permissionsSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.permissions.subtitle",
            default: "Jack needs two things to work seamlessly.",
            locale: locale
        )
    }

    static func clipboardPermissionTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.clipboard.title", default: "Clipboard", locale: locale)
    }

    static func clipboardPermissionSubtitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.clipboard.subtitle", default: "Read what you copy", locale: locale)
    }

    static func accessibilityPermissionTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.accessibility.title", default: "Accessibility", locale: locale)
    }

    static func accessibilityPermissionSubtitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.accessibility.subtitle", default: "Paste into any app", locale: locale)
    }

    static func permissionActiveLabel(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.status.active", default: "Active", locale: locale)
    }

    static func permissionEnableLabel(locale: Locale? = nil) -> String {
        L10n.string("onboarding.permissions.action.enable", default: "Enable", locale: locale)
    }

    static func setupTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.title", default: "Quick Setup", locale: locale)
    }

    static func setupSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.setup.subtitle",
            default: "Fine-tune to your workflow. Change anytime in Settings.",
            locale: locale
        )
    }

    static func globalHotkeyTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.globalHotkey.title", default: "Global Hotkey", locale: locale)
    }

    static func globalHotkeySubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.setup.globalHotkey.subtitle",
            default: "Press this shortcut anywhere to summon Jack instantly",
            locale: locale
        )
    }

    static func launchAtLoginTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.launchAtLogin.title", default: "Launch at Login", locale: locale)
    }

    static func launchAtLoginSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.setup.launchAtLogin.subtitle",
            default: "Start Jack when your Mac boots up",
            locale: locale
        )
    }

    static func enabledStatus(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.status.enabled", default: "Enabled", locale: locale)
    }

    static func disabledStatus(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.status.disabled", default: "Disabled", locale: locale)
    }

    static func historyDurationTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.historyDuration.title", default: "History Duration", locale: locale)
    }

    static func historyDurationSubtitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.setup.historyDuration.subtitle", default: "How long to keep items", locale: locale)
    }

    static func styleTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.style.title", default: "Choose Your Style", locale: locale)
    }

    static func styleSubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.style.subtitle",
            default: "Click each to see how Jack appears on your screen.",
            locale: locale
        )
    }

    static func modeDescription(for mode: ViewMode, locale: Locale? = nil) -> String {
        switch mode {
        case .tray:
            return L10n.string(
                "onboarding.style.mode.tray.description",
                default: "Bottom shelf with horizontal card scrolling. Always accessible at the edge of your screen.",
                locale: locale
            )
        case .drawer:
            return L10n.string(
                "onboarding.style.mode.drawer.description",
                default: "Side panel with vertical clip list. Slides in from the edge of your display.",
                locale: locale
            )
        case .panel:
            return L10n.string(
                "onboarding.style.mode.panel.description",
                default: "Compact pop-up at your cursor with a vertical stack of clips. Pin the ones you need often.",
                locale: locale
            )
        case .grid:
            return L10n.string(
                "onboarding.style.mode.grid.description",
                default: "Floating window with organized card grid. Appears centered on your screen.",
                locale: locale
            )
        case .radial:
            return L10n.string(
                "onboarding.style.mode.radial.description",
                default: "Quick-access ring at cursor position. The fastest way to find and paste.",
                locale: locale
            )
        case .workspace:
            return L10n.string(
                "onboarding.style.mode.workspace.description",
                default: "Desktop workspace with clipboard, tasks, pulse, and meetings.",
                locale: locale
            )
        }
    }

    static func readyTitle(locale: Locale? = nil) -> String {
        L10n.string("onboarding.ready.title", default: "You're all set", locale: locale)
    }

    static func readySubtitle(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.ready.subtitle",
            default: "Jack is now active and guarding your clipboard.\nEverything you copy is saved automatically.",
            locale: locale
        )
    }

    static func readyAccessibilityWarning(locale: Locale? = nil) -> String {
        L10n.string(
            "onboarding.ready.accessibilityWarning",
            default: "Paste into other apps stays off until Accessibility is enabled in System Settings.",
            locale: locale
        )
    }

    static func toggleShelfLabel(locale: Locale? = nil) -> String {
        L10n.string("onboarding.ready.toggleShelf", default: "Toggle Shelf:", locale: locale)
    }
}
