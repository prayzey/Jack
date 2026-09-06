import AppKit
import Foundation

/// Transient feedback shown after an on-device AI action. Auto-dismisses; see `presentAIToast`.
struct AIToast: Identifiable, Equatable {
    enum Kind: Equatable { case success, failure, info }
    let id = UUID()
    let message: String
    let kind: Kind
}

/// On-device AI actions on clips, powered by `OnDeviceAIService` (Apple's Foundation model).
///
/// Delivery model (deliberate, and tray-window safe): text-producing actions write their result to
/// the system clipboard, which `ClipboardMonitor` then captures as a brand-new clip. So the result
/// shows up in history, ready to paste, and the ORIGINAL clip is never mutated. Only `aiRetitleClip`
/// edits a clip in place, because a title is just the card's label and is freely editable.
extension ClipboardStore {

    /// Whether per-clip AI actions should be offered right now (feature on + model usable).
    var aiClipActionsAvailable: Bool {
        settings.aiFeaturesEnabled
            && settings.aiClipActionsEnabled
            && OnDeviceAIService.shared.isUsable
    }

    /// Best text to feed the model for a clip: real text, then link title + URL, then OCR, then preview.
    func aiSourceText(for clip: ClipItemModel) -> String {
        if let text = clip.textValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let url = clip.urlValue, !url.isEmpty {
            let title = clip.linkPageTitle ?? clip.title
            return [title, url].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if let ocr = clip.recognizedText, !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ocr
        }
        return clip.previewText
    }

