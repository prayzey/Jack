import AppKit
import SwiftUI
import XCTest
@testable import Gilt

final class QuickNoteBrowserTests: XCTestCase {

    @MainActor
    func testBrowserSearchPlaceholderStaysReadableAcrossEveryStyleAndAppAppearance() throws {
        for style in QuickNoteStyle.allCases {
            for colorScheme in [ColorScheme.light, .dark] {
                let (darkPixels, lightPixels) = try renderedPromptPixelCounts(
                    style: style,
                    colorScheme: colorScheme
                )
                let message = "Expected readable search text for \(style.rawValue) in \(colorScheme) appearance"
                if style.isLightSurface {
                    XCTAssertGreaterThan(darkPixels, 20, message)
                } else {
                    XCTAssertGreaterThan(lightPixels, 20, message)
                }
            }
        }
    }

    @MainActor
    func testBrowserRowShowsDeleteActionWithoutHover() throws {
        let row = QuickNoteBrowserRow(
            note: quickNote("Title"),
            isCurrent: false,
            primaryText: .clear,
            secondaryText: .black,
            accent: .clear,
            onSelect: {},
            onDelete: {}
        )
        .frame(width: 440, height: 64)
        .background(Color.white)
        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 64)
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let timestampPixels = darkPixelCount(in: 340..<390, bitmap: bitmap, scaleX: scaleX)
        let deletePixels = darkPixelCount(in: 410..<430, bitmap: bitmap, scaleX: scaleX)
        XCTAssertGreaterThan(
            timestampPixels,
            5,
            "The timestamp should remain visible beside the delete action"
        )
        XCTAssertGreaterThan(
            deletePixels,
            70,
            "The delete action should be visible before the pointer hovers over the row"
        )
    }

    @MainActor
    private func renderedPromptPixelCounts(
        style: QuickNoteStyle,
        colorScheme: ColorScheme
    ) throws -> (dark: Int, light: Int) {
        let overlay = QuickNoteBrowserOverlay(
            isPresented: .constant(true),
            notes: [],
            currentNoteID: nil,
            style: style,
            onSelect: { _ in },
            onCreate: {},
            onDelete: { _ in }
        )
        .frame(width: 500, height: 600)
        .environment(\.colorScheme, colorScheme)
        let host = NSHostingView(rootView: overlay)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        let promptX = Int(64 * scaleX)..<Int(180 * scaleX)
        let promptY = Int(32 * scaleY)..<Int(65 * scaleY)
        return promptX.reduce(into: (dark: 0, light: 0)) { counts, x in
            for y in promptY {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.alphaComponent > 0.2 else { continue }
                if color.brightnessComponent < 0.75 { counts.dark += 1 }
                if color.brightnessComponent > 0.35 { counts.light += 1 }
            }
        }
    }

    // MARK: - Markdown fast path

    /// The attachment-free fast path in `markdown(from:)` must produce the exact
    /// same string the general loop did — including the 3+ newline collapse.
    @MainActor
    func testMarkdownFastPathRoundTripsPlainText() {
        let plain = NSAttributedString(string: "Hello\nWorld")
        XCTAssertEqual(QuickNoteBodyRenderer.markdown(from: plain), "Hello\nWorld")
    }

    @MainActor
    func testMarkdownFastPathPreservesBlankLinesVerbatim() {
        // The fast path must reproduce the on-screen text exactly: the old
        // triple-newline collapse desynced the saved note from the editor and
        // blank lines silently shrank on every open/edit cycle.
        let spaced = NSAttributedString(string: "a\n\n\nb")
        XCTAssertEqual(QuickNoteBodyRenderer.markdown(from: spaced), "a\n\n\nb")
    }

    @MainActor
    func testMarkdownFastPathEmptyString() {
        XCTAssertEqual(QuickNoteBodyRenderer.markdown(from: NSAttributedString(string: "")), "")
    }

    @MainActor
    func testPlainStringHasNoAttachments() {
        XCTAssertFalse(NSAttributedString(string: "just text").containsQuickNoteAttachments)
    }

    // MARK: - Browser snippet

    @MainActor
    func testSnippetReturnsBodyAfterTitle() {
        let note = quickNote("My Title\nSome body text")
        XCTAssertEqual(quickNoteBrowserSnippet(for: note), "Some body text")
    }

    @MainActor
    func testSnippetStripsLeadingMarkdownTokens() {
        XCTAssertEqual(quickNoteBrowserSnippet(for: quickNote("Heading\n## Section")), "Section")
        XCTAssertEqual(quickNoteBrowserSnippet(for: quickNote("Heading\n> quoted")), "quoted")
        XCTAssertEqual(quickNoteBrowserSnippet(for: quickNote("Heading\n- bullet")), "bullet")
        XCTAssertEqual(quickNoteBrowserSnippet(for: quickNote("Heading\n- [ ] task")), "task")
    }

    @MainActor
    func testSnippetSkipsImageAndRuleLines() {
        let note = quickNote("Title\n![pic](gilt-note-image://abc)\n---\nReal body")
        XCTAssertEqual(quickNoteBrowserSnippet(for: note), "Real body")
    }

    @MainActor
    func testSnippetEmptyWhenOnlyTitle() {
        XCTAssertEqual(quickNoteBrowserSnippet(for: quickNote("Only a title")), "")
        XCTAssertEqual(quickNoteBrowserSnippet(for: quickNote("")), "")
    }

    private func quickNote(_ body: String) -> NoteItem {
        NoteItem(folderID: NoteFolder.scratchpadsID, bodyMarkdown: body, origin: .quickNote)
    }

    private func darkPixelCount(
        in logicalXRange: Range<Int>,
        bitmap: NSBitmapImageRep,
        scaleX: CGFloat
    ) -> Int {
        logicalXRange.reduce(into: 0) { count, logicalX in
            let pixelX = Int(CGFloat(logicalX) * scaleX)
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: pixelX, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.2, color.brightnessComponent < 0.5 { count += 1 }
            }
        }
    }

}
