import Foundation

enum NoteMarkdown {
    static let boardTitle = "Kanban Board"

    static func displayTitle(for markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                let stripped = trimmed.drop { $0 == "#" || $0 == " " }
                let title = String(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return title }
            }
            return trimmed
        }
        return "Untitled Note"
    }

    static func plainPreview(for markdown: String, limit: Int = 140) -> String {
        let normalized = QuickNoteImageMarkdown.plainTextReplacingImageReferences(markdown)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Empty note" }
        return String(normalized.prefix(limit))
    }

    static func bodyRemovingDuplicateTitle(_ body: String, title: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return body }

        let lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
        guard let firstContentIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return body
        }

        let firstLine = lines[firstContentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLineTitle = firstLine.hasPrefix("#")
            ? String(firstLine.drop { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespacesAndNewlines)
            : firstLine

        guard firstLineTitle.caseInsensitiveCompare(normalizedTitle) == .orderedSame else {
            return body
        }

        var remainingLines = Array(lines.dropFirst(firstContentIndex + 1))
        while remainingLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            remainingLines.removeFirst()
        }

        let remainingBody = remainingLines.joined(separator: "\n")
        return remainingBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? body : remainingBody
    }

    static func extractTasks(from note: NoteItem) -> [NoteTask] {
        let lines = note.bodyMarkdown.components(separatedBy: .newlines)
        var currentColumn: NoteTaskColumn = .todo
        var tasks: [NoteTask] = []

        for (index, line) in lines.enumerated() {
            if let column = parseColumnHeading(line) {
                currentColumn = column
                continue
            }
            guard let task = parseChecklistLine(line) else { continue }
            // Tasks under "Done" render checked even if the source line forgot
            // the `[x]`. Anywhere else, including custom columns, takes the
            // line's literal checked state so user-managed marks are preserved.
            let effectiveChecked = currentColumn.isDone ? true : task.isChecked
            tasks.append(
                NoteTask(
                    id: "\(note.noteID.uuidString)-\(index)-\(task.title)",
                    noteID: note.noteID,
                    lineIndex: index,
                    title: task.title,
                    column: currentColumn,
                    isChecked: effectiveChecked
                )
            )
        }

        return tasks
    }

    /// Returns the kanban columns present in `markdown`, in the order they
    /// appear. Always begins with the three built-ins (auto-inserted if
    /// missing) and is followed by any custom `## Heading` sections that
    /// appear after the board title.
    static func extractColumns(from markdown: String) -> [NoteTaskColumn] {
        let lines = markdown.components(separatedBy: .newlines)
        var seen: [NoteTaskColumn] = []
        var seenIDs = Set<String>()
        for line in lines {
            guard let column = parseColumnHeading(line) else { continue }
            if seenIDs.insert(column.id).inserted {
                seen.append(column)
            }
        }
        // Guarantee the defaults appear first and in canonical order even
        // if the file is incomplete (e.g. user manually deleted one). The
        // missing built-ins get re-added on the next write via
        // `ensureBoardHeadings`.
        var ordered: [NoteTaskColumn] = NoteTaskColumn.defaults
        for column in seen where !ordered.contains(where: { $0.id == column.id }) {
            ordered.append(column)
        }
        return ordered
    }

    static func moveTask(in markdown: String, lineIndex: Int, to column: NoteTaskColumn) -> String {
        moveTask(in: markdown, lineIndex: lineIndex, to: column, targetIndex: nil)
    }

    /// Moves a checklist line into `column`. When `targetIndex` is non-nil, the task is
    /// inserted at that position among the existing checklist lines already in the column
    /// (after the source line has been removed). Pass `nil` to append at the end.
    static func moveTask(
        in markdown: String,
        lineIndex: Int,
        to column: NoteTaskColumn,
        targetIndex: Int?
    ) -> String {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              let parsed = parseChecklistLine(lines[lineIndex]) else {
            return markdown
        }

        // Preserve the source line's checked state when moving between
        // non-Done columns; columns into/out of Done flip the box.
        let checked: Bool
        if column.isDone {
            checked = true
        } else if parsed.isChecked && sourceColumn(forLineIndex: lineIndex, in: lines)?.isDone == true {
            // Was previously in Done; moving out unchecks.
            checked = false
        } else {
            checked = parsed.isChecked
        }

        let movedLine = checklistLine(title: parsed.title, checked: checked)
        lines.remove(at: lineIndex)
        ensureBoardHeadings(in: &lines)
        ensureColumnHeading(column, in: &lines)

        let insertion = resolvedInsertionIndex(for: column, lines: lines, targetIndex: targetIndex)
        lines.insert(movedLine, at: insertion)
        return lines.joined(separator: "\n")
    }

    static func renameTask(in markdown: String, lineIndex: Int, newTitle: String) -> String {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return markdown }
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              let parsed = parseChecklistLine(lines[lineIndex]) else {
            return markdown
        }
        lines[lineIndex] = checklistLine(title: trimmed, checked: parsed.isChecked)
        return lines.joined(separator: "\n")
    }

    static func addTask(in markdown: String, title: String, to column: NoteTaskColumn) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return markdown }

        var lines = markdown.components(separatedBy: .newlines)
        ensureBoardHeadings(in: &lines)
        ensureColumnHeading(column, in: &lines)
        let taskLine = checklistLine(title: trimmed, checked: column.isDone)
        let insertionIndex = insertionIndex(for: column, lines: lines)
        lines.insert(taskLine, at: insertionIndex)
        return lines.joined(separator: "\n")
    }

    /// Adds a brand-new column heading to the kanban file. Built-in titles
    /// are normalized to their canonical form (so re-adding "todo" is a
    /// no-op). Existing custom columns with the same id are also no-ops.
    /// Returns the resulting markdown plus the resolved column.
    static func addColumn(in markdown: String, title: String) -> (markdown: String, column: NoteTaskColumn)? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let column = NoteTaskColumn.column(forMarkdownTitle: trimmed)
        var lines = markdown.components(separatedBy: .newlines)
        ensureBoardHeadings(in: &lines)
        ensureColumnHeading(column, in: &lines)
        return (lines.joined(separator: "\n"), column)
    }

    /// Removes a custom column and every checklist line currently inside it.
    /// Built-in columns are protected -- this is a no-op for `.todo`,
    /// `.doing`, `.done` to preserve the board's invariants.
    static func removeColumn(in markdown: String, column: NoteTaskColumn) -> String {
        guard !column.isBuiltIn else { return markdown }
        var lines = markdown.components(separatedBy: .newlines)
        guard let headingIndex = headingIndex(for: column, in: lines) else {
            return markdown
        }
        // Find the next `## ` heading or end-of-file -- everything up to that
        // (exclusive of any trailing `## ` line) belongs to this column.
        var sectionEnd = lines.count
        var cursor = headingIndex + 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                sectionEnd = cursor
                break
            }
            cursor += 1
        }
        lines.removeSubrange(headingIndex..<sectionEnd)
        // Collapse any duplicate blank lines left at the seam.
        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty, collapsed.last?.isEmpty == true { continue }
            collapsed.append(line)
        }
        return collapsed.joined(separator: "\n")
    }

    static func removeTask(in markdown: String, lineIndex: Int) -> String {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              parseChecklistLine(lines[lineIndex]) != nil else {
            return markdown
        }
        lines.remove(at: lineIndex)
        return lines.joined(separator: "\n")
    }

    static func checklistLine(title: String, checked: Bool) -> String {
        "- [\(checked ? "x" : " ")] \(title)"
    }

    /// Renames a board by replacing its H1 title line (`# …`) with `newTitle`,
    /// leaving every column and task untouched. If the markdown has no H1 yet,
    /// one is prepended. A board's display name lives in this H1, so this is the
    /// single source of truth the sidebar/tab titles mirror.
    static func renameBoard(in markdown: String, to newTitle: String) -> String {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return markdown }
        var lines = markdown.components(separatedBy: .newlines)
        // First level-1 heading only (`# Foo`), never a column heading (`## Foo`).
        if let h1Index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }) {
            lines[h1Index] = "# \(trimmed)"
            return lines.joined(separator: "\n")
        }
        return "# \(trimmed)\n\n" + markdown
    }

    static func emptyBoardTemplate(title: String = boardTitle) -> String {
        """
        # \(title)

        ## Todo

        ## Doing

        ## Done
        """
    }

    static func isKanbanBoard(markdown: String) -> Bool {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.localizedCaseInsensitiveContains("# \(boardTitle)") else {
            return false
        }

        return NoteTaskColumn.defaults.allSatisfy { column in
            normalized.localizedCaseInsensitiveContains(column.heading)
        }
    }

    private static func ensureBoardHeadings(in lines: inout [String]) {
        for column in NoteTaskColumn.defaults {
            ensureColumnHeading(column, in: &lines)
        }
    }

    private static func ensureColumnHeading(_ column: NoteTaskColumn, in lines: inout [String]) {
        if headingIndex(for: column, in: lines) != nil { return }
        if !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append(column.heading)
        lines.append("")
    }

    /// Case-insensitive heading lookup so capitalization drift in the file
    /// (e.g. user-typed `## todo`) still resolves to the right column.
    private static func headingIndex(for column: NoteTaskColumn, in lines: [String]) -> Int? {
        for (index, line) in lines.enumerated() {
            guard let parsed = parseColumnHeading(line) else { continue }
            if parsed.id == column.id { return index }
        }
        return nil
    }

    private static func insertionIndex(for column: NoteTaskColumn, lines: [String]) -> Int {
        guard let headingIndex = headingIndex(for: column, in: lines) else {
            return lines.count
        }

        var index = headingIndex + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") { break }
            index += 1
        }
        return index
    }

    /// Returns the absolute line index where a task should be inserted within `column`.
    /// If `targetIndex` is provided, it is interpreted as the zero-based position among
    /// the existing checklist lines already in that column (clamped to range). `nil`
    /// appends after the last checklist line in the section.
    private static func resolvedInsertionIndex(
        for column: NoteTaskColumn,
        lines: [String],
        targetIndex: Int?
    ) -> Int {
        guard let headingIndex = headingIndex(for: column, in: lines) else {
            return lines.count
        }

        // Walk the column section once, recording the absolute line index of every
        // checklist row plus where the section ends.
        var checklistIndices: [Int] = []
        var sectionEnd = lines.count
        var cursor = headingIndex + 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                sectionEnd = cursor
                break
            }
            if parseChecklistLine(lines[cursor]) != nil {
                checklistIndices.append(cursor)
            }
            cursor += 1
        }

        guard let targetIndex else {
            return checklistIndices.last.map { $0 + 1 } ?? sectionEnd
        }
        if targetIndex <= 0 {
            return checklistIndices.first ?? sectionEnd
        }
        if targetIndex >= checklistIndices.count {
            return checklistIndices.last.map { $0 + 1 } ?? sectionEnd
        }
        return checklistIndices[targetIndex]
    }

    /// Parses an `## …` line as a kanban column heading. Returns the
    /// resolved `NoteTaskColumn` (built-in or custom) or nil if the line
    /// isn't a level-2 heading.
    private static func parseColumnHeading(_ line: String) -> NoteTaskColumn? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("## ") else { return nil }
        let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return NoteTaskColumn.column(forMarkdownTitle: title)
    }

    /// Identifies which column a checklist line currently lives under by
    /// scanning back to the most recent `## ` heading. Used by `moveTask` to
    /// decide whether the source was Done (so its check should clear when
    /// moved elsewhere).
    private static func sourceColumn(forLineIndex lineIndex: Int, in lines: [String]) -> NoteTaskColumn? {
        var cursor = min(lineIndex, lines.count - 1)
        while cursor >= 0 {
            if let column = parseColumnHeading(lines[cursor]) {
                return column
            }
            cursor -= 1
        }
        return nil
    }

    private static func parseChecklistLine(_ line: String) -> (title: String, isChecked: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "* [x] ", "* [X] "]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            let checked = prefix.lowercased().contains("[x]")
            let title = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return (title, checked)
        }
        return nil
    }
}
