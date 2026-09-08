import XCTest
@testable import Gilt

@MainActor
final class LiveDictationPolisherTests: XCTestCase {

    // MARK: - Boundary detection

    func testShortUnpunctuatedTextHasNoPolishablePrefix() {
        XCTAssertNil(LiveDictationPolisher.polishablePrefix(
            in: "i need to buy tomatoes",
            lastPrefixWordCount: 0
        ))
    }

    func testOnlyEngineConfirmedTextEntersBoundaryDetection() {
        // The caller excludes tentative words, including their punctuation.
        XCTAssertNil(LiveDictationPolisher.polishablePrefix(
            in: "i need to",
            lastPrefixWordCount: 0
        ))
    }

    func testCompletedSentenceInStableRegionIsPolishable() {
        XCTAssertEqual(
            LiveDictationPolisher.polishablePrefix(
                in: "i need to buy tomatoes. oops i mean",
                lastPrefixWordCount: 0
            ),
            "i need to buy tomatoes."
        )
    }

    func testTinyFragmentSentenceIsSkipped() {
        XCTAssertNil(LiveDictationPolisher.polishablePrefix(
            in: "ok. so anyway the",
            lastPrefixWordCount: 0
        ))
    }

    func testUsersSessionShapeReachesTheCorrection() {
        // Replays the user's 2026-07-07 session: ~20 words total, terminator
        // boundary at word 8, correction mid-stream. With the old 12-word
        // fallback the session ended before any pass saw the correction; the
        // 6-word cadence must include it.
        let raw = "I need to buy some tomatoes for tonight. Actually no I meant onions and also some bread and butter"
        let prefix = LiveDictationPolisher.polishablePrefix(
            in: raw,
            lastPrefixWordCount: LiveCaptionComposer.wordCount("I need to buy some tomatoes for tonight.")
        )
        XCTAssertNotNil(prefix, "no pass fired after the first sentence")
        XCTAssertTrue(prefix!.contains("onions"), "correction not inside the pass: \(prefix!)")
    }

    func testCorrectionMarkerBeatsWordCountBoundary() {
        // Only four new stable words — under the 6-word fallback — but the
        // correction marker must force a pass anyway.
        let raw = "I need to buy some tomatoes for tonight. Actually no I meant onions okay"
        let prefix = LiveDictationPolisher.polishablePrefix(in: raw, lastPrefixWordCount: 8)
        XCTAssertNotNil(prefix, "marker did not trigger a pass")
        XCTAssertTrue(prefix!.hasSuffix("okay"), "unexpected boundary: \(prefix!)")
    }

    func testUnpunctuatedSpeechFallsBackToWordCountBoundary() {
        // The unified Parakeet stream emits little punctuation mid-stream —
        // exactly the case the user hit — so the whole stable region becomes
        // polishable once it outgrows the fallback threshold.
        let raw = "i need to go and buy some food for my friend so we should buy tomatoes plus more words"
        let prefix = LiveDictationPolisher.polishablePrefix(in: raw, lastPrefixWordCount: 0)
        XCTAssertEqual(
            prefix,
            raw
        )
        // No new boundary until another 12 stable words accumulate.
        XCTAssertNil(LiveDictationPolisher.polishablePrefix(
            in: raw + " a b c",
            lastPrefixWordCount: LiveCaptionComposer.wordCount(prefix ?? "")
        ))
    }

    func testStaleTerminatorDoesNotStallFallbackPasses() {
        // One early period, then a long unpunctuated ramble: the terminator
        // boundary stops moving, so the word-count fallback must take over.
        let raw = "okay so first thing. now a much longer unpunctuated ramble that keeps going and going with plenty of words to cross the fallback threshold easily"
        let first = LiveDictationPolisher.polishablePrefix(in: raw, lastPrefixWordCount: 0)
        XCTAssertEqual(first, "okay so first thing.")
        let second = LiveDictationPolisher.polishablePrefix(
            in: raw,
            lastPrefixWordCount: LiveCaptionComposer.wordCount(first ?? "")
        )
        XCTAssertNotNil(second)
        // Every word here is confirmed by the engine, including the tail.
        XCTAssertTrue(second!.hasSuffix("easily"))
    }

    // MARK: - Ingest → polish → compose

    func testIngestPolishesPrefixAndComposeSplicesRawSuffix() async {
        let polisher = LiveDictationPolisher(
            prepare: { $0 },
            polishChunk: { $0.replacingOccurrences(of: "tomatoes", with: "onions") }
        )
        let raw = "i need to buy tomatoes. no wait i mean onions for sure"
        polisher.ingest(committedRaw: raw)
        await polisher.finishSession()

        XCTAssertEqual(polisher.polishedRawPrefix, "i need to buy tomatoes.")
        XCTAssertEqual(polisher.polishedText, "i need to buy onions.")

        let state = polisher.compose(cumulativeRaw: raw, committedRaw: "i need to buy tomatoes.")
        XCTAssertNotNil(state)
        XCTAssertTrue(state!.text.hasPrefix("i need to buy onions."))
        XCTAssertTrue(state!.text.contains("mean onions for sure"))
        // The polished prefix must never render as provisional (blurred).
        XCTAssertGreaterThanOrEqual(state!.stableWordCount, 5)
    }

