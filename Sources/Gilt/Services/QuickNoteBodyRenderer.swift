import AppKit
import Foundation

/// Markdown horizontal-rule attachment. Renders as a thin, full-width line.
/// Backed by `---` in the persisted markdown so the round-trip stays
/// compatible with any other markdown reader.
///
/// Implemented as an `NSTextAttachment` whose image is a pre-rendered line at
/// the editor's column width. Image-backed attachments compose cleanly with
/// the existing `QuickNoteImageTextAttachment` flow, avoid Swift 6 main-actor
/// gymnastics that come with subclassing `NSTextAttachmentCell`, and let us
/// tint the rule with the active theme's text color.
@MainActor
final class QuickNoteHorizontalRuleAttachment: NSTextAttachment {
    /// Total vertical space the rule reserves on its line. Picked to give
    /// breathing room above and below the line without feeling huge.
    static let layoutHeight: CGFloat = 22

    let displayWidth: CGFloat

    init(width: CGFloat, color: NSColor) {
        self.displayWidth = width
        super.init(data: nil, ofType: nil)
        let size = NSSize(width: width, height: Self.layoutHeight)
        let tint = color.withAlphaComponent(0.28)
        let image = NSImage(size: size, flipped: false) { rect in
            tint.setFill()
            let thickness: CGFloat = 1.0
            let y = rect.midY - thickness / 2
            NSRect(x: 0, y: y, width: rect.width, height: thickness).fill()
            return true
        }
        image.size = size
        self.image = image

        let cell = NSTextAttachmentCell(imageCell: image)
        cell.image = image
        attachmentCell = cell

        // y = -height keeps the layout box below the baseline so the rule
        // sits on its own visual line without overlapping the line above.
        bounds = CGRect(x: 0, y: -Self.layoutHeight, width: width, height: Self.layoutHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        bounds
    }
}

@MainActor
final class QuickNoteImageTextAttachment: NSTextAttachment {
    let imageID: UUID

    init(imageID: UUID, image: NSImage, maxWidth: CGFloat) {
        self.imageID = imageID
        super.init(data: nil, ofType: nil)

        let displaySize = NoteImageAttachmentStore.fittedDisplaySize(for: image, maxWidth: maxWidth)
        image.size = displaySize
        self.image = image

        let cell = NSTextAttachmentCell(imageCell: image)
        cell.image = image
        attachmentCell = cell

        // TextKit 1 lays out attachments on the text baseline; origin.y must be negative
        // by the full height so the image sits below the line and reserves line height.
        bounds = Self.layoutBounds(for: displaySize)
    }

