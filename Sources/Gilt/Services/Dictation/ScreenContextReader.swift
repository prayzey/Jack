import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit
import Vision

/// Reads textual content from the frontmost window using two tiers:
///   1. Accessibility tree walk — fast, free, no Screen Recording permission.
///   2. ScreenCaptureKit one-shot screenshot → Vision text recognition.
///
/// Used by `ScreenContextService` to build a list of candidate terms that bias
/// dictation transcription. This file is pure capture — it returns raw text
/// strings. Term extraction lives in `ScreenContextExtractor`.
///
/// All capture work is bounded by a short timeout (300ms) so a misbehaving
/// app (or a slow OCR pass on a 4K screen) never holds up the dictation
/// session start.
@MainActor
final class ScreenContextReader {
    enum ReaderError: Error {
        case noFrontmostApp
        case noTargetWindow
        case axTreeUnavailable
        case captureFailed(String)
        case ocrFailed(String)
        case timedOut
    }

    struct CaptureResult {
        var text: String
        var source: Source
        var frontmostBundleID: String?
        var frontmostName: String?
    }

    enum Source: String {
        case accessibility
        case ocr
        case combined
    }

    private let logger = Logger(subsystem: AppBrand.logSubsystem, category: "ScreenContextReader")

    /// Hard upper bound on any single capture path. ScreenCaptureKit + Vision
    /// is usually 80–200ms total; AX is typically <30ms. We never want to
    /// delay dictation start by more than a third of a second.
    private let timeoutNanoseconds: UInt64 = 300_000_000

    // MARK: - Public

