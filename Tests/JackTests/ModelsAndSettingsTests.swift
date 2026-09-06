import Carbon.HIToolbox
import XCTest
@testable import Gilt

final class ModelsAndSettingsTests: XCTestCase {

    // MARK: - HistoryRetention (independently-derived values)

    func testRetentionDayIs24Hours() {
        // 24 hours × 60 min × 60 sec — derived independently, not copied from source
        XCTAssertEqual(HistoryRetention.day.maxAgeSeconds, 24 * 60 * 60)
    }

    func testRetentionWeekIs7Days() {
        XCTAssertEqual(HistoryRetention.week.maxAgeSeconds, 7 * 24 * 60 * 60)
    }

    func testRetentionMonthIs30Days() {
        XCTAssertEqual(HistoryRetention.month.maxAgeSeconds, 30 * 24 * 60 * 60)
    }

    func testRetentionForeverIsNil() {
        XCTAssertNil(HistoryRetention.forever.maxAgeSeconds)
    }

    func testRetentionLabelsAreCapitalizedRawValues() {
        XCTAssertEqual(HistoryRetention.day.label, "Day")
        XCTAssertEqual(HistoryRetention.week.label, "Week")
        XCTAssertEqual(HistoryRetention.month.label, "Month")
        XCTAssertEqual(HistoryRetention.forever.label, "Forever")
    }

    func testRetentionDurationOrdering() {
        // Day < week < month — sanity check the math
        let day = HistoryRetention.day.maxAgeSeconds!
        let week = HistoryRetention.week.maxAgeSeconds!
        let month = HistoryRetention.month.maxAgeSeconds!
        XCTAssertTrue(day < week, "Day should be shorter than week")
        XCTAssertTrue(week < month, "Week should be shorter than month")
        XCTAssertEqual(week, day * 7, "Week should be exactly 7 days")
    }

    // MARK: - SensitiveExpiry (independently-derived values)

    func testSensitiveExpiry5MinIs300Seconds() {
        XCTAssertEqual(SensitiveExpiry.fiveMinutes.seconds, 5 * 60)
    }

    func testSensitiveExpiry15MinIs900Seconds() {
        XCTAssertEqual(SensitiveExpiry.fifteenMinutes.seconds, 15 * 60)
    }

    func testSensitiveExpiry1HourIs3600Seconds() {
        XCTAssertEqual(SensitiveExpiry.oneHour.seconds, 60 * 60)
    }

    func testSensitiveExpiryNeverIsNil() {
        XCTAssertNil(SensitiveExpiry.never.seconds)
    }

    func testSensitiveExpiryLabels() {
        XCTAssertEqual(SensitiveExpiry.fiveMinutes.label, "5 Minutes")
        XCTAssertEqual(SensitiveExpiry.fifteenMinutes.label, "15 Minutes")
        XCTAssertEqual(SensitiveExpiry.oneHour.label, "1 Hour")
        XCTAssertEqual(SensitiveExpiry.never.label, "Never")
    }

    // MARK: - SmartCategorySettings

    func testAllCategoriesEnabledByDefault() {
        let settings = SmartCategorySettings()
        for category in SmartCategory.allCases {
            XCTAssertTrue(settings.isEnabled(category), "\(category) should be enabled by default")
        }
    }

    func testDisablingAndEnablingCategory() {
        var settings = SmartCategorySettings()
        settings.setEnabled(.code, false)
        XCTAssertFalse(settings.isEnabled(.code))

        settings.setEnabled(.code, true)
        XCTAssertTrue(settings.isEnabled(.code))
    }

    func testDisablingOneCategoryDoesNotAffectOthers() {
        var settings = SmartCategorySettings()
        settings.setEnabled(.images, false)
        XCTAssertTrue(settings.isEnabled(.code), "Code should still be enabled")
        XCTAssertTrue(settings.isEnabled(.links), "Links should still be enabled")
        XCTAssertTrue(settings.isEnabled(.contacts), "Contacts should still be enabled")
        XCTAssertTrue(settings.isEnabled(.colors), "Colors should still be enabled")
        XCTAssertTrue(settings.isEnabled(.addresses), "Addresses should still be enabled")
        XCTAssertTrue(settings.isEnabled(.sensitive), "Sensitive should still be enabled")
        XCTAssertFalse(settings.isEnabled(.images), "Images should be disabled")
    }

    func testDisablingMultipleCategories() {
        var settings = SmartCategorySettings()
        settings.setEnabled(.code, false)
        settings.setEnabled(.sensitive, false)
        settings.setEnabled(.colors, false)
        XCTAssertFalse(settings.isEnabled(.code))
        XCTAssertFalse(settings.isEnabled(.sensitive))
        XCTAssertFalse(settings.isEnabled(.colors))
        XCTAssertTrue(settings.isEnabled(.links))
        XCTAssertTrue(settings.isEnabled(.images))
    }

    func testSmartCategorySettingsDefaultExpiry() {
        let settings = SmartCategorySettings()
        XCTAssertFalse(settings.autoExpireSensitive, "Auto-expire should be off by default")
        XCTAssertEqual(settings.sensitiveExpiry, .fifteenMinutes, "Default expiry should be 15 minutes")
    }

    func testSmartCategorySettingsJSONRoundTrip() throws {
        var original = SmartCategorySettings()
        original.setEnabled(.code, false)
        original.setEnabled(.sensitive, false)
        original.autoExpireSensitive = true
        original.sensitiveExpiry = .oneHour

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SmartCategorySettings.self, from: data)