    /// Whether a clip has anything worth running AI on (drives whether the menu shows for it).
    func aiHasUsableText(_ clip: ClipItemModel) -> Bool {
        !aiSourceText(for: clip).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Text actions (result copied to the clipboard as a new clip)

    func runAITextAction(_ action: AITextAction, on clipID: UUID) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        let source = aiSourceText(for: clip)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentAIToast(L10n.string("ai.toast.nothingToProcess", default: "There's no text here to work with."), kind: .info)
            return
        }
        performClipAI(clipID: clipID) {
            try await OnDeviceAIService.shared.respond(instructions: action.instruction, to: source)
        } onSuccess: { [weak self] result in
            self?.deliverAIText(result)
            let template = L10n.string("ai.toast.copied", default: "%@ copied to your clipboard.")
            self?.presentAIToast(String(format: template, action.resultNoun), kind: .success)
        }
    }

    /// Generate a short title and apply it to the clip in place.
    func aiRetitleClip(_ clipID: UUID) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        let source = aiSourceText(for: clip)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentAIToast(L10n.string("ai.toast.nothingToProcess", default: "There's no text here to work with."), kind: .info)
            return
        }
        let instruction = "You write very short, descriptive titles. Reply with ONLY a title of at most six words: no quotation marks, no trailing period, no explanation. Use the same language as the text."
        performClipAI(clipID: clipID) {
            try await OnDeviceAIService.shared.respond(instructions: instruction, to: source)
        } onSuccess: { [weak self] result in
            let cleaned = Self.cleanGeneratedTitle(result)
            guard !cleaned.isEmpty else { return }
            clip.title = cleaned
            self?.save()
            self?.presentAIToast(L10n.string("ai.toast.renamed", default: "Card renamed."), kind: .success)
        }
    }

    /// Extract action items as a markdown checklist and copy them to the clipboard.
    func aiExtractActionItems(_ clipID: UUID) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        let source = aiSourceText(for: clip)
        guard #available(macOS 26.0, *) else {
            presentAIToast(OnDeviceAIError.unsupported(.unsupportedOS).localizedDescription ?? "", kind: .failure)
            return
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentAIToast(L10n.string("ai.toast.nothingToProcess", default: "There's no text here to work with."), kind: .info)
            return
        }
        extractActionItems(
            from: source,
            instruction: "Extract every concrete task, to-do, or commitment from the user's text. Return an empty list if there are none. Keep each item short and in its original language.",
            busyID: clipID,
            busySet: \.aiBusyClipIDs
        )
    }

    /// Detect an actionable reminder in the clip and, if found, add it (mirroring to Apple Reminders
    /// when the user has that sync turned on).
    func aiCreateReminder(from clipID: UUID) {
        guard let clip = clips.first(where: { $0.clipID == clipID }) else { return }
        let source = aiSourceText(for: clip)
        guard #available(macOS 26.0, *) else {
            presentAIToast(OnDeviceAIError.unsupported(.unsupportedOS).localizedDescription ?? "", kind: .failure)
            return
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentAIToast(L10n.string("ai.toast.nothingToProcess", default: "There's no text here to work with."), kind: .info)
            return
        }
        aiBusyClipIDs.insert(clipID)
        let instruction = "Decide whether the user's text contains something to be reminded about (a task, deadline, or commitment). If it does, write a short imperative reminder title and copy any mentioned date or time verbatim."
        let sourceTitle = clip.title.isEmpty ? clip.previewText : clip.title
        Task { [weak self] in
            defer { self?.aiBusyClipIDs.remove(clipID) }
            do {
                let draft = try await OnDeviceAIService.shared.respond(
                    instructions: instruction,
                    to: source,
                    generating: AIReminderDraft.self
                )
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard draft.isActionable, !title.isEmpty else {
                    self?.presentAIToast(L10n.string("ai.toast.noReminder", default: "Nothing here looked like a reminder."), kind: .info)
                    return
                }
                let when = draft.whenText.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = when.isEmpty ? title : "\(title) (\(when))"
                self?.addPulseReminder(PulseReminder(message: message, sourceTitle: sourceTitle))
                self?.presentAIToast(L10n.string("ai.toast.reminderCreated", default: "Reminder created."), kind: .success)
            } catch {
                self?.presentAIToast(Self.aiMessage(for: error), kind: .failure)
            }
        }
    }

    // MARK: - Quick Note / workspace note actions (result copied to clipboard)

    /// Whether note AI actions should be offered (feature on + model usable).
    var aiNoteActionsAvailable: Bool {
        settings.aiFeaturesEnabled
            && settings.aiNoteAssistEnabled
            && OnDeviceAIService.shared.isUsable
    }

    func runAINoteTextAction(_ action: AITextAction, noteID: UUID) {
        guard let note = note(with: noteID) else { return }
        let source = note.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            presentAIToast(L10n.string("ai.toast.noteEmpty", default: "This note is empty."), kind: .info)
            return
        }
        aiBusyNoteIDs.insert(noteID)
        Task { [weak self] in
            defer { self?.aiBusyNoteIDs.remove(noteID) }
            do {
                let result = try await OnDeviceAIService.shared.respond(instructions: action.instruction, to: source)
                self?.deliverAIText(result)
                let template = L10n.string("ai.toast.copied", default: "%@ copied to your clipboard.")
                self?.presentAIToast(String(format: template, action.resultNoun), kind: .success)
            } catch {
                self?.presentAIToast(Self.aiMessage(for: error), kind: .failure)
            }
        }
    }

    func aiExtractNoteActionItems(_ noteID: UUID) {
        guard let note = note(with: noteID) else { return }
        let source = note.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard #available(macOS 26.0, *) else {
            presentAIToast(OnDeviceAIError.unsupported(.unsupportedOS).localizedDescription ?? "", kind: .failure)
            return
        }
        guard !source.isEmpty else {
            presentAIToast(L10n.string("ai.toast.noteEmpty", default: "This note is empty."), kind: .info)
            return
        }
        extractActionItems(
            from: source,
            instruction: "Extract every concrete task, to-do, or commitment from the note. Return an empty list if there are none. Keep each item short and in its original language.",
            busyID: noteID,
            busySet: \.aiBusyNoteIDs
        )
    }

    /// Shared body for clip/note action-item extraction: run the model, build a
    /// markdown checklist, deliver it to the clipboard, and toast the outcome.
    @available(macOS 26.0, *)
    private func extractActionItems(
        from source: String,
        instruction: String,
        busyID: UUID,
        busySet: ReferenceWritableKeyPath<ClipboardStore, Set<UUID>>
    ) {
        self[keyPath: busySet].insert(busyID)
        Task { [weak self] in
            defer { self?[keyPath: busySet].remove(busyID) }
            do {
                let result = try await OnDeviceAIService.shared.respond(
                    instructions: instruction,
                    to: source,
                    generating: AIActionItemList.self
                )
                let items = result.items
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !items.isEmpty else {
                    self?.presentAIToast(L10n.string("ai.toast.noActionItems", default: "No action items found here."), kind: .info)
                    return
                }
                let checklist = items.map { "- [ ] \($0)" }.joined(separator: "\n")
                self?.deliverAIText(checklist)
                self?.presentAIToast(L10n.string("ai.toast.actionItemsCopied", default: "Action items copied to your clipboard."), kind: .success)
            } catch {
                self?.presentAIToast(Self.aiMessage(for: error), kind: .failure)
            }
        }
    }

    // MARK: - Natural-language search

    /// Whether the natural-language search affordance should appear.
    var aiSearchAvailable: Bool {
        settings.aiFeaturesEnabled
            && settings.aiNaturalLanguageSearchEnabled
            && OnDeviceAIService.shared.isUsable
    }

    /// Interpret the current free-form `searchText` into the structured filter tokens the existing
    /// search already understands (`type:`, `app:`, keywords), then rewrite `searchText` so the
    /// normal filter does the rest. The rewritten query stays visible and editable.
    func aiInterpretSearch() {
        let raw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard aiSearchAvailable, !raw.isEmpty else { return }
        guard #available(macOS 26.0, *) else {
            presentAIToast(OnDeviceAIError.unsupported(.unsupportedOS).localizedDescription ?? "", kind: .failure)
            return
        }
        aiSearchInterpreting = true
        let instruction = "You convert a person's plain-language search of their clipboard history into filters. Choose a content type only if it's clearly implied. Pull out a source app name only if one is named. Reduce the rest to the core keywords, dropping filler words."
        Task { [weak self] in
            guard let self else { return }
            defer { self.aiSearchInterpreting = false }
            do {
                let result = try await OnDeviceAIService.shared.respond(
                    instructions: instruction,
                    to: raw,
                    generating: AISearchInterpretation.self
                )
                self.searchText = Self.composeSearchQuery(from: result, fallback: raw)
            } catch {
                self.presentAIToast(Self.aiMessage(for: error), kind: .failure)
            }
        }
    }

    @available(macOS 26.0, *)
    static func composeSearchQuery(from interpretation: AISearchInterpretation, fallback: String) -> String {
        var tokens: [String] = []
        let validTypes = Set(ClipType.allCases.map { $0.rawValue })
        let type = interpretation.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if validTypes.contains(type) {
            tokens.append("type:\(type)")
        }
        // The token parser splits on whitespace, so an app filter must be a single token.
        if let appWord = interpretation.app
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init), !appWord.isEmpty {
            tokens.append("app:\(appWord.lowercased())")
        }
        let keywords = interpretation.keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keywords.isEmpty {
            tokens.append(keywords)
        }
        let composed = tokens.joined(separator: " ")
        return composed.isEmpty ? fallback : composed
    }

    // MARK: - Automatic enrichment on capture (opt-in, runs in the background)

    /// When enabled, give a freshly captured clip an AI title and/or topic tags. Runs off the
    /// capture path so it never slows down a copy, stays silent on error, and skips sensitive
    /// clips entirely (credentials etc. must never be sent through the model, even on-device).
    func scheduleAIClipEnrichmentIfNeeded(for clip: ClipItemModel) {
        guard settings.aiFeaturesEnabled, OnDeviceAIService.shared.isUsable else { return }
        let wantTitle = settings.aiAutoTitleEnabled
        let wantTags = settings.aiSmartTaggingEnabled
        guard wantTitle || wantTags else { return }
        guard clip.clipType == .text || clip.clipType == .link else { return }
        guard !clip.isSensitive else { return }

        let trimmed = aiSourceText(for: clip).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 60 else { return }
        // A generated title only earns its place for genuinely long captures; short clips keep the
        // natural title from capture.
        let longEnoughForTitle = trimmed.count >= 200
        let clipID = clip.clipID

        guard #available(macOS 26.0, *) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let instruction = "You label clipboard items. Provide a short descriptive title and a few lowercase topic keywords. Use the same language as the text."
                let draft = try await OnDeviceAIService.shared.respond(
                    instructions: instruction,
                    to: trimmed,
                    generating: AIClipEnrichmentDraft.self
                )
                // The clip may have been deleted while the model was thinking — re-resolve it.
                guard let live = self.clips.first(where: { $0.clipID == clipID }) else { return }
                var changed = false
                if wantTags {
                    let tags = Array(draft.tags.prefix(5))
                    if !tags.isEmpty {
                        live.aiKeywords = tags
                        changed = true
                    }
                }
                if wantTitle, longEnoughForTitle {
                    let title = Self.cleanGeneratedTitle(draft.title)
                    if !title.isEmpty {
                        live.title = title
                        changed = true
                    }
                }
                if changed { self.scheduleMetadataSave() }
            } catch {
                // Automatic enrichment is best-effort and must stay invisible on failure.
            }
        }
    }

    // MARK: - Internals

    /// Run a text-returning AI task with busy-state + error handling on the main actor.
    private func performClipAI(
        clipID: UUID,
        _ work: @escaping () async throws -> String,
        onSuccess: @escaping (String) -> Void
    ) {
        aiBusyClipIDs.insert(clipID)
        Task { [weak self] in
            defer { self?.aiBusyClipIDs.remove(clipID) }
            do {
                let result = try await work()
                onSuccess(result)
            } catch {
                self?.presentAIToast(Self.aiMessage(for: error), kind: .failure)
            }
        }
    }

    /// Place AI-produced text on the clipboard. `ClipboardMonitor` ingests it as a new clip on its
    /// next poll, so the result lands in history without us touching the original clip or SwiftData.
    func deliverAIText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
    }

    func presentAIToast(_ message: String, kind: AIToast.Kind) {
        guard !message.isEmpty else { return }
        let toast = AIToast(message: message, kind: kind)
        aiToast = toast
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            if self?.aiToast?.id == toast.id {
                self?.aiToast = nil
            }
        }
    }

    func dismissAIToast() {
        aiToast = nil
    }

    /// Strip quotes/extra lines the model sometimes adds, keep it to a single tidy line.
    static func cleanGeneratedTitle(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = line.split(separator: "\n").first {
            line = String(firstLine)
        }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
        if line.hasSuffix(".") { line.removeLast() }
        if line.count > 60 {
            line = String(line.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return line
    }

    static func aiMessage(for error: Error) -> String {
        if let aiError = error as? OnDeviceAIError, let description = aiError.errorDescription {
            return description
        }
        return L10n.string("ai.error.generic", default: "The on-device model couldn't finish that request. Please try again.")
    }
}

extension AppSettings {
    /// Best-effort read of the persisted settings snapshot straight from UserDefaults. Used by
    /// subsystems (e.g. meetings) that intentionally avoid holding a `ClipboardStore` reference but
    /// still need to read a user preference. Mirrors the key `ClipboardStore` persists to
    /// (`settingsKey = "GiltAppSettings"`); kept in sync because the store writes on every change.
    static func currentPersisted() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "GiltAppSettings"),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }
}