    /// Capture textual context using the mode the user picked in settings.
    /// Returns nil when the frontmost app is excluded or no text can be
    /// gathered — callers should treat that as "no bias applied, continue
    /// normally."
    func capture(
        mode: ScreenContextMode,
        excludedBundleIDs: Set<String>,
        axMinimumChars: Int
    ) async -> CaptureResult? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            logger.debug("No frontmost app — skipping context capture")
            return nil
        }
        if let bundleID = frontmost.bundleIdentifier, excludedBundleIDs.contains(bundleID) {
            logger.debug("Frontmost app \(bundleID) is excluded — skipping context capture")
            return nil
        }
        // Never read our own UI — it's never useful and pulling the AX tree
        // for the dictation overlay would just bias on phrases like
        // "Listening" or "Jack".
        if let bundleID = frontmost.bundleIdentifier, bundleID == Bundle.main.bundleIdentifier {
            logger.debug("Frontmost is Jack itself, skipping context capture")
            return nil
        }

        let appName = frontmost.localizedName
        let bundleID = frontmost.bundleIdentifier

        switch mode {
        case .accessibilityOnly:
            let text = await runBounded { [weak self] in
                await self?.readAccessibilityText(for: frontmost) ?? ""
            }
            guard let text, !text.isEmpty else { return nil }
            return CaptureResult(text: text, source: .accessibility, frontmostBundleID: bundleID, frontmostName: appName)

        case .ocrOnly:
            let text = await runBounded { [weak self] in
                (try? await self?.readOCRText(for: frontmost)) ?? ""
            }
            guard let text, !text.isEmpty else { return nil }
            return CaptureResult(text: text, source: .ocr, frontmostBundleID: bundleID, frontmostName: appName)

        case .accessibilityWithOCRFallback:
            // Try AX first. If we get a reasonable chunk back, use it as-is.
            // Otherwise, *combine* AX (window title, breadcrumbs) with OCR
            // (visible body text) — empirically the union is stronger than
            // either alone.
            let axText = await runBounded { [weak self] in
                await self?.readAccessibilityText(for: frontmost) ?? ""
            } ?? ""
            if axText.count >= axMinimumChars {
                return CaptureResult(text: axText, source: .accessibility, frontmostBundleID: bundleID, frontmostName: appName)
            }
            let ocrText = await runBounded { [weak self] in
                (try? await self?.readOCRText(for: frontmost)) ?? ""
            } ?? ""
            let combined = [axText, ocrText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !combined.isEmpty else { return nil }
            let source: Source = axText.isEmpty
                ? .ocr
                : (ocrText.isEmpty ? .accessibility : .combined)
            return CaptureResult(text: combined, source: source, frontmostBundleID: bundleID, frontmostName: appName)
        }
    }

    // MARK: - Timeout wrapper

    private func runBounded<T: Sendable>(
        _ op: @escaping @Sendable () async -> T
    ) async -> T? {
        // Race the operation against a sleep. Whichever finishes first wins.
        // The loser is cancelled.
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await op() }
            group.addTask { [timeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Accessibility tree walk

    /// Walk the AXUIElement tree of the frontmost app and concatenate every
    /// AXValue / AXTitle / AXDescription / AXHelp string we find. Bounded by
    /// node count + a max depth so a misbehaving app can't infinite-loop us.
    private func readAccessibilityText(for app: NSRunningApplication) async -> String {
        // AX calls block — hop off the main actor.
        let pid = app.processIdentifier
        return await Task.detached(priority: .userInitiated) {
            ScreenContextReader.collectAXText(forPID: pid)
        }.value
    }

    /// Static so we can call from a detached task without capturing self.
    nonisolated private static func collectAXText(forPID pid: pid_t) -> String {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        // Prefer the focused window if we can identify it; fall back to the
        // first window. Many apps don't reliably set focused on background.
        let focusedErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focused
        )
        let targetWindow: AXUIElement?
        // A .success status doesn't guarantee an AXUIElement type. `as?` can't validate
        // a CoreFoundation type (it always succeeds), so check the CFTypeID; on a
        // mismatch, fall through to the kAXWindowsAttribute fallback below.
        if focusedErr == .success, let value = focused, CFGetTypeID(value) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            targetWindow = (value as! AXUIElement)
        } else {
            var windows: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windows
            )
            if err == .success,
               let array = windows as? [AXUIElement],
               let first = array.first {
                targetWindow = first
            } else {
                targetWindow = nil
            }
        }
        guard let window = targetWindow else { return "" }

        var collected: [String] = []
        var totalChars = 0
        var visited = 0
        // Tighter limits than before. The extractor only mines short
        // identifier-ish tokens, so we don't need pages of body text. These
        // caps put a hard ceiling on the AX walk's memory cost (≈200KB worst
        // case) and prevent runaway accumulation in apps with massive text
        // areas (code editors, terminals).
        let maxNodes = 1500
        let maxDepth = 25
        let maxCharsPerAttr = 400
        let maxTotalChars = 100_000
        let textAttrs: [CFString] = [
            kAXValueAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXPlaceholderValueAttribute as CFString,
            "AXSelectedText" as CFString
        ]

        func walk(_ element: AXUIElement, depth: Int) {
            if visited >= maxNodes || depth > maxDepth || totalChars >= maxTotalChars { return }
            visited += 1
            for attr in textAttrs {
                if totalChars >= maxTotalChars { break }
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attr, &value) == .success,
                   let str = value as? String {
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    // Truncate long blobs (code, prose) — we only need enough
                    // for the extractor to find identifier tokens.
                    let snippet = trimmed.count > maxCharsPerAttr
                        ? String(trimmed.prefix(maxCharsPerAttr))
                        : trimmed
                    collected.append(snippet)
                    totalChars += snippet.count
                }
            }
            // Visible-children first when available — drastically reduces
            // noise from offscreen sidebars and collapsed panels.
            var children: CFTypeRef?
            let visErr = AXUIElementCopyAttributeValue(
                element,
                kAXVisibleChildrenAttribute as CFString,
                &children
            )
            if visErr != .success || children == nil {
                _ = AXUIElementCopyAttributeValue(
                    element,
                    kAXChildrenAttribute as CFString,
                    &children
                )
            }
            if let array = children as? [AXUIElement] {
                for child in array {
                    if visited >= maxNodes { break }
                    walk(child, depth: depth + 1)
                }
            }
        }
        walk(window, depth: 0)
        return collected.joined(separator: "\n")
    }

    // MARK: - ScreenCaptureKit + Vision OCR

    /// Grab a single PNG-equivalent CGImage of the frontmost window, then
    /// run Vision text recognition on it. Returns the joined recognized text.
    private func readOCRText(for app: NSRunningApplication) async throws -> String {
        let cgImage = try await captureFrontmostWindowImage(for: app)
        return try await recognizeText(in: cgImage)
    }

    private func captureFrontmostWindowImage(for app: NSRunningApplication) async throws -> CGImage {
        // SCShareableContent enumerates every capturable window on the system.
        // The first call after install triggers the Screen Recording TCC prompt.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ReaderError.captureFailed("SCShareableContent failed: \(error.localizedDescription)")
        }

        // Pick the largest on-screen window belonging to the frontmost app.
        // "Largest" because apps often have helper windows (pickers, palettes)
        // that we don't care about — the main document window wins by area.
        let pid = app.processIdentifier
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID == pid && window.isOnScreen
        }
        guard let target = candidates.max(by: { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }) else {
            throw ReaderError.noTargetWindow
        }

        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        // Vision's fast-path OCR is resolution-tolerant down to ~1x screen
        // points, and the CGImage memory cost scales O(w*h*4). Cap each axis
        // at 1600 px — that's ~10MB for a square image vs ~26MB at 2560 —
        // and we get the same term recall.
        let pointScale: CGFloat = 1.0
        let rawWidth = Int(target.frame.width * pointScale)
        let rawHeight = Int(target.frame.height * pointScale)
        config.width = min(max(rawWidth, 320), 1600)
        config.height = min(max(rawHeight, 240), 1600)
        config.showsCursor = false
        config.scalesToFit = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            throw ReaderError.captureFailed("captureImage failed: \(error.localizedDescription)")
        }
    }

    /// Run Vision OCR on a CGImage. Hops off the main actor via `Task.detached`
    /// because Vision's completion handler fires on a background thread; if we
    /// resumed a continuation from a `@MainActor`-isolated context there, the
    /// Swift 6 runtime trips `dispatch_assert_queue_fail` and we crash.
    /// The static `nonisolated` worker has zero captured isolation, so the
    /// callback path is clean.
    private func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try ScreenContextReader.recognizeTextSync(in: image)
        }.value
    }

    nonisolated private static func recognizeTextSync(in image: CGImage) throws -> String {
        // `VNImageRequestHandler.perform([_:])` runs synchronously and invokes
        // the completion handler before returning, so we don't need a
        // semaphore or continuation — a plain Result is enough.
        var outcome: Result<String, Error> = .success("")
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                outcome = .failure(ReaderError.ocrFailed(error.localizedDescription))
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            outcome = .success(text)
        }
        // Fast path — we don't need pixel-perfect transcription; we just want
        // enough terms to bias the matcher. Accurate would add 100ms+ on a big
        // window for no measurable gain in term recall.
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ReaderError.ocrFailed(error.localizedDescription)
        }
        return try outcome.get()
    }

    // MARK: - Permission helpers

    /// Whether the user has already granted Screen Recording to us. Used by
    /// the settings UI to show a "Permission needed" hint.
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Trigger the system prompt. Returns immediately; the user grants
    /// asynchronously in System Settings.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