    func testComposeSurvivesIrregularAsrSpacing() async {
        // The ASR helper joins committed + tentative segments with raw token
        // spacing — double spaces must not break the prefix splice (this hid
        // every live heal in the first real-world test).
        let polisher = LiveDictationPolisher(
            prepare: { $0 },
            polishChunk: { $0.replacingOccurrences(of: "tomatoes", with: "onions") }
        )
        polisher.ingest(committedRaw: "i need to buy tomatoes. oops i  mean")
        await polisher.finishSession()

        let state = polisher.compose(cumulativeRaw: "i need to  buy tomatoes. oops i  mean onions now", committedRaw: "i need to buy tomatoes.")
        XCTAssertNotNil(state)
        XCTAssertTrue(state!.text.hasPrefix("i need to buy onions."))
    }

    func testComposeFallsBackWhenRawNoLongerStartsWithPolishedPrefix() async {
        let polisher = LiveDictationPolisher(
            prepare: { $0 },
            polishChunk: { $0 }
        )
        polisher.ingest(committedRaw: "i need to buy tomatoes. oops i mean")
        await polisher.finishSession()

        XCTAssertNil(polisher.compose(cumulativeRaw: "completely different transcript now", committedRaw: "completely different"))
    }

    func testFinalResultRequiresExactInputMatch() async {
        let polisher = LiveDictationPolisher(
            prepare: { $0 },
            polishChunk: { $0.uppercased() }
        )
        polisher.ingest(committedRaw: "i need to buy tomatoes. oops i mean")
        await polisher.finishSession()

        XCTAssertEqual(
            polisher.finalResult(matching: "i need to buy tomatoes."),
            "I NEED TO BUY TOMATOES."
        )
        XCTAssertNil(polisher.finalResult(matching: "i need to buy tomatoes. oops i mean onions."))
    }

    func testFailedPolishIsNotReusedButSuccessfulUnchangedTextIs() async {
        let raw = "Please send the proposal."
        let failed = LiveDictationPolisher(prepare: { $0 }, polishChunk: { _ in nil })
        failed.ingest(committedRaw: raw)
        await failed.finishSession()
        XCTAssertNil(failed.finalResult(matching: raw))
        XCTAssertNil(failed.compose(cumulativeRaw: raw, committedRaw: raw))

        let unchanged = LiveDictationPolisher(prepare: { $0 }, polishChunk: { $0 })
        unchanged.ingest(committedRaw: raw)
        await unchanged.finishSession()
        XCTAssertEqual(unchanged.finalResult(matching: raw), raw)
    }

    func testFinishingDropsQueuedAndLatePasses() async {
        var calls = 0
        let polisher = LiveDictationPolisher(prepare: { $0 }, polishChunk: { input in
            calls += 1
            return input
        })
        polisher.ingest(committedRaw: "Please send the proposal.")
        polisher.ingest(committedRaw: "Please send the proposal. Include the final schedule.")
        await polisher.finishSession()
        polisher.ingest(committedRaw: "Please send the proposal. Include the final schedule. Thank you very much.")
        await polisher.finishSession()
        XCTAssertEqual(calls, 1, "Final speech-recognition chunks must not start a second live pass.")
    }

    func testNewBoundarySupersedesWhilePassRuns() async {
        var polishCount = 0
        let polisher = LiveDictationPolisher(
            prepare: { $0 },
            polishChunk: { input in
                polishCount += 1
                try? await Task.sleep(nanoseconds: 20_000_000)
                return input
            }
        )
        // First boundary starts a pass; the next two land while it runs and
        // collapse into a single follow-up pass (drop-intermediate).
        polisher.ingest(committedRaw: "first sentence done here. second one is")
        polisher.ingest(committedRaw: "first sentence done here. second one is now finished. and more words")
        polisher.ingest(committedRaw: "first sentence done here. second one is now finished. third also complete. trailing tentative words")
        // finishSession would drop the queued pass (that's its job at session
        // end), so poll until the drop-intermediate chain settles instead.
        for _ in 0..<200 where !polisher.polishedRawPrefix.contains("third") {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(polishCount, 2)
        XCTAssertEqual(
            polisher.polishedRawPrefix,
            "first sentence done here. second one is now finished. third also complete."
        )
    }
}