        XCTAssertFalse(decoded.isEnabled(.code))
        XCTAssertFalse(decoded.isEnabled(.sensitive))
        XCTAssertTrue(decoded.isEnabled(.links))
        XCTAssertTrue(decoded.autoExpireSensitive)
        XCTAssertEqual(decoded.sensitiveExpiry, .oneHour)
    }

    func testPulseCharacterMessageSettingsRoundTrip() throws {
        var settings = AppSettings()
        let reminderID = UUID()
        settings.pulseCharacterMessageMode = .remindersAndInspiration
        settings.pulseCharacterCustomMessage = "Stretch before the next deep work block."
        settings.pulseReminders = [
            PulseReminder(
                id: reminderID,
                message: "Review the launch checklist",
                sourceTitle: "Launch",
                createdAt: Date(timeIntervalSince1970: 100),
                dueAt: Date(timeIntervalSince1970: 200)
            )
        ]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.pulseCharacterMessageMode, .remindersAndInspiration)
        XCTAssertEqual(decoded.pulseCharacterCustomMessage, "Stretch before the next deep work block.")
        XCTAssertEqual(decoded.pulseReminders.count, 1)
        XCTAssertEqual(decoded.pulseReminders.first?.id, reminderID)
        XCTAssertEqual(decoded.pulseReminders.first?.message, "Review the launch checklist")
    }

    func testPulseMessageFrequencyOptionsIncludeDailyWithoutChangingUsageRefreshOptions() {
        XCTAssertTrue(PulseRefreshInterval.messageFrequencyOptions.contains(.oneDay))
        XCTAssertEqual(PulseRefreshInterval.oneDay.seconds, 24 * 60 * 60)
        XCTAssertFalse(PulseRefreshInterval.usageRefreshOptions.contains(.oneDay))
    }

    func testSmartCategorySettingsDecodesEmptyJSONWithDefaults() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SmartCategorySettings.self, from: data)

        for category in SmartCategory.allCases {
            XCTAssertTrue(decoded.isEnabled(category), "\(category) should default to enabled")
        }
        XCTAssertFalse(decoded.autoExpireSensitive)
        XCTAssertEqual(decoded.sensitiveExpiry, .fifteenMinutes)
    }

    // MARK: - Custom Folder Visibility

    func testCustomFoldersAreVisibleByDefault() {
        let settings = AppSettings()
        let customFolderID = UUID()

        XCTAssertTrue(settings.isCustomFolderVisible(customFolderID))
    }

    func testCustomFolderVisibilityCanBeDisabledAndRestored() {
        var settings = AppSettings()
        let customFolderID = UUID()

        settings.setCustomFolderVisibility(false, for: customFolderID)
        XCTAssertFalse(settings.isCustomFolderVisible(customFolderID))

        settings.setCustomFolderVisibility(true, for: customFolderID)
        XCTAssertTrue(settings.isCustomFolderVisible(customFolderID))
    }

    func testFolderTabVisibilityOnlyHidesCustomFolders() {
        var settings = AppSettings()
        let customFolder = ClipFolderModel(name: "Commands")
        let smartFolder = ClipFolderModel(
            folderID: SmartCategory.code.folderID,
            name: "Code",
            isSystem: true,
            smartCategoryRaw: SmartCategory.code.rawValue
        )
        let systemFolder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Clipboard",
            isSystem: true
        )

        settings.setCustomFolderVisibility(false, for: customFolder.folderID)

        XCTAssertFalse(settings.isFolderVisibleInTabs(customFolder))
        XCTAssertTrue(settings.isFolderVisibleInTabs(smartFolder))
        XCTAssertTrue(settings.isFolderVisibleInTabs(systemFolder))
    }

    func testCustomFolderVisibilityRoundTripsThroughJSON() throws {
        var original = AppSettings()
        let hiddenFolderID = UUID()
        original.setCustomFolderVisibility(false, for: hiddenFolderID)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.isCustomFolderVisible(hiddenFolderID))
    }

    // MARK: - SmartCategory Properties

    func testSmartCategoryFolderNames() {
        XCTAssertEqual(SmartCategory.code.folderName, "Code")
        XCTAssertEqual(SmartCategory.images.folderName, "Images")
        XCTAssertEqual(SmartCategory.links.folderName, "Links")
        XCTAssertEqual(SmartCategory.contacts.folderName, "Contacts")
        XCTAssertEqual(SmartCategory.colors.folderName, "Colors")
        XCTAssertEqual(SmartCategory.addresses.folderName, "Addresses")
        XCTAssertEqual(SmartCategory.sensitive.folderName, "Sensitive")
    }

    func testSmartCategoryFolderIDsAreAllUnique() {
        let ids = SmartCategory.allCases.map(\.folderID)
        XCTAssertEqual(ids.count, Set(ids).count, "All smart categories must have unique folder IDs")
    }

    func testSmartCategoryFolderIDsMatchExpectedValues() {
        // Verify the actual UUID values — catches accidental edits
        XCTAssertEqual(
            SmartCategory.code.folderID,
            UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000001")!
        )
        XCTAssertEqual(
            SmartCategory.sensitive.folderID,
            UUID(uuidString: "A1B2C3D4-0007-4000-8000-000000000007")!
        )
    }

    func testSmartCategoryFolderColors() {
        XCTAssertEqual(SmartCategory.code.folderColor, .sapphire)
        XCTAssertEqual(SmartCategory.images.folderColor, .coral)
        XCTAssertEqual(SmartCategory.links.folderColor, .emerald)
        XCTAssertEqual(SmartCategory.contacts.folderColor, .gold)
        XCTAssertEqual(SmartCategory.colors.folderColor, .amber)
        XCTAssertEqual(SmartCategory.addresses.folderColor, .teal)
        XCTAssertEqual(SmartCategory.sensitive.folderColor, .mauve)
    }

    func testSmartCategoryDefaultFillGradientsAreValidGradientSpecs() {
        for category in SmartCategory.allCases {
            let raw = category.defaultFillGradient
            XCTAssertNotNil(
                GradientSpec(rawString: raw),
                "\(category).defaultFillGradient should be a valid GradientSpec: \(raw)"
            )
        }
    }

    func testSmartCategorySystemImages() {
        // Verify they're non-empty and specific, not just "exists"
        XCTAssertEqual(SmartCategory.code.systemImage, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(SmartCategory.images.systemImage, "photo")
        XCTAssertEqual(SmartCategory.links.systemImage, "link")
    }

    // MARK: - Folder Auto-Categorization Lock

    func testClipFolderAutoCategorizationLockDefaultsToFalse() {
        let folder = ClipFolderModel(name: "Inbox")
        XCTAssertFalse(folder.isAutoCategorizationLocked)
    }

    func testClipFolderAutoCategorizationLockCanBeEnabled() {
        let folder = ClipFolderModel(name: "Code", isAutoCategorizationLocked: true)
        XCTAssertTrue(folder.isAutoCategorizationLocked)
    }

    func testClipboardFolderDoesNotSupportSeparators() {
        let folder = ClipFolderModel(
            folderID: ClipFolderModel.clipboardID,
            name: "Clipboard",
            isSystem: true
        )

        XCTAssertTrue(folder.isClipboardFolder)
        XCTAssertFalse(folder.supportsSeparators)
    }

    func testRegularFolderSupportsSeparators() {
        let folder = ClipFolderModel(name: "Projects")

        XCTAssertFalse(folder.isClipboardFolder)
        XCTAssertTrue(folder.supportsSeparators)
    }

    func testSmartFolderSupportsSeparators() {
        let folder = ClipFolderModel(
            name: SmartCategory.code.folderName,
            isSystem: true,
            smartCategoryRaw: SmartCategory.code.rawValue
        )

        XCTAssertTrue(folder.isSmartFolder)
        XCTAssertTrue(folder.supportsSeparators)
    }

    func testSeparatorMoveDirectionRawValues() {
        XCTAssertEqual(ClipboardStore.SeparatorMoveDirection.left.rawValue, "left")
        XCTAssertEqual(ClipboardStore.SeparatorMoveDirection.right.rawValue, "right")
    }

    func testFolderSeparatorDefaultsToSlateColor() {
        let separator = FolderSeparatorModel()

        XCTAssertEqual(separator.resolvedColor, .token(.slate))
    }

    func testFolderSeparatorUsesExplicitTokenColor() {
        let separator = FolderSeparatorModel(colorRaw: FolderColorToken.emerald.rawValue)

        XCTAssertEqual(separator.resolvedColor, .token(.emerald))
    }

    func testFolderSeparatorPreservesCustomHexColor() {
        let separator = FolderSeparatorModel(colorRaw: "#12ABCD")

        XCTAssertEqual(separator.resolvedColor, .hex("#12ABCD"))
    }

    func testClipTypeThemeDecodesWithoutBadgeColorForBackwardsCompatibility() throws {
        let data = try XCTUnwrap("""
        {"accentRaw":"#123456","headerRaw":"#654321"}
        """.data(using: .utf8))

        let theme = try JSONDecoder().decode(ClipTypeTheme.self, from: data)

        XCTAssertEqual(theme.accentRaw, "#123456")
        XCTAssertEqual(theme.headerRaw, "#654321")
        XCTAssertNil(theme.badgeRaw)
    }

    func testClipFolderUsesCustomEmojiIconWhenPresent() {
        let folder = ClipFolderModel(name: "Notes", folderIconRaw: "📝")
        XCTAssertEqual(folder.customFolderIcon, .glyph("📝"))
        XCTAssertEqual(folder.effectiveFolderIcon, .glyph("📝"))
    }

    func testSmartFolderFallsBackToDefaultSystemIcon() {
        let folder = ClipFolderModel(name: "Code", smartCategoryRaw: SmartCategory.code.rawValue)
        XCTAssertEqual(folder.effectiveFolderIcon, .symbol(SmartCategory.code.systemImage))
    }

    func testFolderIconSymbolEncodingRoundTrips() {
        let icon = FolderIcon.symbol("tray.full")
        XCTAssertEqual(FolderIcon(rawValue: icon.rawValue), icon)
    }

    // MARK: - GlobalShortcut Display String

    func testShortcutDisplayStringCmd() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertEqual(shortcut.displayString, "Cmd+C")
    }

    func testShortcutDisplayStringCmdShift() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        XCTAssertEqual(shortcut.displayString, "Cmd+Shift+V")
    }

    func testShortcutDisplayStringCtrlOption() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey)
        )
        XCTAssertEqual(shortcut.displayString, "Option+Ctrl+V")
    }

    func testShortcutDisplayStringAllModifiers() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(shortcut.displayString, "Cmd+Shift+Option+Ctrl+A")
    }

    func testShortcutKeyDisplayName() {
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_Return)), "Return")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_Space)), "Space")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_Tab)), "Tab")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_Delete)), "Delete")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_Escape)), "Escape")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_ANSI_A)), "A")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_ANSI_Z)), "Z")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_ANSI_0)), "0")
        XCTAssertEqual(GlobalShortcut.displayName(for: UInt32(kVK_ANSI_9)), "9")
    }

    func testUnknownKeyCodeReturnsKeyPrefix() {
        let display = GlobalShortcut.displayName(for: 999)
        XCTAssertEqual(display, "Key999", "Unknown key codes should return 'Key<number>'")
    }

    func testDefaultShortcutIsCtrlV() {
        let def = GlobalShortcut.default
        XCTAssertEqual(def.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(def.modifiers, UInt32(controlKey))
        XCTAssertEqual(def.displayString, "Ctrl+V")
    }

    func testLegacyDefaultShortcutIsCmdShiftV() {
        let legacy = GlobalShortcut.legacyDefault
        XCTAssertEqual(legacy.displayString, "Cmd+Shift+V")
    }

    func testShortcutEquality() {
        let a = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey))
        let b = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey))
        let c = GlobalShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))
        XCTAssertEqual(a, b, "Same key + modifiers should be equal")
        XCTAssertNotEqual(a, c, "Different keys should not be equal")
    }

    // MARK: - ResolvedColor

    func testResolvedColorFromHex() {
        let color = ResolvedColor(rawString: "#FF5733")
        guard case .hex(let hex) = color else {
            XCTFail("Should resolve as .hex, got \(color)")
            return
        }
        XCTAssertEqual(hex, "#FF5733")
    }

    func testResolvedColorFromAllTokens() {
        // Every FolderColorToken should round-trip through ResolvedColor
        for token in FolderColorToken.allCases {
            let resolved = ResolvedColor(rawString: token.rawValue)
            guard case .token(let t) = resolved else {
                XCTFail("\(token.rawValue) should resolve as .token, got \(resolved)")
                continue
            }
            XCTAssertEqual(t, token)
        }
    }

    func testResolvedColorFallsBackToSlate() {
        let color = ResolvedColor(rawString: "nonsense")
        guard case .token(let token) = color else {
            XCTFail("Should resolve as .token(.slate)")
            return
        }
        XCTAssertEqual(token, .slate, "Unknown strings should fall back to slate")
    }

    func testResolvedColorEmptyStringFallsBackToSlate() {
        let color = ResolvedColor(rawString: "")
        guard case .token(let token) = color else {
            XCTFail("Empty string should resolve as .token(.slate)")
            return
        }
        XCTAssertEqual(token, .slate)
    }

    func testResolvedColorHashOnlyIsHex() {
        // "#" alone — starts with "#" so treated as hex
        let color = ResolvedColor(rawString: "#")
        guard case .hex(let hex) = color else {
            XCTFail("'#' should resolve as .hex, got \(color)")
            return
        }
        XCTAssertEqual(hex, "#")
    }

    func testResolvedColorRawStringRoundTrip() {
        // Hex round-trip
        let hexOriginal = "#AABBCC"
        XCTAssertEqual(ResolvedColor(rawString: hexOriginal).rawString, hexOriginal)

        // Token round-trip
        let tokenOriginal = "gold"
        XCTAssertEqual(ResolvedColor(rawString: tokenOriginal).rawString, tokenOriginal)

        // Fallback gives slate's raw value
        let fallback = ResolvedColor(rawString: "garbage")
        XCTAssertEqual(fallback.rawString, "slate")
    }

    // MARK: - GradientSpec

    func testGradientSpecParsesValidString() {
        guard let grad = GradientSpec(rawString: "grad:#FF0000,#00FF00,135.0") else {
            XCTFail("Should parse valid gradient string")
            return
        }
        XCTAssertEqual(grad.color1, "#FF0000")
        XCTAssertEqual(grad.color2, "#00FF00")
        XCTAssertEqual(grad.angle, 135.0)
    }

    func testGradientSpecDefaultAngle() {
        guard let grad = GradientSpec(rawString: "grad:#FF0000,#00FF00") else {
            XCTFail("Should parse gradient without angle")
            return
        }
        XCTAssertEqual(grad.angle, 180.0, "Missing angle should default to 180")
    }

    func testGradientSpecRejectsNonGradString() {
        XCTAssertNil(GradientSpec(rawString: "#FF0000"))
        XCTAssertNil(GradientSpec(rawString: "gold"))
        XCTAssertNil(GradientSpec(rawString: ""))
    }

    func testGradientSpecRejectsSingleColor() {
        // "grad:" prefix but only one color
        XCTAssertNil(GradientSpec(rawString: "grad:#FF0000"))
    }

    func testGradientSpecRejectsEmptyAfterPrefix() {
        XCTAssertNil(GradientSpec(rawString: "grad:"))
    }

    func testGradientSpecNonNumericAngleDefaultsTo180() {
        guard let grad = GradientSpec(rawString: "grad:#AA0000,#00BB00,notanumber") else {
            XCTFail("Should still parse with invalid angle")
            return
        }
        XCTAssertEqual(grad.angle, 180.0, "Non-numeric angle should fall back to 180")
    }

    func testGradientSpecSerializationRoundTrip() {
        let spec = GradientSpec(color1: "#AA0000", color2: "#00BB00", angle: 45.0)
        let serialized = spec.serialized
        XCTAssertTrue(serialized.hasPrefix("grad:"), "Serialized should start with 'grad:'")

        guard let parsed = GradientSpec(rawString: serialized) else {
            XCTFail("Should re-parse serialized gradient")
            return
        }
        XCTAssertEqual(parsed.color1, "#AA0000")
        XCTAssertEqual(parsed.color2, "#00BB00")
        XCTAssertEqual(parsed.angle, 45.0)
    }

    func testGradientSpecDirectInit() {
        let spec = GradientSpec(color1: "#111111", color2: "#222222")
        XCTAssertEqual(spec.angle, 180.0, "Direct init default angle should be 180")
        XCTAssertEqual(spec.color1, "#111111")
        XCTAssertEqual(spec.color2, "#222222")
    }

    func testGradientSpecCodableRoundTrip() throws {
        let spec = GradientSpec(color1: "#FF0000", color2: "#0000FF", angle: 90.0)
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(GradientSpec.self, from: data)
        XCTAssertEqual(decoded, spec)
    }

    // MARK: - FolderColorValue

    func testFolderColorValueSolid() {
        let value = FolderColorValue(rawString: "coral")
        XCTAssertFalse(value.isGradient)
        XCTAssertEqual(value.rawString, "coral")
    }

    func testFolderColorValueGradient() {
        let value = FolderColorValue(rawString: "grad:#FF0000,#0000FF,90.0")
        XCTAssertTrue(value.isGradient)
    }

    func testFolderColorValueRawStringRoundTrip() {
        let solidOriginal = "emerald"
        XCTAssertEqual(FolderColorValue(rawString: solidOriginal).rawString, solidOriginal)

        let gradOriginal = "grad:#AABB00,#00CCDD,120.0"
        XCTAssertEqual(FolderColorValue(rawString: gradOriginal).rawString, gradOriginal)
    }

    func testFolderColorValueUnknownStringFallsToSlateSolid() {
        let value = FolderColorValue(rawString: "unknowncolor")
        XCTAssertFalse(value.isGradient)
        // Falls through to ResolvedColor → .token(.slate)
        XCTAssertEqual(value.rawString, "slate")
    }

    // MARK: - ClipItemModel Computed Properties

    func testClipTypeParsesAllValidRawValues() {
        for clipType in ClipType.allCases {
            let clip = ClipItemModel(typeRaw: clipType.rawValue, title: "t", previewText: "p", sourceAppName: "s")
            XCTAssertEqual(clip.clipType, clipType, "\(clipType.rawValue) should parse to \(clipType)")
        }
    }

    func testClipTypeDefaultsToTextForInvalidRaw() {
        let clip = ClipItemModel(typeRaw: "invalid", title: "t", previewText: "p", sourceAppName: "s")
        XCTAssertEqual(clip.clipType, .text, "Invalid type raw should default to .text")
    }

    func testClipTypeDefaultsToTextForEmptyRaw() {
        let clip = ClipItemModel(typeRaw: "", title: "t", previewText: "p", sourceAppName: "s")
        XCTAssertEqual(clip.clipType, .text, "Empty type raw should default to .text")
    }

    func testContentTagsRoundTrip() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        clip.contentTags = [.code, .email]

        let tags = clip.contentTags
        XCTAssertTrue(tags.contains(.code), "Should contain .code")
        XCTAssertTrue(tags.contains(.email), "Should contain .email")
        XCTAssertEqual(tags.count, 2)
    }

    func testContentTagsAllTagsRoundTrip() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        let allTags = Set(ContentTag.allCases)
        clip.contentTags = allTags

        let recovered = clip.contentTags
        XCTAssertEqual(recovered, allTags, "All content tags should survive round-trip")
    }

    func testContentTagsEmptyByDefault() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        XCTAssertTrue(clip.contentTags.isEmpty)
        XCTAssertEqual(clip.contentTagsRaw, "")
    }

    func testContentTagsWithGarbageRawReturnsEmpty() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        clip.contentTagsRaw = "notreal,alsofake,garbage"
        XCTAssertTrue(clip.contentTags.isEmpty, "Invalid tag strings should be filtered out")
    }

    func testContentTagsWithMixedValidAndInvalidRaw() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        clip.contentTagsRaw = "code,garbage,email"
        let tags = clip.contentTags
        XCTAssertEqual(tags.count, 2, "Should only keep valid tags")
        XCTAssertTrue(tags.contains(.code))
        XCTAssertTrue(tags.contains(.email))
    }

    func testDetectedLanguageRoundTrip() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        for lang in DetectedLanguage.allCases {
            clip.detectedLanguage = lang
            XCTAssertEqual(clip.detectedLanguage, lang, "\(lang) should round-trip")
        }
    }

    func testDetectedLanguageNilByDefault() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        XCTAssertNil(clip.detectedLanguage)
        XCTAssertNil(clip.detectedLanguageRaw)
    }

    func testDetectedLanguageInvalidRawReturnsNil() {
        let clip = ClipItemModel(typeRaw: "text", title: "t", previewText: "p", sourceAppName: "s")
        clip.detectedLanguageRaw = "klingon"
        XCTAssertNil(clip.detectedLanguage, "Invalid language raw should return nil")
    }

    func testLinkPlatformComputedProperty() {
        let clip = ClipItemModel(typeRaw: "link", title: "t", previewText: "p", sourceAppName: "s")
        XCTAssertNil(clip.linkPlatform, "Should be nil when linkPlatformRaw is nil")

        clip.linkPlatformRaw = "youtube"
        XCTAssertEqual(clip.linkPlatform, .youtube)

        clip.linkPlatformRaw = "invalid"
        XCTAssertNil(clip.linkPlatform, "Invalid platform raw should return nil")
    }

    func testLinkFaviconURLComputedProperty() {
        let clip = ClipItemModel(typeRaw: "link", title: "t", previewText: "p", sourceAppName: "s")
        XCTAssertNil(clip.linkFaviconURL, "Should be nil when no URL string set")

        clip.linkFaviconURLString = "https://example.com/favicon.ico"
        XCTAssertEqual(clip.linkFaviconURL?.absoluteString, "https://example.com/favicon.ico")
    }

    // MARK: - AppSettings Defaults

    func testDefaultSettingsValues() {
        let settings = AppSettings()
        XCTAssertEqual(settings.historyRetention, .week)
        XCTAssertFalse(settings.alwaysPlainText)
        XCTAssertTrue(settings.pasteToActiveApp)
        XCTAssertFalse(settings.singleClickToPaste)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.showInMenuBar)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(settings.alwaysShowOnboarding)
        XCTAssertFalse(settings.trackpadRevealBottomEdgeSwipeEnabled)
        XCTAssertFalse(settings.trackpadRevealBottomCenterSwipeEnabled)
        XCTAssertEqual(settings.backgroundTheme, .scenic)
        XCTAssertEqual(settings.clipboardFont, .sfPro)
        XCTAssertEqual(settings.backgroundOpacity, 0.5)
        XCTAssertEqual(settings.backgroundWallpaper, .terra)
        XCTAssertEqual(settings.globalShortcut, .default)
        XCTAssertEqual(settings.trayAnimationSpeed, 0, accuracy: 0.001)
        XCTAssertNil(settings.customBackgroundGradient)
        XCTAssertTrue(settings.savedColorPresets.isEmpty)
        XCTAssertNil(settings.customWallpaperFilename)
        XCTAssertEqual(settings.wallpaperOffsetX, 0.5)
        XCTAssertEqual(settings.wallpaperOffsetY, 0.5)
        XCTAssertEqual(settings.radialSwipeDirection, .natural)
        XCTAssertEqual(settings.radialPageSwipeSensitivity, 0.6, accuracy: 0.001)
        XCTAssertTrue(settings.clipTypeThemes.isEmpty)
        XCTAssertFalse(settings.pulseCharactersEnabled)
        XCTAssertEqual(settings.pulseCharacterTriggerMode, .interval)
    }

    func testMenuBarTextColorHexRoundTrip() throws {
        var original = AppSettings()
        original.menuBarShowCustomText = true
        original.menuBarCustomText = "Focus"
        original.menuBarTextColorHex = "#C4A882"
        original.menuBarPopoverTextColorHex = "#1A2030"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.menuBarTextColorHex, "#C4A882")
        XCTAssertEqual(decoded.menuBarPopoverTextColorHex, "#1A2030")
        XCTAssertEqual(decoded.menuBarCustomText, "Focus")
    }

    // MARK: - AppSettings JSON Round-Trip (comprehensive)

    func testSettingsFullRoundTrip() throws {
        var original = AppSettings()
        original.historyRetention = .month
        original.alwaysPlainText = true
        original.pasteToActiveApp = false
        original.singleClickToPaste = true
        original.launchAtLogin = true
        original.showInMenuBar = false
        original.globalShortcut = .legacyDefault
        original.trayAnimationSpeed = 0.75
        original.trackpadRevealBottomEdgeSwipeEnabled = true
        original.trackpadRevealBottomCenterSwipeEnabled = true
        original.backgroundTheme = .midnight
        original.clipboardFont = .instrumentSans
        original.backgroundOpacity = 0.8
        original.backgroundWallpaper = .none
        original.hasCompletedOnboarding = true
        original.alwaysShowOnboarding = true
        original.customBackgroundGradient = GradientSpec(color1: "#AA0000", color2: "#0000AA", angle: 45.0)
        original.savedColorPresets = [ColorPreset(name: "Test", rawValue: "#112233")]
        original.customWallpaperFilename = "my-wallpaper.png"
        original.wallpaperOffsetX = 0.3
        original.wallpaperOffsetY = 0.7
        original.radialSwipeDirection = .reversed
        original.radialPageSwipeSensitivity = 1.3
        original.pulseCharactersEnabled = true
        original.pulseCharacterTriggerMode = .threshold
        original.reverseQuickNoteSwipeDirection = true
        original.quickNoteNavigationControlsStyle = .minimal
        original.quickNoteAutoPasteFromClipboard = true
        original.clipTypeThemes = [
            ClipType.text.rawValue: ClipTypeTheme(
                accentRaw: "#123456",
                headerRaw: "grad:#111111,#999999,45"
            )
        ]

        var catSettings = SmartCategorySettings()
        catSettings.setEnabled(.code, false)
        catSettings.autoExpireSensitive = true
        catSettings.sensitiveExpiry = .oneHour
        original.smartCategories = catSettings

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.historyRetention, .month)
        XCTAssertTrue(decoded.alwaysPlainText)
        XCTAssertFalse(decoded.pasteToActiveApp)
        XCTAssertTrue(decoded.singleClickToPaste)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertFalse(decoded.showInMenuBar)
        XCTAssertEqual(decoded.globalShortcut, .legacyDefault)
        XCTAssertEqual(decoded.trayAnimationSpeed, 0.75, accuracy: 0.001)
        XCTAssertTrue(decoded.trackpadRevealBottomEdgeSwipeEnabled)
        XCTAssertTrue(decoded.trackpadRevealBottomCenterSwipeEnabled)
        XCTAssertEqual(decoded.backgroundTheme, .midnight)
        XCTAssertEqual(decoded.clipboardFont, .instrumentSans)
        XCTAssertEqual(decoded.backgroundOpacity, 0.8)
        XCTAssertEqual(decoded.backgroundWallpaper, .none)
        XCTAssertTrue(decoded.hasCompletedOnboarding)
        XCTAssertTrue(decoded.alwaysShowOnboarding)
        XCTAssertEqual(decoded.customBackgroundGradient?.color1, "#AA0000")
        XCTAssertEqual(decoded.customBackgroundGradient?.angle, 45.0)
        XCTAssertEqual(decoded.savedColorPresets.count, 1)
        XCTAssertEqual(decoded.savedColorPresets.first?.name, "Test")
        XCTAssertEqual(decoded.customWallpaperFilename, "my-wallpaper.png")
        XCTAssertEqual(decoded.wallpaperOffsetX, 0.3)
        XCTAssertEqual(decoded.wallpaperOffsetY, 0.7)
        XCTAssertEqual(decoded.radialSwipeDirection, .reversed)
        XCTAssertEqual(decoded.radialPageSwipeSensitivity, 1.3, accuracy: 0.001)
        XCTAssertTrue(decoded.pulseCharactersEnabled)
        XCTAssertEqual(decoded.pulseCharacterTriggerMode, .threshold)
        XCTAssertTrue(decoded.reverseQuickNoteSwipeDirection)
        XCTAssertEqual(decoded.quickNoteNavigationControlsStyle, .minimal)
        XCTAssertTrue(decoded.quickNoteAutoPasteFromClipboard)
        XCTAssertEqual(decoded.clipTypeThemes[ClipType.text.rawValue]?.accentRaw, "#123456")
        XCTAssertEqual(decoded.clipTypeThemes[ClipType.text.rawValue]?.headerRaw, "grad:#111111,#999999,45")
        XCTAssertFalse(decoded.smartCategories.isEnabled(.code))
        XCTAssertTrue(decoded.smartCategories.autoExpireSensitive)
        XCTAssertEqual(decoded.smartCategories.sensitiveExpiry, .oneHour)
    }

    func testSettingsDecodesWithMissingKeysUsingDefaults() throws {
        let json = """
        {"historyRetention": "day"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.historyRetention, .day)
        // Everything else should be defaults
        XCTAssertFalse(decoded.alwaysPlainText)
        XCTAssertTrue(decoded.pasteToActiveApp)
        XCTAssertFalse(decoded.singleClickToPaste)
        XCTAssertFalse(decoded.launchAtLogin)
        XCTAssertTrue(decoded.showInMenuBar)
        XCTAssertFalse(decoded.trackpadRevealBottomEdgeSwipeEnabled)
        XCTAssertFalse(decoded.trackpadRevealBottomCenterSwipeEnabled)
        XCTAssertEqual(decoded.backgroundTheme, .scenic)
        XCTAssertEqual(decoded.clipboardFont, .sfPro)
        XCTAssertEqual(decoded.backgroundOpacity, 0.5)
        XCTAssertEqual(decoded.backgroundWallpaper, .terra)
        XCTAssertFalse(decoded.hasCompletedOnboarding)
        XCTAssertNil(decoded.customBackgroundGradient)
        XCTAssertTrue(decoded.savedColorPresets.isEmpty)
        XCTAssertEqual(decoded.wallpaperOffsetX, 0.5)
        XCTAssertEqual(decoded.wallpaperOffsetY, 0.5)
        XCTAssertEqual(decoded.radialSwipeDirection, .natural)
        XCTAssertFalse(decoded.reverseQuickNoteSwipeDirection)
        XCTAssertEqual(decoded.quickNoteNavigationControlsStyle, .standard)
        XCTAssertFalse(decoded.quickNoteAutoPasteFromClipboard)
        XCTAssertEqual(decoded.radialPageSwipeSensitivity, 0.6, accuracy: 0.001)
        XCTAssertEqual(decoded.trayAnimationSpeed, 0, accuracy: 0.001)
        XCTAssertTrue(decoded.clipTypeThemes.isEmpty)
    }

    func testTrayAnimationSpeedIsClampedOnDecode() throws {
        let tooFast = try JSONDecoder().decode(
            AppSettings.self,
            from: #"{"trayAnimationSpeed": 4.0}"#.data(using: .utf8)!
        )
        let tooSlow = try JSONDecoder().decode(
            AppSettings.self,
            from: #"{"trayAnimationSpeed": -2.0}"#.data(using: .utf8)!
        )

        XCTAssertEqual(tooFast.trayAnimationSpeed, 1, accuracy: 0.001)
        XCTAssertEqual(tooSlow.trayAnimationSpeed, 0, accuracy: 0.001)
    }

    func testSettingsDecodesCompletelyEmptyJSON() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        // Should match a fresh AppSettings()
        let fresh = AppSettings()
        XCTAssertEqual(decoded.historyRetention, fresh.historyRetention)
        XCTAssertEqual(decoded.alwaysPlainText, fresh.alwaysPlainText)
        XCTAssertEqual(decoded.singleClickToPaste, fresh.singleClickToPaste)
        XCTAssertEqual(decoded.backgroundTheme, fresh.backgroundTheme)
        XCTAssertEqual(decoded.clipboardFont, fresh.clipboardFont)
        XCTAssertEqual(decoded.backgroundOpacity, fresh.backgroundOpacity)
    }

    func testTrayFlowSettingsDecodeAndDefaultSafely() throws {
        let json = """
        {
          "showInMenuBar": false,
          "scrollToLatestOnShow": false,
          "newestTrayClipsOnRight": true,
          "backgroundTheme": "midnight"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.showInMenuBar)
        XCTAssertEqual(decoded.backgroundTheme, .midnight)
        XCTAssertFalse(decoded.scrollToLatestOnShow)
        XCTAssertTrue(decoded.newestTrayClipsOnRight)

        let defaults = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.scrollToLatestOnShow)
        XCTAssertFalse(defaults.newestTrayClipsOnRight)
    }

    func testRadialSwipeSensitivityIsClampedOnDecode() throws {
        let highJSON = #"{"radialPageSwipeSensitivity": 9.0}"#
        let highData = highJSON.data(using: .utf8)!
        let highDecoded = try JSONDecoder().decode(AppSettings.self, from: highData)
        XCTAssertEqual(highDecoded.radialPageSwipeSensitivity, 1.6, accuracy: 0.001)

        let lowJSON = #"{"radialPageSwipeSensitivity": 0.01}"#
        let lowData = lowJSON.data(using: .utf8)!
        let lowDecoded = try JSONDecoder().decode(AppSettings.self, from: lowData)
        XCTAssertEqual(lowDecoded.radialPageSwipeSensitivity, 0.4, accuracy: 0.001)
    }

    func testQuickNoteWindowSizeKeepsLargeValuesAndStillHonorsMinimums() throws {
        let highJSON = #"{"quickNoteWindowWidth": 1920, "quickNoteWindowHeight": 1280}"#
        let highData = highJSON.data(using: .utf8)!
        let highDecoded = try JSONDecoder().decode(AppSettings.self, from: highData)
        XCTAssertEqual(highDecoded.quickNoteWindowWidth, 1920, accuracy: 0.001)
        XCTAssertEqual(highDecoded.quickNoteWindowHeight, 1280, accuracy: 0.001)

        let lowJSON = #"{"quickNoteWindowWidth": 10, "quickNoteWindowHeight": 20}"#
        let lowData = lowJSON.data(using: .utf8)!
        let lowDecoded = try JSONDecoder().decode(AppSettings.self, from: lowData)
        XCTAssertEqual(lowDecoded.quickNoteWindowWidth, 320, accuracy: 0.001)
        XCTAssertEqual(lowDecoded.quickNoteWindowHeight, 220, accuracy: 0.001)
    }

    // MARK: - DetectedLanguage

    func testSpecificLanguageDisplayNames() {
        XCTAssertEqual(DetectedLanguage.swift.displayName, "Swift")
        XCTAssertEqual(DetectedLanguage.python.displayName, "Python")
        XCTAssertEqual(DetectedLanguage.javascript.displayName, "JavaScript")
        XCTAssertEqual(DetectedLanguage.typescript.displayName, "TypeScript")
        XCTAssertEqual(DetectedLanguage.html.displayName, "HTML")
        XCTAssertEqual(DetectedLanguage.css.displayName, "CSS")
        XCTAssertEqual(DetectedLanguage.sql.displayName, "SQL")
        XCTAssertEqual(DetectedLanguage.go.displayName, "Go")
        XCTAssertEqual(DetectedLanguage.rust.displayName, "Rust")
        XCTAssertEqual(DetectedLanguage.ruby.displayName, "Ruby")
        XCTAssertEqual(DetectedLanguage.java.displayName, "Java")
        XCTAssertEqual(DetectedLanguage.shell.displayName, "Shell")
        XCTAssertEqual(DetectedLanguage.unknown.displayName, "Code")
    }

    // MARK: - ClipType Enum

    func testClipTypeRawValues() {
        XCTAssertEqual(ClipType.text.rawValue, "text")
        XCTAssertEqual(ClipType.link.rawValue, "link")
        XCTAssertEqual(ClipType.image.rawValue, "image")
        XCTAssertEqual(ClipType.audio.rawValue, "audio")
        XCTAssertEqual(ClipType.color.rawValue, "color")
    }

    func testClipTypeRawValueRoundTrip() {
        for type in ClipType.allCases {
            let recovered = ClipType(rawValue: type.rawValue)
            XCTAssertEqual(recovered, type, "\(type) should round-trip through rawValue")
        }
    }

    func testClipTypeInvalidRawValueReturnsNil() {
        XCTAssertNil(ClipType(rawValue: "video"))
        XCTAssertNil(ClipType(rawValue: ""))
        XCTAssertNil(ClipType(rawValue: "TEXT"))  // Case-sensitive
    }

    func testClipTypeThemeFallsBackToDefaultsWhenUnset() {
        let settings = AppSettings()
        let defaultTheme = ClipTypePresentation.defaultTheme(for: .text)
        XCTAssertEqual(settings.clipTypeTheme(for: .text), defaultTheme)
    }

    func testClipTypeThemeSetAndResetHelpers() {
        var settings = AppSettings()
        let custom = ClipTypeTheme(accentRaw: "#ABCDEF", headerRaw: "#112233")
        settings.setClipTypeTheme(custom, for: .image)
        XCTAssertEqual(settings.clipTypeTheme(for: .image), custom)

        settings.resetClipTypeTheme(for: .image)
        XCTAssertEqual(settings.clipTypeTheme(for: .image), ClipTypePresentation.defaultTheme(for: .image))
    }

    // MARK: - FolderColorToken

    func testTokenLabelIsCapitalizedRawValue() {
        for token in FolderColorToken.allCases {
            XCTAssertEqual(token.label, token.rawValue.capitalized,
                           "\(token) label should be capitalized raw value")
        }
    }

    func testSpecificTokenLabels() {
        XCTAssertEqual(FolderColorToken.gold.label, "Gold")
        XCTAssertEqual(FolderColorToken.emerald.label, "Emerald")
        XCTAssertEqual(FolderColorToken.sapphire.label, "Sapphire")
    }

    func testTokenRawValueRoundTrip() {
        for token in FolderColorToken.allCases {
            let recovered = FolderColorToken(rawValue: token.rawValue)
            XCTAssertEqual(recovered, token)
        }
    }

    // MARK: - FolderColorMode

    func testFolderColorModeLabels() {
        XCTAssertEqual(FolderColorMode.dot.label, "Dot Only")
        XCTAssertEqual(FolderColorMode.text.label, "Text Only")
        XCTAssertEqual(FolderColorMode.fill.label, "Fill Background")
        XCTAssertEqual(FolderColorMode.dotAndText.label, "Dot & Text")
    }

    // MARK: - FolderTextColorMode

    func testFolderTextColorModeLabels() {
        XCTAssertEqual(FolderTextColorMode.auto.label, "Auto")
        XCTAssertEqual(FolderTextColorMode.white.label, "White")
        XCTAssertEqual(FolderTextColorMode.accent.label, "Accent")
        XCTAssertEqual(FolderTextColorMode.custom.label, "Custom")
    }

    // MARK: - BackgroundTheme

    func testAllThemesHaveLabel() {
        for theme in BackgroundTheme.allCases {
            XCTAssertFalse(theme.label.isEmpty, "\(theme) should have a label")
        }
    }

    func testSpecificThemeLabels() {
        XCTAssertEqual(BackgroundTheme.auric.label, "Auric")
        XCTAssertEqual(BackgroundTheme.vibrancy.label, "Vibrancy")
        XCTAssertEqual(BackgroundTheme.scenic.label, "Normal")
    }

    func testVibrancyUsesNativeVibrancy() {
        XCTAssertTrue(BackgroundTheme.vibrancy.usesNativeVibrancy)
        XCTAssertFalse(BackgroundTheme.auric.usesNativeVibrancy)
        XCTAssertFalse(BackgroundTheme.midnight.usesNativeVibrancy)
    }

    func testScenicIsImageOnly() {
        XCTAssertTrue(BackgroundTheme.scenic.isImageOnly)
        XCTAssertFalse(BackgroundTheme.auric.isImageOnly)
        XCTAssertFalse(BackgroundTheme.vibrancy.isImageOnly)
    }

    func testAllThemesHaveGradientColors() {
        for theme in BackgroundTheme.allCases {
            XCTAssertFalse(theme.gradientColors.isEmpty,
                           "\(theme) should have gradient colors")
        }
    }

    func testGlassMaterialOpacityIsHigher() {
        XCTAssertEqual(BackgroundTheme.glass.materialOpacityMultiplier, 2.0)
        XCTAssertEqual(BackgroundTheme.vibrancy.materialOpacityMultiplier, 0.0)
        XCTAssertEqual(BackgroundTheme.scenic.materialOpacityMultiplier, 0.0)
        XCTAssertEqual(BackgroundTheme.auric.materialOpacityMultiplier, 1.0)
    }

    // MARK: - BackgroundWallpaper

    func testWallpaperLabels() {
        XCTAssertEqual(BackgroundWallpaper.none.label, "None")
        XCTAssertEqual(BackgroundWallpaper.terra.label, "Terra")
        XCTAssertEqual(BackgroundWallpaper.custom.label, "Custom")
    }

    func testWallpaperResourceNames() {
        XCTAssertNil(BackgroundWallpaper.none.resourceName)
        XCTAssertEqual(BackgroundWallpaper.terra.resourceName, "terra")
        XCTAssertNil(BackgroundWallpaper.custom.resourceName)
    }

    // MARK: - ColorPreset

    func testColorPresetGradientDetection() {
        let gradient = ColorPreset(name: "Sunset", rawValue: "grad:#FF0000,#FF8800,180.0")
        XCTAssertTrue(gradient.isGradient)

        let solid = ColorPreset(name: "Red", rawValue: "#FF0000")
        XCTAssertFalse(solid.isGradient)
    }

    func testColorPresetCodableRoundTrip() throws {
        let original = ColorPreset(name: "TestPreset", rawValue: "grad:#111,#222,90.0")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColorPreset.self, from: data)
        XCTAssertEqual(decoded.name, "TestPreset")
        XCTAssertEqual(decoded.rawValue, "grad:#111,#222,90.0")
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertTrue(decoded.isGradient)
    }

    // MARK: - ContentTag Enum

    func testContentTagRawValues() {
        XCTAssertEqual(ContentTag.code.rawValue, "code")
        XCTAssertEqual(ContentTag.email.rawValue, "email")
        XCTAssertEqual(ContentTag.phoneNumber.rawValue, "phoneNumber")
        XCTAssertEqual(ContentTag.colorValue.rawValue, "colorValue")
        XCTAssertEqual(ContentTag.credential.rawValue, "credential")
        XCTAssertEqual(ContentTag.address.rawValue, "address")
    }

    // MARK: - SuggestedAction

    func testSuggestedActionTypeRawValues() {
        XCTAssertEqual(SuggestedActionType.call.rawValue, "call")
        XCTAssertEqual(SuggestedActionType.email.rawValue, "email")
        XCTAssertEqual(SuggestedActionType.openURL.rawValue, "openURL")
        XCTAssertEqual(SuggestedActionType.openMaps.rawValue, "openMaps")
        XCTAssertEqual(SuggestedActionType.colorSwatch.rawValue, "colorSwatch")
        XCTAssertEqual(SuggestedActionType.language.rawValue, "language")
    }

    // MARK: - ClipTypeTheme

    func testClipTypeThemeDecodesLegacyJSONWithoutLabelColor() throws {
        let json = "{\"accentRaw\":\"#6685F5\",\"headerRaw\":\"grad:#4D5CD1,#7A61E6,90\"}"
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(ClipTypeTheme.self, from: data)

        XCTAssertEqual(decoded.accentRaw, "#6685F5")
        XCTAssertEqual(decoded.headerRaw, "grad:#4D5CD1,#7A61E6,90")
        XCTAssertNil(decoded.labelRaw)
    }

    func testAppSettingsClipTypeThemeRoundTripsLabelColor() throws {
        var settings = AppSettings()
        settings.setClipTypeTheme(
            ClipTypeTheme(
                accentRaw: "#6685F5",
                headerRaw: "grad:#4D5CD1,#7A61E6,90",
                labelRaw: "#FDF2A6"
            ),
            for: .text
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.clipTypeTheme(for: .text).labelRaw, "#FDF2A6")
    }

    // MARK: - Launch At Login Messaging

    func testLaunchAtLoginFailureMessageExplainsDevBuildLimitation() {
        let message = ClipboardStore.launchAtLoginFailureMessage(
            enabling: true,
            isAppBundle: false,
            appName: "Gilt"
        )

        XCTAssertTrue(message.contains("isn't available right now"))
        XCTAssertTrue(message.contains("Applications"))
    }

    func testLaunchAtLoginFailureMessageForInstalledAppMentionsLoginItems() {
        let message = ClipboardStore.launchAtLoginFailureMessage(
            enabling: true,
            isAppBundle: true,
            appName: "Gilt"
        )

        XCTAssertTrue(message.contains("Couldn't turn on"))
        XCTAssertTrue(message.contains("Applications"))
    }

    func testLaunchAtLoginDisableFailureMessageExplainsManualRemovalPath() {
        let message = ClipboardStore.launchAtLoginFailureMessage(
            enabling: false,
            isAppBundle: true,
            appName: "Gilt"
        )

        XCTAssertTrue(message.contains("Couldn't turn off"))
        XCTAssertTrue(message.contains("System Settings"))
    }

    func testSettingsSideEffectsAreSkippedWhileHydratingStoredSettings() {
        XCTAssertFalse(ClipboardStore.shouldApplySettingsSideEffects(isHydratingSettings: true))
        XCTAssertTrue(ClipboardStore.shouldApplySettingsSideEffects(isHydratingSettings: false))
    }
}
