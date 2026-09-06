import SwiftUI

/// The "Dictate" tab content for the Settings window. Pure presentation —
/// reads/writes through the `DictationStore` injected from the app root.
///
/// Designed to slot into the parent `SettingsView` scroll container; it does
/// not provide its own `ScrollView` or page header (the host already renders a
/// greeting + subtitle above the tab content).
struct DictationSettingsView: View {
    @EnvironmentObject private var store: DictationStore
    @Namespace private var triggerNamespace
    /// Separate matched-geometry namespace for the ask-screen trigger
    /// picker so its segmented-pill animation doesn't fight the primary
    /// dictation trigger picker when both are visible on the Shortcut tab.
    @Namespace private var askTriggerNamespace
    @Namespace private var actionsTriggerNamespace
    @Namespace private var styleNamespace
    @Namespace private var livePolishEngineNamespace
    @State private var remindersAccessGranted = RemindersSyncService.shared.hasAccess
    @Namespace private var subTabNamespace
    @State private var subTab: DictateSubTab = .shortcut

    /// Self-contained model manager scoped to this settings view. We don't
    /// reach into `MeetingHub` because that would force the entire meeting
    /// subsystem (store + controller + audio capture) to spin up just so a
    /// user can read a download progress bar. The library-level model cache
    /// (FluidAudio / WhisperKit) lives on disk and is shared across
    /// instances, so a download started here is visible in Meetings settings
    /// next time it refreshes.
    @StateObject private var modelManager: MeetingModelManager = {
        let meetingsRoot = MeetingAppSupportLocator.meetingsRoot()
        let modelsRoot = MeetingAppSupportLocator.modelsRoot(in: meetingsRoot)
        let transcription = MeetingTranscriptionService(modelsRoot: modelsRoot)
        return MeetingModelManager(
            modelsRoot: modelsRoot,
            transcriptionService: transcription
        )
    }()

    /// Sub-pages inside the Dictate tab. Same separation pattern as the
    /// Appearance / Folders / Pulse tabs use elsewhere in Settings — keeps
    /// each concern on its own page instead of one long scroll.
    enum DictateSubTab: String, CaseIterable, Identifiable {
        case shortcut
        case appearance
        case style
        case context
        case advanced

        var id: String { rawValue }

        var label: String {
            switch self {
            case .shortcut:   return "Shortcut"
            case .appearance: return "Appearance"
            case .style:      return "Style"
            case .context:    return "Context"
            case .advanced:   return "Advanced"
            }
        }

        var blurb: String {
            switch self {
            case .shortcut:
                return "Pick the key (or key combo) that starts a dictation, and how it fires."
            case .appearance:
                return "Choose the colour scheme for the floating dictation pill."
            case .style:
                return "Optional AI polish. Turn rough speech into clean text in the voice you pick."
            case .context:
                return "Let Jack peek at what's on screen so it spells names, code, and jargon right."
            case .advanced:
                return "Engine, paste behaviour, history, and the master enable switch."
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            intro
            subTabPicker
            // Each sub-page renders only its own section block — no more
            // single long scroll. Switching is animated so the transition
            // matches the rest of the Settings window.
            Group {
                switch subTab {
                case .shortcut:   shortcutSubTabSection
                case .appearance: appearanceSection
                case .style:      styleSubTabSection
                case .context:    screenContextSubTabSection
                case .advanced:   advancedAndModelSection
                }
            }
            .transition(.opacity)
            .id(subTab)
        }
    }

    // MARK: - Sub-tab picker