    static func layoutBounds(for displaySize: NSSize) -> CGRect {
        CGRect(
            x: 0,
            y: -displaySize.height,
            width: displaySize.width,
            height: displaySize.height
        )
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        guard bounds.height > 0 else { return bounds }
        return bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
enum QuickNoteBodyRenderer {
    /// True if `line` is a Markdown horizontal-rule line: 3+ of `-`, `*`, or
    /// `_`, optionally interspersed with whitespace, and nothing else.
    static func isHorizontalRuleLine(_ line: String) -> Bool {
        let condensed = line.filter { !$0.isWhitespace }
        guard condensed.count >= 3 else { return false }
        let chars = Set(condensed)
        return chars == ["-"] || chars == ["*"] || chars == ["_"]
    }

    static func attributedString(
        from markdown: String,
        noteID: UUID,
        attachmentsRoot: URL,
        baseAttributes: [NSAttributedString.Key: Any],
        maxImageWidth: CGFloat
    ) -> NSAttributedString {
        let lines = markdown.components(separatedBy: "\n")
        let hasHRLine = lines.contains(where: isHorizontalRuleLine(_:))
        let hasImageRef = markdown.contains("![") && markdown.contains(QuickNoteImageMarkdown.schemePrefix)

        // No rules/images → still parse inline <b>/<i>/<u> formatting. Tag-free
        // notes resolve to a single plain run identical to the old fast path.
        if !hasHRLine && !hasImageRef {
            return QuickNoteInlineFormatting.attributedString(from: markdown, baseAttributes: baseAttributes)
        }

        let ruleColor = (baseAttributes[.foregroundColor] as? NSColor) ?? .labelColor
        let result = NSMutableAttributedString()
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            if isHorizontalRuleLine(line) {
                let hr = QuickNoteHorizontalRuleAttachment(width: maxImageWidth, color: ruleColor)
                result.append(NSAttributedString(attachment: hr))
                continue
            }
            result.append(processLineForImageRefs(
                line,
                noteID: noteID,
                attachmentsRoot: attachmentsRoot,
                baseAttributes: baseAttributes,
                maxImageWidth: maxImageWidth
            ))
        }

        return result
    }

    private static func processLineForImageRefs(
        _ line: String,
        noteID: UUID,
        attachmentsRoot: URL,
        baseAttributes: [NSAttributedString.Key: Any],
        maxImageWidth: CGFloat
    ) -> NSAttributedString {
        guard let regex = try? NSRegularExpression(pattern: QuickNoteImageMarkdown.referencePattern) else {
            return NSAttributedString(string: line, attributes: baseAttributes)
        }
        let nsLine = line as NSString
        let matches = regex.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        guard !matches.isEmpty else {
            return QuickNoteInlineFormatting.attributedString(from: line, baseAttributes: baseAttributes)
        }

        let result = NSMutableAttributedString()
        var cursor = 0

        for match in matches {
            let textRange = NSRange(location: cursor, length: match.range.location - cursor)
            if textRange.length > 0 {
                let text = nsLine.substring(with: textRange)
                result.append(QuickNoteInlineFormatting.attributedString(from: text, baseAttributes: baseAttributes))
            }

            if match.numberOfRanges > 1,
               let imageID = UUID(uuidString: nsLine.substring(with: match.range(at: 1))),
               let imageData = NoteImageAttachmentStore.load(imageID: imageID, noteID: noteID, root: attachmentsRoot),
               let image = NoteImageAttachmentStore.loadedDisplayImage(from: imageData) {
                let attachment = QuickNoteImageTextAttachment(
                    imageID: imageID,
                    image: image,
                    maxWidth: maxImageWidth
                )
                result.append(NSAttributedString(attachment: attachment))
            } else {
                let fallback = nsLine.substring(with: match.range)
                result.append(NSAttributedString(string: fallback, attributes: baseAttributes))
            }

            cursor = match.range.upperBound
        }

        if cursor < nsLine.length {
            let trailing = nsLine.substring(from: cursor)
            result.append(QuickNoteInlineFormatting.attributedString(from: trailing, baseAttributes: baseAttributes))
        }

        return result
    }

    static func markdown(from attributedString: NSAttributedString) -> String {
        let source = attributedString.string as NSString
        guard source.length > 0 else { return "" }

        // Fast path: notes with no embedded image/rule attachments — the
        // overwhelming common case — round-trip to their plain string. This
        // runs on EVERY keystroke; the general loop below probes every index
        // for the next attachment, which degrades toward O(n^2) on long
        // attachment-free notes and was a real source of typing lag.
        // `containsQuickNoteAttachments` walks attribute *runs* (not
        // characters), so this check is ~O(1) when there are none. The fast
        // path also requires no inline formatting — a styled run has to be
        // serialized back to <b>/<i>/<u> tags below.
        //
        // Invariant: serialization must reproduce the on-screen text verbatim
        // (attachments swapped for their markdown). Any normalization here
        // (the old "\n\n\n" -> "\n\n" collapse) desyncs the saved note from
        // what the user sees, and the drift compounds every open/edit cycle.
        // Literal tag tokens still get escaped — that's not normalization,
        // it's what makes the next render show the same characters.
        if !attributedString.containsQuickNoteAttachments && !attributedString.containsInlineFormatting {
            return QuickNoteInlineFormatting.escapeLiteralTags(source as String)
        }

        var parts: [String] = []
        var index = 0
        let fullRange = NSRange(location: 0, length: source.length)

        while index < source.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attachment = attributedString.attribute(
                .attachment,
                at: index,
                longestEffectiveRange: &effectiveRange,
                in: fullRange
            )

            if let quickNoteAttachment = attachment as? QuickNoteImageTextAttachment {
                // The surrounding newlines are real characters in the text
                // storage (insertEmbeddedImage puts them there), so the
                // adjacent plain-text segments already carry them. Synthesizing
                // extra "\n\n" here added a blank line on every save/load
                // cycle and the note kept growing.
                parts.append(QuickNoteImageMarkdown.imageReference(imageID: quickNoteAttachment.imageID))
                index = NSMaxRange(effectiveRange)
                continue
            }

            if attachment is QuickNoteHorizontalRuleAttachment {
                // A rule's source representation is the literal markdown `---`
                // on its own line. The surrounding newlines come from the
                // adjacent plain-text segments (we don't synthesize any here).
                parts.append("---")
                index = NSMaxRange(effectiveRange)
                continue
            }

            // No attachment at `index`: `longestEffectiveRange` already grouped
            // the entire run of attachment-free text (it only varies on the
            // .attachment attribute), so we serialize that run in one shot and
            // jump past it. This replaces an index-by-index probe that degraded
            // toward O(n^2) on long notes containing any attachment or inline
            // formatting — a confirmed source of typing lag.
            if effectiveRange.length > 0 {
                // Serialize the run so any bold/italic/underline becomes tags.
                let segment = attributedString.attributedSubstring(from: effectiveRange)
                let serialized = QuickNoteInlineFormatting.serialize(segment)
                if !serialized.isEmpty {
                    parts.append(serialized)
                }
                index = NSMaxRange(effectiveRange)
            } else {
                index += 1
            }
        }

        return parts.joined()
    }