    private var subTabPicker: some View {
        VStack(spacing: 6) {
            SettingsSegmentedPicker(
                options: DictateSubTab.allCases,
                selection: subTab,
                namespace: subTabNamespace,
                label: \.label
            ) { tab in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    subTab = tab
                }
            }

            // Sub-page blurb sits under the picker so each section has a
            // one-line "what is this" without needing its own intro card.
            Text(subTab.blurb)
                .font(.system(size: 11.5))
                .foregroundStyle(SettingsTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 2)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Appearance (pill color theme)

    private var appearanceSection: some View {
        SettingsSection(L10n.string("ui.pill.color", default: "Pill color")) {
            VStack(alignment: .leading, spacing: 0) {
                // Current selection summary — name on the left, tagline below.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.settings.pillTheme.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SettingsTheme.textPrimary)
                        Spacer()
                        Text("\(DictationPillTheme.allCases.count) options")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SettingsTheme.textSecondary)
                    }
                    Text(store.settings.pillTheme.tagline)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                SettingsDivider()

                // Swatches grouped by mood. Each group has a tiny heading so
                // the user can scan ~20 options without it feeling chaotic.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ThemeGroup.allCases) { group in
                        let themes = DictationPillTheme.allCases.filter { $0.group == group }
                        if !themes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.displayName.uppercased())
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundStyle(SettingsTheme.textSecondary)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 10)],
                                    spacing: 10
                                ) {
                                    ForEach(themes) { theme in
                                        DictationPillThemeSwatch(
                                            theme: theme,
                                            isSelected: store.settings.pillTheme == theme
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .onTapGesture {
                                            store.settings.pillTheme = theme
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Context (screen-aware dictation)

    /// Thin wrapper that delegates to the dedicated `ScreenContextSettingsView`.
    /// Kept here just so the sub-tab switch in `body` stays internally consistent
    /// with the other `*SubTabSection` properties.
    private var screenContextSubTabSection: some View {
        ScreenContextSettingsView()
            .environmentObject(store)
    }

    /// Combines the engine picker and the advanced toggles onto one sub-page
    /// — they're related concerns (capture / output behaviour) and putting
    /// them on separate sub-tabs would create needless clicking.
    private var advancedAndModelSection: some View {
        VStack(spacing: 18) {
            modelSection
            microphoneSection
            audioSection
            advancedSection
        }
    }

    // MARK: - Microphone (device + input gain)

    /// Hosts the reusable `MicrophoneSettingsSection`. Lives on the Advanced
    /// sub-tab next to the audio-ducking section — both are "what mic Jack
    /// uses and how it sounds" concerns.
    private var microphoneSection: some View {
        MicrophoneSettingsSection(
            selectedDeviceUID: Binding(
                get: { store.settings.preferredMicDeviceUID },
                set: { store.settings.preferredMicDeviceUID = $0 }
            ),
            inputGain: Binding(
                get: { store.settings.inputGain },
                set: { store.settings.inputGain = $0 }
            )
        )
    }

    // MARK: - Vocabulary

    @State private var pendingCustomTerm: String = ""
    /// When non-nil, the vocabulary section swaps from the pack-list view
    /// to a per-pack editor. We keep the editor inline (instead of a sheet
    /// or popover) so it lives inside the settings window and doesn't get
    /// awkwardly anchored to the bottom tray.
    @State private var editingPack: DictationVocabularyPack? = nil
    /// Buffer for the "add a term" field inside the per-pack editor. Kept
    /// separate from `pendingCustomTerm` so switching between packs and the
    /// global "Your terms" list doesn't bleed half-typed input.
    @State private var pendingPackTerm: String = ""

    private var vocabularySection: some View {
        SettingsSection(L10n.string("ui.vocabulary", default: "Vocabulary")) {
            VStack(alignment: .leading, spacing: 0) {
                if let pack = editingPack {
                    packEditor(pack)
                } else {
                    vocabularyPackList
                }
            }
        }
    }

    private var vocabularyPackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section explainer
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsTheme.primaryAccent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(SettingsTheme.primaryAccent.opacity(0.10)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("ui.teach.jack.your.jargon", default: "Teach Jack your jargon"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Text("When the engine hears \u{201C}chat g p t\u{201D} or \u{201C}use effect\u{201D}, the matcher swaps it for the canonical spelling (\u{201C}ChatGPT\u{201D}, \u{201C}useEffect\u{201D}). Tap the pencil on any pack to see and edit what\u{2019}s inside. Works without the AI polish.")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            SettingsDivider()

            // Pack toggles
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(DictationVocabularyPack.allCases.enumerated()), id: \.element.id) { idx, pack in
                    packRow(pack)
                    if idx < DictationVocabularyPack.allCases.count - 1 {
                        SettingsDivider()
                    }
                }
            }

            SettingsDivider()

            // Custom terms
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.string("ui.your.terms", default: "Your terms"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Spacer()
                    Text("\(store.settings.customVocabulary.count) added")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.textSecondary)
                }

                Text("General terms that aren\u{2019}t tied to any pack: product names, brand spellings, names of people you talk about a lot. Use the strength menu on each term to dial how hard Jack tries to fix it. \u{201C}Strong\u{201D} catches mishearings that sound similar (e.g. \u{201C}clawed\u{201D} \u{2192} \u{201C}claude\u{201D}).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Existing custom terms list. Wrapped in a fixed-height
                // scroll region so the section stays compact even with
                // hundreds of terms — the outer settings page never has
                // to grow taller than this card.
                if !store.settings.customVocabulary.isEmpty {
                    customTermsScrollList
                }

                // Add-new field
                HStack(spacing: 8) {
                    TextField("Add a term…", text: $pendingCustomTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitPendingTerm() }
                    Button(L10n.string("ui.add", default: "Add")) { commitPendingTerm() }
                        .disabled(pendingCustomTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func packRow(_ pack: DictationVocabularyPack) -> some View {
        SettingsRow(
            title: pack.displayName,
            subtitle: pack.subtitle,
            icon: pack.icon
        ) {
            HStack(spacing: 10) {
                Button {
                    pendingPackTerm = ""
                    withAnimation(.easeOut(duration: 0.18)) {
                        editingPack = pack
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(SettingsTheme.primaryAccent.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Edit \(pack.displayName) terms")

                Toggle("", isOn: Binding(
                    get: { store.settings.enabledVocabPacks.contains(pack) },
                    set: { isOn in
                        if isOn {
                            store.settings.enabledVocabPacks.insert(pack)
                        } else {
                            store.settings.enabledVocabPacks.remove(pack)
                        }
                    }
                ))
                .toggleStyle(GoldToggleStyle())
                .labelsHidden()
            }
        }
    }

    // MARK: Per-pack editor

    @ViewBuilder
    private func packEditor(_ pack: DictationVocabularyPack) -> some View {
        let additions = store.settings.packTermAdditions[pack.rawValue] ?? []
        let removals = store.settings.packTermRemovals[pack.rawValue] ?? []
        let removalSet = Set(removals.map { $0.lowercased() })
        let visibleBuiltIns = pack.terms.filter { !removalSet.contains($0.lowercased()) }
        let hasEdits = !additions.isEmpty || !removals.isEmpty

        VStack(alignment: .leading, spacing: 14) {
            // Header — back button + pack identity
            HStack(spacing: 12) {
                Button {
                    pendingPackTerm = ""
                    withAnimation(.easeOut(duration: 0.18)) {
                        editingPack = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.string("ui.all.packs", default: "All packs"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(SettingsTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if hasEdits {
                    Button(L10n.string("ui.reset.to.defaults", default: "Reset to defaults")) {
                        store.settings.packTermAdditions.removeValue(forKey: pack.rawValue)
                        store.settings.packTermRemovals.removeValue(forKey: pack.rawValue)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsTheme.textSecondary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(SettingsTheme.primaryAccent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: pack.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.primaryAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textPrimary)
                    Text(pack.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Add-new field
            HStack(spacing: 8) {
                TextField("Add a term to this pack…", text: $pendingPackTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitPendingPackTerm(into: pack) }
                Button(L10n.string("ui.add", default: "Add")) { commitPendingPackTerm(into: pack) }
                    .disabled(pendingPackTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }

            // User additions section (only shown when non-empty)
            if !additions.isEmpty {
                packEditorSubsectionHeader(
                    title: "Your additions",
                    count: additions.count
                )
                packTermsGrid(additions) { term in
                    removePackAddition(term, from: pack)
                }
            }

            // Built-in section
            packEditorSubsectionHeader(
                title: "Built-in",
                count: visibleBuiltIns.count,
                trailing: removals.isEmpty ? nil : "\(removals.count) hidden"
            )
            if visibleBuiltIns.isEmpty {
                Text("You\u{2019}ve removed every built-in term. Use \u{201C}Reset to defaults\u{201D} above to bring them back.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                packTermsGrid(visibleBuiltIns) { term in
                    removeBuiltInTerm(term, from: pack)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func packEditorSubsectionHeader(title: String, count: Int, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.textPrimary)
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.textSecondary)
            }
        }
    }

    /// Flowing grid of term chips. Caps height so a 200-term pack doesn't
    /// blow out the settings page; the user scrolls inside the card.
    @ViewBuilder
    private func packTermsGrid(_ terms: [String], onRemove: @escaping (String) -> Void) -> some View {
        let rowHeight: CGFloat = 32
        let visibleRows: CGFloat = 8
        let rough = ceil(CGFloat(terms.count) / 2.0)
        let height = min(rough, visibleRows) * rowHeight + max(0, min(rough, visibleRows) - 1) * 6
        ScrollView(.vertical, showsIndicators: rough > visibleRows) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 6
            ) {
                ForEach(terms, id: \.self) { term in
                    HoverableTermRow(term: term) { onRemove(term) }
                }
            }
            .padding(.trailing, rough > visibleRows ? 6 : 0)
        }
        .frame(maxHeight: max(rowHeight, height))
    }

    private func commitPendingPackTerm(into pack: DictationVocabularyPack) {
        let trimmed = pendingPackTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // If the user is "re-adding" a built-in term they previously removed,
        // un-hide it instead of creating a duplicate addition.
        if let removals = store.settings.packTermRemovals[pack.rawValue],
           let idx = removals.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            var updated = removals
            updated.remove(at: idx)
            if updated.isEmpty {
                store.settings.packTermRemovals.removeValue(forKey: pack.rawValue)
            } else {
                store.settings.packTermRemovals[pack.rawValue] = updated
            }
            pendingPackTerm = ""
            return
        }
        // Dedup against current additions + the built-in list.
        let existingAdditions = store.settings.packTermAdditions[pack.rawValue] ?? []
        let alreadyKnown = existingAdditions.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
            || pack.terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        if !alreadyKnown {
            store.settings.packTermAdditions[pack.rawValue, default: []].append(trimmed)
        }
        pendingPackTerm = ""
    }

    private func removePackAddition(_ term: String, from pack: DictationVocabularyPack) {
        guard var list = store.settings.packTermAdditions[pack.rawValue] else { return }
        list.removeAll { $0 == term }
        if list.isEmpty {
            store.settings.packTermAdditions.removeValue(forKey: pack.rawValue)
        } else {
            store.settings.packTermAdditions[pack.rawValue] = list
        }
    }

    private func removeBuiltInTerm(_ term: String, from pack: DictationVocabularyPack) {
        var removals = store.settings.packTermRemovals[pack.rawValue] ?? []
        if !removals.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
            removals.append(term)
            store.settings.packTermRemovals[pack.rawValue] = removals
        }
    }

    /// Scrollable bounded-height container for the custom terms list.
    /// Rows are a little taller than pack chips because each one carries a
    /// strength menu in addition to the text + delete button.
    @ViewBuilder
    private var customTermsScrollList: some View {
        let rowHeight: CGFloat = 38
        let visibleRows: CGFloat = 5
        let count = CGFloat(store.settings.customVocabulary.count)
        let height = min(count, visibleRows) * rowHeight + (min(count, visibleRows) - 1) * 6
        ScrollView(.vertical, showsIndicators: count > visibleRows) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.settings.customVocabulary) { term in
                    customTermRow(term)
                }
            }
            .padding(.trailing, count > visibleRows ? 6 : 0)
        }
        .frame(maxHeight: max(rowHeight, height))
    }

    @ViewBuilder
    private func customTermRow(_ term: CustomVocabularyTerm) -> some View {
        CustomTermRow(
            term: term,
            onChangeStrength: { newStrength in
                if let idx = store.settings.customVocabulary.firstIndex(where: { $0.id == term.id }) {
                    store.settings.customVocabulary[idx].strength = newStrength
                }
            },
            onRemove: {
                store.settings.customVocabulary.removeAll { $0.id == term.id }
            }
        )
    }

    private func commitPendingTerm() {
        let trimmed = pendingCustomTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // De-dupe — case-insensitive comparison so "ChatGPT" and "chatgpt"
        // don't both end up in the list. New terms default to .strong so
        // the user gets the better-mishearing-fix behavior on day one.
        if !store.settings.customVocabulary.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            store.settings.customVocabulary.append(
                CustomVocabularyTerm(text: trimmed, strength: .strong)
            )
        }
        pendingCustomTerm = ""
    }

    // MARK: - Background audio (ducking)

    private var audioSection: some View {
        SettingsSection(L10n.string("ui.background.audio", default: "Background audio")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "Quiet other apps while dictating",
                    subtitle: "Volume comes back when you stop.",
                    icon: "speaker.wave.2.fill",
                    isOn: Binding(
                        get: { store.settings.duckOtherAudio },
                        set: { store.settings.duckOtherAudio = $0 }
                    )
                )

                if store.settings.duckOtherAudio {
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.string("ui.how.much.quieter", default: "How much quieter"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Spacer()
                            Text("\(Int((store.settings.duckAmount * 100).rounded()))%")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(SettingsTheme.textSecondary)
                        }

                        Slider(
                            value: Binding(
                                get: { store.settings.duckAmount },
                                set: { store.settings.duckAmount = $0 }
                            ),
                            in: 0...1
                        ) {
                            Text(L10n.string("ui.how.much.quieter", default: "How much quieter"))
                        } minimumValueLabel: {
                            Text(L10n.string("ui.off", default: "Off"))
                                .font(.system(size: 10))
                                .foregroundStyle(SettingsTheme.textSecondary)
                        } maximumValueLabel: {
                            Text(L10n.string("ui.mute", default: "Mute"))
                                .font(.system(size: 10))
                                .foregroundStyle(SettingsTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsTheme.primaryAccent.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SettingsTheme.primaryAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("ui.dictate.anywhere", default: "Dictate anywhere"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Text("Hold a key, speak, release. \(AppBrand.displayName) transcribes and types it into the app you're using.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Hotkey

    /// Bundles the primary dictation hotkey + the optional ask-the-screen
    /// hotkey on the same sub-tab. They're distinct features but they
    /// belong together because they're both "what key fires dictation."
    private var shortcutSubTabSection: some View {
        VStack(spacing: 18) {
            hotkeySection
            askScreenSection
            voiceActionsSection
        }
    }

    /// Ask-the-screen: a separate dictation flow that answers questions about
    /// what's on screen. Gated behind its own on/off toggle (`askScreenEnabled`)
    /// that is independent of the bound key, so turning the feature off keeps
    /// the user's chosen shortcut for next time instead of resetting it.
    ///
    /// Layout mirrors the primary `hotkeySection`: an enable toggle on top,
    /// then (only while enabled) the shortcut recorder + "How it fires".
    private var askScreenSection: some View {
        SettingsSection(L10n.string("ui.ask.the.screen", default: "Ask the screen")) {
            VStack(alignment: .leading, spacing: 0) {
                DictationFeatureDemoView(
                    command: "What does this error mean?",
                    resultIcon: "eye.fill",
                    resultTitle: "Jack reads your screen",
                    resultSubtitle: "The answer is pasted where you're typing",
                    accent: Color(red: 0.28, green: 0.78, blue: 0.92)
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)

                SettingsToggleRow(
                    title: "Ask the screen",
                    subtitle: askScreenSubtitle,
                    icon: "eye.fill",
                    isOn: Binding(
                        get: { store.settings.askScreenEnabled },
                        set: { store.settings.askScreenEnabled = $0 }
                    )
                )

                // Shortcut + trigger only appear while the feature is on.
                // Turning it off hides the controls but leaves the stored
                // shortcut untouched, so flipping it back on restores the
                // exact key the user picked before.
                if store.settings.askScreenEnabled {
                    SettingsDivider()

                    SettingsRow(
                        title: "Ask shortcut",
                        subtitle: "Click the field, then press the key (or combo) you want to use.",
                        icon: "keyboard"
                    ) {
                        DictationShortcutRecorderField(
                            shortcut: askShortcutBinding,
                            placeholder: store.settings.askScreenShortcut == nil ? "Click to set a key" : nil
                        ) { captured in
                            // Preserve whatever trigger the user already
                            // picked when they re-record the key — otherwise
                            // the recorder field would silently reset trigger
                            // back to .pushToTalk every time they change keys.
                            var updated = captured
                            if let existing = store.settings.askScreenShortcut {
                                updated.trigger = existing.trigger
                            }
                            store.settings.askScreenShortcut = updated
                        }
                        .frame(width: 200, height: 28)
                    }

                    // "How it fires" only appears once a key is actually
                    // bound. Showing it while unset would let the trigger
                    // picker silently create a default (Right Option) binding
                    // the user never chose — exactly the phantom-default
                    // behaviour we're trying to remove.
                    if let askShortcut = store.settings.askScreenShortcut {
                        SettingsDivider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(L10n.string("ui.how.it.fires", default: "How it fires"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SettingsTheme.textPrimary)
                                Spacer()
                            }

                            SettingsSegmentedPicker(
                                options: DictationTriggerKind.allCases,
                                selection: askShortcut.trigger,
                                namespace: askTriggerNamespace,
                                label: { $0.displayName },
                                action: { newTrigger in
                                    var s = askShortcut
                                    s.trigger = newTrigger
                                    store.settings.askScreenShortcut = s
                                }
                            )

                            Text(askShortcut.trigger.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    /// Binding adapter so `DictationShortcutRecorderField` (which expects a
    /// non-optional `DictationShortcut`) can edit our optional setting. The
    /// recorder shows a grey "Click to set a key" prompt while the value is
    /// nil (see the `placeholder:` argument at the call site), so the user is
    /// never shown a phantom default that they didn't choose.
    private var askShortcutBinding: Binding<DictationShortcut> {
        Binding(
            get: { store.settings.askScreenShortcut ?? .default },
            set: { store.settings.askScreenShortcut = $0 }
        )
    }

    private var askScreenSubtitle: String {
        guard store.settings.askScreenEnabled else {
            return "Speak a question; Jack answers using what's on your screen."
        }
        if let s = store.settings.askScreenShortcut {
            return "Press \(s.displayString) to ask a question about your screen."
        }
        return "Set a shortcut below to start asking about your screen."
    }

    /// Voice actions: speak a command instead of dictating text. Reminders is
    /// the default connector; Spotify is optional via AppleScript.
    private var voiceActionsSection: some View {
        SettingsSection(L10n.string("ui.voice.actions", default: "Voice actions")) {
            VStack(alignment: .leading, spacing: 0) {
                DictationFeatureDemoView(
                    command: "Remind me to send the invoice tomorrow at 9",
                    resultIcon: "checklist",
                    resultTitle: "Send the invoice",
                    resultSubtitle: "Added to Apple Reminders · Tomorrow 9:00 AM",
                    accent: Color(red: 0.96, green: 0.58, blue: 0.28)
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)

                SettingsToggleRow(
                    title: "Voice actions",
                    subtitle: voiceActionsSubtitle,
                    icon: "checklist",
                    isOn: Binding(
                        get: { store.settings.voiceActionsEnabled },
                        set: { enabled in
                            store.settings.voiceActionsEnabled = enabled
                            if enabled {
                                Task {
                                    let granted = await RemindersSyncService.shared.requestAccess()
                                    if granted {
                                        RemindersSyncService.shared.isSyncEnabled = true
                                    }
                                    remindersAccessGranted = RemindersSyncService.shared.hasAccess
                                }
                            }
                        }
                    )
                )

                if store.settings.voiceActionsEnabled {
                    if !remindersAccessGranted {
                        SettingsDivider()

                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(0.9))
                            Text(L10n.string("ui.allow.reminders.access.when.macos.prompts.you", default: "Allow Reminders access when macOS prompts you."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }

                    if remindersAccessGranted {
                        SettingsDivider()
                        AppleRemindersListPicker()
                    }

                    SettingsDivider()

                    ForEach(VoiceActionConnector.allCases) { connector in
                        connectorRow(connector)
                        if connector != VoiceActionConnector.allCases.last {
                            SettingsDivider()
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Actions shortcut",
                        subtitle: "Click the field, then press the key you want for voice commands.",
                        icon: "keyboard"
                    ) {
                        DictationShortcutRecorderField(
                            shortcut: actionsShortcutBinding,
                            placeholder: store.settings.voiceActionsShortcut == nil ? "Click to set a key" : nil
                        ) { captured in
                            var updated = captured
                            if let existing = store.settings.voiceActionsShortcut {
                                updated.trigger = existing.trigger
                            }
                            store.settings.voiceActionsShortcut = updated
                        }
                        .frame(width: 200, height: 28)
                    }

                    if let actionsShortcut = store.settings.voiceActionsShortcut {
                        SettingsDivider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(L10n.string("ui.how.it.fires", default: "How it fires"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SettingsTheme.textPrimary)
                                Spacer()
                            }

                            SettingsSegmentedPicker(
                                options: DictationTriggerKind.allCases,
                                selection: actionsShortcut.trigger,
                                namespace: actionsTriggerNamespace,
                                label: { $0.displayName },
                                action: { newTrigger in
                                    var s = actionsShortcut
                                    s.trigger = newTrigger
                                    store.settings.voiceActionsShortcut = s
                                }
                            )

                            Text(actionsShortcut.trigger.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
        .onAppear {
            remindersAccessGranted = RemindersSyncService.shared.hasAccess
        }
    }

    private func connectorRow(_ connector: VoiceActionConnector) -> some View {
        let enabled = store.settings.voiceActionConnectors.contains(connector)
        let disabled = connector == .spotify && !SpotifyControlService.isInstalled
        return SettingsToggleRow(
            title: connector.displayName,
            subtitle: disabled
                ? "Install Spotify on your Mac to enable playback commands."
                : connector.subtitle,
            icon: connector.icon,
            isOn: Binding(
                get: { enabled && !disabled },
                set: { on in
                    if on {
                        store.settings.voiceActionConnectors.insert(connector)
                    } else {
                        store.settings.voiceActionConnectors.remove(connector)
                    }
                }
            )
        )
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private var actionsShortcutBinding: Binding<DictationShortcut> {
        Binding(
            get: { store.settings.voiceActionsShortcut ?? .default },
            set: { store.settings.voiceActionsShortcut = $0 }
        )
    }

    private var voiceActionsSubtitle: String {
        guard store.settings.voiceActionsEnabled else {
            return "Say “remind me to call mom tomorrow” and it lands in Apple Reminders."
        }
        if let s = store.settings.voiceActionsShortcut {
            return "Press \(s.displayString) and speak a command."
        }
        return "Set a shortcut below, then speak commands like “remind me to…”."
    }

    private var hotkeySection: some View {
        SettingsSection(L10n.string("ui.shortcut", default: "Shortcut")) {
            VStack(alignment: .leading, spacing: 0) {
                // Master on/off, surfaced here on the Shortcut page (not just
                // buried in Advanced) so it's the first thing the user sees.
                // When off, the hotkey monitor is uninstalled entirely, so no
                // key triggers dictation — but the chosen key is remembered.
                SettingsToggleRow(
                    title: "Dictation",
                    subtitle: store.settings.isEnabled
                        ? "Dictation is on. Use the key below to start talking."
                        : "Dictation is off. No key will start a dictation.",
                    icon: "power",
                    isOn: Binding(
                        get: { store.settings.isEnabled },
                        set: { store.settings.isEnabled = $0 }
                    )
                )

                if store.settings.isEnabled {
                    SettingsDivider()

                    SettingsRow(
                        title: "Trigger key",
                        subtitle: "Click the field, then press the key (or combo) you want to use.",
                        icon: "keyboard"
                    ) {
                        DictationShortcutRecorderField(
                            shortcut: Binding(
                                get: { store.settings.shortcut },
                                set: { store.settings.shortcut = $0 }
                            )
                        ) { captured in
                            store.settings.shortcut = captured
                        }
                        .frame(width: 200, height: 28)
                    }

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.string("ui.how.it.fires", default: "How it fires"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Spacer()
                        }

                        SettingsSegmentedPicker(
                            options: DictationTriggerKind.allCases,
                            selection: store.settings.shortcut.trigger,
                            namespace: triggerNamespace,
                            label: { $0.displayName },
                            action: { newTrigger in
                                var s = store.settings.shortcut
                                s.trigger = newTrigger
                                store.settings.shortcut = s
                            }
                        )

                        Text(store.settings.shortcut.trigger.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Style + list-formatting (Style sub-tab)

    /// The Style sub-tab. Two stacked sections that together answer the
    /// question "how does my dictation come out?":
    ///   1. **Style picker** — Qwen's "voice" (Conversation vs Vibe Coding)
    ///      and how aggressively it polishes the wording.
    ///   2. **Vocabulary** — profession packs + user custom terms that
    ///      restore canonical spellings ("ChatGPT", "useEffect", "API")
    ///      even without the AI polish.
    ///
    /// Smart formatting (punctuation commands, sentence capitalization,
    /// curly quotes, list/paragraph structure) is intentionally invisible —
    /// it just always runs on the output.
    /// Style sub-tab content.
    ///
    /// Smart-formatting controls used to live here as their own section
    /// (punctuation commands, sentence capitalization, curly quotes,
    /// list + paragraph structure). They were removed from the UI to keep
    /// this page short — every one of those behaviours still runs
    /// automatically using the defaults baked into `DictationSettings`,
    /// the user just doesn't see toggles for them anymore.
    private var styleSubTabSection: some View {
        VStack(spacing: 18) {
            styleSection
            vocabularySection
            // Sits next to Vocabulary because it's the same idea — a list
            // of word-level substitutions the matcher will apply, just
            // sourced automatically instead of typed manually by the user.
            LearnedCorrectionsSection()
        }
    }


    private var styleSection: some View {
        SettingsSection(L10n.string("ui.style", default: "Style")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "Polish dictation with AI",
                    subtitle: "Cleans up filler words and fixes grammar using the on-device Qwen model.",
                    icon: "sparkles",
                    isOn: Binding(
                        get: { store.settings.postProcessEnabled },
                        set: { store.settings.postProcessEnabled = $0 }
                    )
                )

                if store.settings.postProcessEnabled {
                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Polish while you speak",
                        subtitle: "Finished sentences clean themselves up live in the caption, so corrections like \u{201C}oops, I meant onions\u{201D} heal before you even finish.",
                        icon: "wand.and.sparkles",
                        isOn: Binding(
                            get: { store.settings.livePolishEnabled },
                            set: { store.settings.livePolishEnabled = $0 }
                        )
                    )

                    if store.settings.livePolishEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(L10n.string("ui.live.polish.engine", default: "Live polish engine"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SettingsTheme.textPrimary)
                                Spacer()
                            }

                            SettingsSegmentedPicker(
                                options: LivePolishEngine.allCases,
                                selection: store.settings.livePolishEngine,
                                namespace: livePolishEngineNamespace,
                                label: { $0.displayName },
                                action: { store.settings.livePolishEngine = $0 }
                            )

                            Text(store.settings.livePolishEngine.description)
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.string("ui.voice", default: "Voice"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Spacer()
                        }

                        SettingsSegmentedPicker(
                            options: DictationStyle.allCases,
                            selection: store.settings.style,
                            namespace: styleNamespace,
                            label: { $0.displayName },
                            action: { store.settings.style = $0 }
                        )

                        Text(store.settings.style.description)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.string("ui.polish.level", default: "Polish level"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Spacer()
                            Text(store.settings.level.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SettingsTheme.textSecondary)
                        }

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(DictationLevel.allCases) { level in
                                DictationLevelCard(
                                    level: level,
                                    isSelected: store.settings.level == level,
                                    sampleText: sampleText(for: level)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture {
                                    store.settings.level = level
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        SettingsSection(L10n.string("ui.dictation.model", default: "Dictation Model")) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(MeetingTranscriptionEngine.dictationEngines.enumerated()), id: \.element) { index, engine in
                    if index > 0 {
                        SettingsDivider()
                    }
                    modelCard(for: engine)
                }
            }
        }
        .onAppear {
            modelManager.refreshAll()
        }
    }

    /// The single dictation model card: NVIDIA logo, one metadata line, and
    /// the download / delete action. No picker chrome since there is exactly
    /// one model.
    @ViewBuilder
    private func modelCard(for engine: MeetingTranscriptionEngine) -> some View {
        let state = modelManager.transcriptionState(for: engine)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        nvidiaLogo
                        statusBadge(for: state)
                    }
                    Text("English · \(formattedModelSize(engine.approximateDownloadSizeBytes))")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.textTertiary)
                }

                Spacer(minLength: 8)

                modelAction(for: state, engine: engine)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if case let .downloading(progress, _) = state {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(SettingsTheme.primaryAccent)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            } else if case let .failed(reason) = state {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder
    private var nvidiaLogo: some View {
        if let url = Bundle.module.url(
            forResource: "nvidia",
            withExtension: "svg",
            subdirectory: "Resources/ProviderIcons"
        ),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 14)
                .accessibilityLabel(L10n.string("ui.nvidia.speech.model", default: "NVIDIA speech model"))
        } else {
            Text(L10n.string("ui.nvidia", default: "NVIDIA"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsTheme.textPrimary)
        }
    }

    @ViewBuilder
    private func statusBadge(for state: MeetingModelDownloadState) -> some View {
        switch state {
        case .ready:
            badge(text: "Ready", color: Color.green.opacity(0.85))
        case .downloading(let progress, _):
            badge(text: "Downloading \(Int(progress * 100))%", color: SettingsTheme.primaryAccent)
        case .missing:
            badge(text: "Not downloaded", color: SettingsTheme.textTertiary)
        case .failed:
            badge(text: "Failed", color: Color.red.opacity(0.85))
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func formattedModelSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        return "\(Int(mb)) MB"
    }

    @ViewBuilder
    private func modelAction(for state: MeetingModelDownloadState, engine: MeetingTranscriptionEngine) -> some View {
        switch state {
        case .missing:
            Button {
                Task { await modelManager.downloadTranscriptionModel(engine) }
            } label: {
                Label(L10n.string("ui.download", default: "Download"), systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .failed:
            Button {
                Task { await modelManager.downloadTranscriptionModel(engine) }
            } label: {
                Label(L10n.string("ui.retry", default: "Retry"), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Button {
                modelManager.deleteModel(engine)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Remove downloaded model")
            .foregroundStyle(SettingsTheme.textTertiary)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        SettingsSection(L10n.string("ui.advanced", default: "Advanced")) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Dictation enabled",
                    subtitle: "Master switch for the global dictation hotkey.",
                    icon: "power",
                    isOn: Binding(
                        get: { store.settings.isEnabled },
                        set: { store.settings.isEnabled = $0 }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Paste into active app",
                    subtitle: "Type the transcript directly into the frontmost application.",
                    icon: "doc.on.clipboard",
                    isOn: Binding(
                        get: { store.settings.autoPasteIntoActiveApp },
                        set: { store.settings.autoPasteIntoActiveApp = $0 }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Save to clipboard history",
                    subtitle: "Keep every dictation as a clip so you can re-grab it later.",
                    icon: "clock.arrow.circlepath",
                    isOn: Binding(
                        get: { store.settings.saveToClipboardHistory },
                        set: { store.settings.saveToClipboardHistory = $0 }
                    )
                )

                SettingsDivider()

                SettingsRow(
                    title: "Release models when idle",
                    subtitle: store.settings.engineIdleUnload.subtitle,
                    icon: "memorychip"
                ) {
                    Picker("", selection: Binding(
                        get: { store.settings.engineIdleUnload },
                        set: { store.settings.engineIdleUnload = $0 }
                    )) {
                        ForEach(EngineIdleUnload.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                if !store.history.isEmpty {
                    SettingsDivider()

                    HStack(spacing: 12) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SettingsTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(SettingsTheme.primaryAccent.opacity(0.10))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(store.history.count) recent dictations saved")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SettingsTheme.textPrimary)
                            Text(L10n.string("ui.clears.the.local.dictation.log.clipb.8658d9", default: "Clears the local dictation log. Clipboard history is untouched."))
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Button(L10n.string("ui.clear", default: "Clear")) {
                            store.clearHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sampleText(for level: DictationLevel) -> String {
        level.sample(for: store.settings.style)
    }
}

private struct DictationLevelCard: View {
    let level: DictationLevel
    let isSelected: Bool
    let sampleText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(level.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.textPrimary)
                Spacer()
                if isSelected {
                    Text(L10n.string("ui.active", default: "Active"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(SettingsTheme.primaryAccent.opacity(0.12))
                        )
                        .foregroundStyle(SettingsTheme.primaryAccent)
                }
            }

            dots

            Text(level.tagline)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsTheme.textPrimary)

            Text("\u{201C}\(sampleText)\u{201D}")
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundStyle(SettingsTheme.textSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? SettingsTheme.primaryAccent.opacity(0.85)
                        : SettingsTheme.border,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isSelected
                ? SettingsTheme.primaryAccent.opacity(0.10)
                : Color.black.opacity(0.03),
            radius: isSelected ? 6 : 3,
            x: 0,
            y: isSelected ? 3 : 1
        )
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < level.dotCount
                        ? (isSelected
                            ? SettingsTheme.primaryAccent
                            : SettingsTheme.textPrimary.opacity(0.7))
                        : SettingsTheme.border)
                    .frame(width: 18, height: 4)
            }
        }
    }
}


/// Compact custom-vocabulary row. Replaces the always-visible minus button
/// with an X icon that only appears on hover — the resting state is clean,
/// the remove affordance is right there when the user goes to grab it.
/// Row for a single user-curated vocabulary term. Mirrors `HoverableTermRow`
/// in styling but adds a Menu-style strength picker so users can dial
/// off / normal / strong per term without leaving the list.
private struct CustomTermRow: View {
    let term: CustomVocabularyTerm
    let onChangeStrength: (VocabularyStrength) -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(term.text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(
                    term.strength == .off
                        ? SettingsTheme.textTertiary
                        : SettingsTheme.textPrimary
                )
                .strikethrough(term.strength == .off, color: SettingsTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            strengthMenu

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsTheme.primaryAccent.opacity(isHovered ? 0.10 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var strengthMenu: some View {
        Menu {
            ForEach(VocabularyStrength.allCases) { option in
                Button {
                    onChangeStrength(option)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                            Text(option.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(SettingsTheme.textSecondary)
                        }
                        if option == term.strength {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: strengthIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(term.strength.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(strengthColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(strengthColor.opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(term.strength.subtitle)
    }

    private var strengthIcon: String {
        switch term.strength {
        case .off:    return "pause.circle"
        case .normal: return "circle.fill"
        case .strong: return "sparkles"
        }
    }

    private var strengthColor: Color {
        switch term.strength {
        case .off:    return SettingsTheme.textTertiary
        case .normal: return SettingsTheme.textSecondary
        case .strong: return SettingsTheme.primaryAccent
        }
    }
}

private struct HoverableTermRow: View {
    let term: String
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(term)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(SettingsTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SettingsTheme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsTheme.primaryAccent.opacity(isHovered ? 0.10 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