    /// Plain-text approximation of a note body for non-editable previews
    /// (the swipe-transition ghost): image references removed, formatting
    /// tags stripped, escapes resolved — so raw markup never flashes on
    /// screen during the note-switch animation.
    static func plainPreviewText(from markdown: String) -> String {
        let withoutImages = QuickNoteImageMarkdown.plainTextReplacingImageReferences(markdown)
        guard withoutImages.contains("<") else { return withoutImages }
        return QuickNoteInlineFormatting.attributedString(from: withoutImages, baseAttributes: [:]).string
    }

    static func refreshNonAttachmentAttributes(
        in textStorage: NSTextStorage?,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        // Re-apply the theme's base attributes to every text run, but keep any
        // inline bold/italic/underline the user applied — re-derive the styled
        // font from the *new* base font so a theme/typography change doesn't
        // strip formatting. Collect first, then write, so we never mutate the
        // storage while enumerating it.
        let baseFont = baseAttributes[.font] as? NSFont
        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard value == nil else { return }
            textStorage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
                let traits = QuickNoteInlineFormatting.traits(from: attrs)
                if traits.isEmpty {
                    updates.append((subRange, baseAttributes))
                    return
                }
                var styled = baseAttributes
                if let baseFont {
                    styled[.font] = QuickNoteInlineFormatting.styledFont(
                        base: baseFont,
                        bold: traits.contains(.bold),
                        italic: traits.contains(.italic)
                    )
                }
                if traits.contains(.underline) {
                    styled[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                updates.append((subRange, styled))
            }
        }

        textStorage.beginEditing()
        for (range, attrs) in updates {
            textStorage.setAttributes(attrs, range: range)
        }
        textStorage.endEditing()
    }
}

extension NSAttributedString {
    /// True when the string carries at least one `.attachment` run. Used by
    /// `QuickNoteBodyRenderer.markdown(from:)` to take its plain-text fast path.
    /// `enumerateAttribute` advances by attribute run, so an attachment-free
    /// note resolves in a single step rather than scanning every character.
    var containsQuickNoteAttachments: Bool {
        var found = false
        enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: length),
            options: []
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
