import XCTest
@testable import Gilt

final class ContentClassifierTests: XCTestCase {

    // MARK: - Code Detection: Language Identification

    func testDetectsSwiftCode() {
        let swift = """
        struct ContentView: View {
            @State private var count = 0
            var body: some View {
                Text("Hello \\(count)")
            }
        }
        """
        let result = ContentClassifier.detectCode(text: swift)
        XCTAssertTrue(result.isCode, "Should detect Swift code")
        XCTAssertEqual(result.language, .swift, "Language should be Swift")
    }

    func testDetectsPythonCode() {
        let python = """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n - 1) + fibonacci(n - 2)

        for i in range(10):
            print(fibonacci(i))
        """
        let result = ContentClassifier.detectCode(text: python)
        XCTAssertTrue(result.isCode, "Should detect Python code")
        XCTAssertEqual(result.language, .python, "Language should be Python")
    }

    func testDetectsJavaScriptCode() {
        let js = """
        const fetchData = async () => {
            const response = await fetch('/api/data');
            const json = await response.json();
            console.log(json);
            return json;
        };
        export default fetchData;
        """
        let result = ContentClassifier.detectCode(text: js)
        XCTAssertTrue(result.isCode, "Should detect JavaScript code")
        XCTAssertEqual(result.language, .javascript, "Language should be JavaScript")
    }

    func testDetectsSQLCode() {
        let sql = """
        SELECT users.name, orders.total
        FROM users
        JOIN orders ON users.id = orders.user_id
        WHERE orders.total > 100
        """
        let result = ContentClassifier.detectCode(text: sql)
        XCTAssertTrue(result.isCode, "Should detect SQL code")
        XCTAssertEqual(result.language, .sql, "Language should be SQL")
    }

    func testDetectsHTMLCode() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Test</title></head>
        <body>
            <div class="container">
                <span>Hello</span>
            </div>
        </body>
        </html>
        """
        let result = ContentClassifier.detectCode(text: html)
        XCTAssertTrue(result.isCode, "Should detect HTML code")
        XCTAssertEqual(result.language, .html, "Language should be HTML")
    }

    func testDetectsRustCode() {
        let rust = """
        pub fn calculate(x: i32) -> i32 {
            let mut result = 0;
            for i in 0..x {
                result += i;
            }
            result
        }
        """
        let result = ContentClassifier.detectCode(text: rust)
        XCTAssertTrue(result.isCode, "Should detect Rust code")
        XCTAssertEqual(result.language, .rust, "Language should be Rust")
    }

    func testDetectsShellScript() {
        let shell = """
        #!/bin/bash
        echo "Starting deploy"
        if [ -f config.yml ]; then
            echo "Config found"
        fi
        """
        let result = ContentClassifier.detectCode(text: shell)
        XCTAssertTrue(result.isCode, "Should detect Shell code")
        XCTAssertEqual(result.language, .shell, "Language should be Shell")
    }

    // MARK: - Code Detection: Rejection Cases

    func testRejectsPlainEnglishSentence() {
        let sentence = "The quick brown fox jumps over the lazy dog."
        let result = ContentClassifier.detectCode(text: sentence)
        XCTAssertFalse(result.isCode, "Plain English should not be detected as code")
    }

    func testRejectsShortText() {
        let short = "hello"
        let result = ContentClassifier.detectCode(text: short)
        XCTAssertFalse(result.isCode, "Text under 10 chars should not be detected as code")
    }

    func testRejectsQuestionSentence() {
        let question = "How do I install Python on my Mac?"
        let result = ContentClassifier.detectCode(text: question)
        XCTAssertFalse(result.isCode, "Question sentences should not be detected as code")
    }

    func testRejectsTranscriptStyleTextThatMentionsLetAndSomeView() {
        let transcript = """
        let me show you the layout in the next section
        we return to the homepage after the intro
        some view of the dashboard fades in here
        """
        let result = ContentClassifier.detectCode(text: transcript)
        XCTAssertFalse(result.isCode, "Narration with URL- or Swift-like words should stay plain text")
    }

    func testRejectsURLHeavyMultilineTextAsCode() {
        let links = """
        https://x.com/feross/status/2038867034419982449?s=20
        https://github.com/instructkr/claude-code
        https://youtu.be/TEAlD4p1yqI
        """
        let result = ContentClassifier.detectCode(text: links)
        XCTAssertFalse(result.isCode, "Lists of links should not get extra code points from // in URLs")
    }

    // MARK: - Code Detection: JSON (structural, not language-specific)

    func testDetectsJSONStructureAsCode() {
        let json = """
        {
            "name": "Gilt",
            "version": "1.0.0",
            "description": "A clipboard manager"
        }
        """
        let result = ContentClassifier.detectCode(text: json)
        XCTAssertTrue(result.isCode, "JSON objects should be detected as code-like structure")
        // JSON has no dedicated language — it matches structural patterns not language-specific ones
    }

    // MARK: - Code Detection: Score Threshold Boundary

    func testTextJustBelowCodeThresholdIsNotCode() {
        // Simple text with a couple code-like tokens but not enough to reach score 6
        // A single { adds 2 points, a single } adds 2 — that's 4, below threshold
        let text = "The object { has a property } here in this text"
        let result = ContentClassifier.detectCode(text: text)
        XCTAssertFalse(result.isCode, "Text with few code tokens should stay below score threshold of 6")
    }

    // MARK: - Credential Detection: Positive

    func testDetectsOpenAIKey() {
        let text = "My API key is sk-abc123def456ghi789jkl012mno345pqr"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectCredentials(text: text, range: range), "Should detect sk- prefixed API keys")
    }

    func testDetectsGitHubToken() {
        let text = "token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectCredentials(text: text, range: range), "Should detect ghp_ GitHub tokens")
    }

    func testDetectsAWSAccessKey() {
        let text = "aws_access_key_id = AKIAIOSFODNN7EXAMPLE"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectCredentials(text: text, range: range), "Should detect AKIA AWS keys")
    }

    func testDetectsSSHPrivateKey() {
        let text = "-----BEGIN RSA PRIVATE KEY-----\nMIIEow..."
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectCredentials(text: text, range: range), "Should detect SSH private key headers")
    }

    func testDetectsBearerToken() {
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectCredentials(text: text, range: range), "Should detect Bearer tokens")
    }

    func testDetectsSlackToken() {
        let text = "SLACK_TOKEN=xoxb-1234567890-abcdefghij"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectCredentials(text: text, range: range), "Should detect Slack xoxb tokens")
    }

    func testDetectsAllSupportedCredentialPatterns() {
        let cases: [(label: String, text: String)] = [
            ("OpenAI or Stripe secret key", "sk-abc123def456ghi789jkl012mno345pqr"),
            ("Public key", "pk-abc123def456ghi789jkl012mno345pqr"),
            ("GitHub personal access token", "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"),
            ("GitHub OAuth token", "gho_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"),
            ("GitHub app token", "ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"),
            ("AWS access key ID", "AKIAIOSFODNN7EXAMPLE"),
            ("Generic api key assignment", "api_key = supersecretvalue1234"),
            ("Generic token assignment", "token: abcdefghijklmnopqrstuvwx"),
            ("Password assignment", "password = hunter22!"),
            ("Private key header", "-----BEGIN RSA PRIVATE KEY-----\nMIIEow..."),
            ("Certificate header", "-----BEGIN CERTIFICATE-----\nMIIDdzCCAl+gAwIBAgIE..."),
            ("Bearer token", "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0"),
            ("Slack token", "xoxb-1234567890-abcdefghij"),
            ("SendGrid API key", "SG.abcdefghijklmnopqrstuv.ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq")
        ]

        for testCase in cases {
            let range = NSRange(testCase.text.startIndex..., in: testCase.text)
            XCTAssertTrue(
                ContentClassifier.detectCredentials(text: testCase.text, range: range),
                "Expected to detect \(testCase.label)"
            )
        }
    }

    // MARK: - Credential Detection: False Positive Resistance

    func testRejectsNormalTextAsCredential() {
        let text = "Just a regular paragraph about coding and APIs in general."
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertFalse(ContentClassifier.detectCredentials(text: text, range: range), "Normal prose should not be flagged")
    }

    func testRejectsShortSkPrefix() {
        // "sk-" followed by fewer than 20 chars should NOT match
        let text = "I use sk-short as a nickname"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertFalse(ContentClassifier.detectCredentials(text: text, range: range), "Short sk- prefix should not match")
    }

    func testRejectsTokenInProse() {
        // The word "token" in normal prose should not trigger
        let text = "The token of appreciation was lovely"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertFalse(ContentClassifier.detectCredentials(text: text, range: range), "Prose use of 'token' should not match")
    }

    // MARK: - Color Detection

    func testDetectsHexColor() {
        let text = "#FF5733"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectColor(text: text, range: range), "Should detect 6-digit hex")
    }

    func testDetectsShortHexColor() {
        let text = "#F53"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectColor(text: text, range: range), "Should detect 3-digit hex")
    }

    func testDetectsRGBColor() {
        let text = "rgb(255, 99, 71)"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectColor(text: text, range: range), "Should detect rgb()")
    }

    func testDetectsHSLColor() {
        let text = "hsl(120, 100%, 50%)"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectColor(text: text, range: range), "Should detect hsl()")
    }

    func testDetectsCSSNamedColor() {
        let text = "coral"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectColor(text: text, range: range), "Should detect CSS named color")
    }

    func testRejectsRandomWordAsColor() {
        let text = "banana"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertFalse(ContentClassifier.detectColor(text: text, range: range), "Random word should not match")
    }

    func testCSSNamedColorDoesNotMatchInLongerText() {
        // CSS named colors should only match when the entire text IS the color name
        let text = "The background is coral and the text is white"
        let range = NSRange(text.startIndex..., in: text)
        // detectColor checks: trimmed text < 30 chars AND is exact CSS name match
        // "The background is coral and the text is white" is > 30 chars, so CSS name check fails
        // But hex/rgb regex might still match "coral" — let's check the full behavior
        // Actually, "coral" is not a hex/rgb pattern, so it should only match via the CSS path
        // which requires the trimmed text to be < 30 and an exact match. This text is > 30 chars.
        XCTAssertFalse(ContentClassifier.detectColor(text: text, range: range),
                        "CSS named color should not match when embedded in a longer sentence (>30 chars)")
    }

    // MARK: - Color Detection Suppression for Long Text

    func testColorDetectionSuppressedInLongText() {
        // The classify() method skips color detection for text >= 200 chars
        // to avoid false positives in code snippets
        let longCode = String(repeating: "x", count: 200) + " #FF5733"
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Long",
            previewText: longCode,
            textValue: longCode,
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertFalse(result.contentTags.contains(.colorValue),
                        "Color detection should be suppressed for text >= 200 characters")
    }

    func testColorDetectionWorksForShortText() {
        let shortText = "#FF5733"
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Short",
            previewText: shortText,
            textValue: shortText,
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.contentTags.contains(.colorValue),
                       "Color detection should work for short text")
    }

    // MARK: - Color Extraction (exact values)

    func testExtractsHexColorExactValue() {
        let text = "The color is #FF5733 in the design"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertEqual(ContentClassifier.extractFirstColor(text: text, range: range), "#FF5733",
                        "Should extract exact hex color string")
    }

    func testExtractsRGBColorWithClosingParen() {
        let text = "Use rgb(255, 99, 71) for the button"
        let range = NSRange(text.startIndex..., in: text)
        let color = ContentClassifier.extractFirstColor(text: text, range: range)
        XCTAssertEqual(color, "rgb(255, 99, 71)", "Should extract complete rgb() including closing paren")
    }

    func testExtractsCSSNamedColorAsExactValue() {
        let text = "  coral  "
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertEqual(ContentClassifier.extractFirstColor(text: text, range: range), "coral",
                        "Should extract trimmed CSS color name")
    }

    // MARK: - Hex Color Parsing (guard-let pattern to avoid crash)

    func testParseHex6Digit() {
        guard let result = ContentClassifier.parseHexColor("#FF0000") else {
            XCTFail("Expected non-nil result for valid 6-digit hex")
            return
        }
        XCTAssertEqual(result.r, 1.0, accuracy: 0.01, "Red channel")
        XCTAssertEqual(result.g, 0.0, accuracy: 0.01, "Green channel")
        XCTAssertEqual(result.b, 0.0, accuracy: 0.01, "Blue channel")
    }

    func testParseHex3Digit() {
        guard let result = ContentClassifier.parseHexColor("#F00") else {
            XCTFail("Expected non-nil result for valid 3-digit hex")
            return
        }
        XCTAssertEqual(result.r, 1.0, accuracy: 0.01, "Red channel")
        XCTAssertEqual(result.g, 0.0, accuracy: 0.01, "Green channel")
        XCTAssertEqual(result.b, 0.0, accuracy: 0.01, "Blue channel")
    }

    func testParseHex8DigitIgnoresAlpha() {
        // #FF000080 = RR=FF, GG=00, BB=00, AA=80. Alpha is discarded.
        guard let result = ContentClassifier.parseHexColor("#FF000080") else {
            XCTFail("Expected non-nil result for valid 8-digit hex")
            return
        }
        XCTAssertEqual(result.r, 1.0, accuracy: 0.01, "Red should be 1.0")
        XCTAssertEqual(result.g, 0.0, accuracy: 0.01, "Green should be 0.0")
        XCTAssertEqual(result.b, 0.0, accuracy: 0.01, "Blue should be 0.0 (AA byte is discarded)")
    }

    func testParseHexRejectsInvalidInput() {
        XCTAssertNil(ContentClassifier.parseHexColor("not-a-color"), "Non-hex text should return nil")
        XCTAssertNil(ContentClassifier.parseHexColor("#GGGGGG"), "Invalid hex chars should return nil")
    }

    func testParseHex4DigitReturnsNil() {
        XCTAssertNil(ContentClassifier.parseHexColor("#F00A"), "4-digit hex is not a standard format")
    }

    func testParseHex5DigitReturnsNil() {
        XCTAssertNil(ContentClassifier.parseHexColor("#12345"), "5-digit hex is not a standard format")
    }

    // MARK: - Universal Color Parsing

    func testParseAnyColorHex() {
        guard let result = ContentClassifier.parseAnyColor("#00FF00") else {
            XCTFail("Expected non-nil for valid hex")
            return
        }
        XCTAssertEqual(result.r, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.g, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.b, 0.0, accuracy: 0.01)
    }

    func testParseAnyColorRGB() {
        guard let result = ContentClassifier.parseAnyColor("rgb(0, 128, 255)") else {
            XCTFail("Expected non-nil for valid rgb()")
            return
        }
        XCTAssertEqual(result.r, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.g, 128.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(result.b, 1.0, accuracy: 0.01)
    }

    func testParseAnyColorRGBA() {
        guard let result = ContentClassifier.parseAnyColor("rgba(255, 0, 0, 0.5)") else {
            XCTFail("Expected non-nil for valid rgba()")
            return
        }
        XCTAssertEqual(result.r, 1.0, accuracy: 0.01, "Red channel from rgba")
        XCTAssertEqual(result.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.b, 0.0, accuracy: 0.01)
    }

    func testParseAnyColorHSLPureGreen() {
        // hsl(120, 100%, 50%) = pure green — independently verifiable via color theory
        guard let result = ContentClassifier.parseAnyColor("hsl(120, 100%, 50%)") else {
            XCTFail("Expected non-nil for valid hsl()")
            return
        }
        XCTAssertEqual(result.r, 0.0, accuracy: 0.02)
        XCTAssertEqual(result.g, 1.0, accuracy: 0.02)
        XCTAssertEqual(result.b, 0.0, accuracy: 0.02)
    }

    func testParseAnyColorHSLGrayHasZeroSaturation() {
        // hsl(0, 0%, 50%) = gray (equal RGB) — independent of implementation
        guard let result = ContentClassifier.parseAnyColor("hsl(0, 0%, 50%)") else {
            XCTFail("Expected non-nil for gray hsl")
            return
        }
        XCTAssertEqual(result.r, 0.5, accuracy: 0.02, "Gray should have equal RGB channels")
        XCTAssertEqual(result.g, 0.5, accuracy: 0.02)
        XCTAssertEqual(result.b, 0.5, accuracy: 0.02)
    }

    func testParseAnyColorCSSNamedRed() {
        guard let result = ContentClassifier.parseAnyColor("red") else {
            XCTFail("Expected non-nil for CSS named color 'red'")
            return
        }
        // Red is universally #FF0000 = (1,0,0)
        XCTAssertEqual(result.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.b, 0.0, accuracy: 0.01)
    }

    func testParseAnyColorReturnsNilForGarbage() {
        XCTAssertNil(ContentClassifier.parseAnyColor("not a color at all"))
    }

    // MARK: - Email Detection (exact values)

    func testDetectsSingleEmail() {
        let text = "Contact me at john@example.com for details"
        let range = NSRange(text.startIndex..., in: text)
        let emails = ContentClassifier.detectEmails(text: text, range: range)
        XCTAssertEqual(emails, ["john@example.com"], "Should extract exact email address")
    }

    func testDetectsMultipleEmailsWithCorrectValues() {
        let text = "Email alice@test.org or bob@company.co.uk"
        let range = NSRange(text.startIndex..., in: text)
        let emails = ContentClassifier.detectEmails(text: text, range: range)
        XCTAssertEqual(emails.count, 2, "Should find exactly 2 emails")
        XCTAssertTrue(emails.contains("alice@test.org"), "Should contain alice's email")
        XCTAssertTrue(emails.contains("bob@company.co.uk"), "Should contain bob's email")
    }

    func testNoEmailsInPlainText() {
        let text = "There are no email addresses here at all"
        let range = NSRange(text.startIndex..., in: text)
        let emails = ContentClassifier.detectEmails(text: text, range: range)
        XCTAssertTrue(emails.isEmpty, "Plain text should yield no emails")
    }

    // MARK: - Phone Detection (exact values)

    func testDetectsUSPhoneExactValue() {
        let text = "Call us at (555) 123-4567"
        let range = NSRange(text.startIndex..., in: text)
        let phones = ContentClassifier.detectPhones(text: text, range: range)
        XCTAssertEqual(phones.count, 1, "Should detect one phone number")
        XCTAssertEqual(phones.first, "(555) 123-4567", "Should extract full formatted number")
    }

    func testDetectsInternationalPhoneExactValue() {
        let text = "International: +44 7700 900000"
        let range = NSRange(text.startIndex..., in: text)
        let phones = ContentClassifier.detectPhones(text: text, range: range)
        XCTAssertEqual(phones.count, 1, "Should detect one international number")
        XCTAssertTrue(phones.first?.hasPrefix("+44") ?? false, "Should start with country code")
    }

    // MARK: - URL Detection (exact values)

    func testDetectsHTTPSUrlExactValue() {
        let text = "Visit https://example.com/page for more info"
        let range = NSRange(text.startIndex..., in: text)
        let urls = ContentClassifier.detectURLs(text: text, range: range)
        XCTAssertEqual(urls, ["https://example.com/page"], "Should extract exact URL")
    }

    func testDetectsHTTPUrlExactValue() {
        let text = "Old link: http://legacy.site.com/api"
        let range = NSRange(text.startIndex..., in: text)
        let urls = ContentClassifier.detectURLs(text: text, range: range)
        XCTAssertEqual(urls, ["http://legacy.site.com/api"], "Should extract exact HTTP URL")
    }

    func testNoUrlsInPlainText() {
        let text = "No links here, just plain text"
        let range = NSRange(text.startIndex..., in: text)
        let urls = ContentClassifier.detectURLs(text: text, range: range)
        XCTAssertTrue(urls.isEmpty, "Plain text should yield no URLs")
    }

    // MARK: - URL Detection Scoping

    func testURLDetectionOnlyAppliesToTextClips() {
        // A link-type clip with an embedded URL in its text should NOT double-add to .links
        let clip = ClipItemModel(
            typeRaw: ClipType.link.rawValue,
            title: "Link",
            previewText: "Check https://example.com out",
            textValue: "Check https://example.com out",
            urlValue: "https://example.com",
            sourceAppName: "Safari"
        )
        let result = ContentClassifier.classify(item: clip)
        // Should only have one openURL action (from the link clip path), not two
        let urlActions = result.suggestedActions.filter { $0.type == .openURL }
        XCTAssertEqual(urlActions.count, 1, "Link clips should not double-add URL actions from text detection")
    }

    // MARK: - Address Detection

    func testDetectsStreetAddress() {
        let text = "Our office is at 123 Main Street, Suite 400"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectAddress(text: text, range: range), "Should detect 'Main Street'")
    }

    func testDetectsAbbreviatedAddress() {
        let text = "Ship to 456 Oak Ave"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertTrue(ContentClassifier.detectAddress(text: text, range: range), "Should detect 'Oak Ave'")
    }

    func testRejectsNonAddress() {
        let text = "I went to the store yesterday"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertFalse(ContentClassifier.detectAddress(text: text, range: range))
    }

    func testRejectsNumbersWithNonAddressWords() {
        let text = "Buy 100 Apple shares today"
        let range = NSRange(text.startIndex..., in: text)
        XCTAssertFalse(ContentClassifier.detectAddress(text: text, range: range),
                        "'100 Apple shares' should not match as address")
    }

    // MARK: - Full Classification: Categories

    func testClassifyImageClipReturnsImagesCategory() {
        let clip = ClipItemModel(
            typeRaw: ClipType.image.rawValue,
            title: "Screenshot",
            previewText: "",
            sourceAppName: "Preview"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.contains(.images), "Image clips should be in images category")
        XCTAssertFalse(result.isSensitive, "Image clips should not be sensitive by default")
        XCTAssertTrue(result.contentTags.isEmpty, "Image clips should have no content tags")
    }

    func testClassifyLinkClipReturnsLinksCategoryWithAction() {
        let clip = ClipItemModel(
            typeRaw: ClipType.link.rawValue,
            title: "Example",
            previewText: "https://example.com",
            urlValue: "https://example.com",
            sourceAppName: "Safari"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.contains(.links), "Link clips should be in links category")
        // Verify the openURL action was created
        let urlAction = result.suggestedActions.first(where: { $0.type == .openURL })
        XCTAssertNotNil(urlAction, "Link clips should have an openURL action")
        XCTAssertEqual(urlAction?.value, "https://example.com", "Action value should be the URL")
    }

    func testClassifyCredentialMarksSensitive() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Token",
            previewText: "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn",
            textValue: "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn",
            sourceAppName: "Terminal"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.isSensitive, "Credentials should be flagged as sensitive")
        XCTAssertTrue(result.matchedCategories.contains(.sensitive), "Should be in sensitive category")
        XCTAssertTrue(result.contentTags.contains(.credential), "Should have credential tag")
    }

    func testClassifyEmailAddsContactCategoryWithAction() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Email",
            previewText: "john@example.com",
            textValue: "john@example.com",
            sourceAppName: "Mail"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.contains(.contacts), "Emails should be in contacts")
        XCTAssertTrue(result.contentTags.contains(.email), "Should have email tag")
        let emailAction = result.suggestedActions.first(where: { $0.type == .email })
        XCTAssertNotNil(emailAction, "Should have email action")
        XCTAssertEqual(emailAction?.value, "john@example.com", "Action value should be the email")
    }

    func testClassifyPhoneAddsContactCategoryWithAction() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Phone",
            previewText: "(555) 123-4567",
            textValue: "(555) 123-4567",
            sourceAppName: "Contacts"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.contains(.contacts), "Phones should be in contacts")
        XCTAssertTrue(result.contentTags.contains(.phoneNumber), "Should have phone tag")
        let callAction = result.suggestedActions.first(where: { $0.type == .call })
        XCTAssertNotNil(callAction, "Should have call action")
    }

    func testClassifyAddressHasMapsAction() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Address",
            previewText: "742 Evergreen Terrace",
            textValue: "742 Evergreen Terrace",
            sourceAppName: "Notes"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.contains(.addresses), "Should be in addresses category")
        let mapsAction = result.suggestedActions.first(where: { $0.type == .openMaps })
        XCTAssertNotNil(mapsAction, "Should have openMaps action")
    }

    func testClassifyEmptyTextReturnsNothingAtAll() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Empty",
            previewText: "",
            textValue: "",
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.isEmpty, "No categories for empty text")
        XCTAssertTrue(result.contentTags.isEmpty, "No tags for empty text")
        XCTAssertFalse(result.isSensitive, "Empty text is not sensitive")
        XCTAssertNil(result.detectedLanguage, "No language for empty text")
        XCTAssertTrue(result.suggestedActions.isEmpty, "No actions for empty text")
    }

    // MARK: - Classification: Suggested Actions Limit

    func testClassifyCapsActionsAtThree() {
        // Create a clip that would trigger many categories: email + phone + address + URL
        let text = "Contact john@example.com or call (555) 123-4567 at 123 Main Street, see https://example.com"
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Multi",
            previewText: text,
            textValue: text,
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertLessThanOrEqual(result.suggestedActions.count, 3,
                                  "Suggested actions should be capped at 3")
    }

    // MARK: - Classification: Code Detection Sets Language

    func testClassifyCodeClipSetsDetectedLanguage() {
        let swift = """
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }
        let message = greet(name: "World")
        """
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Code",
            previewText: swift,
            textValue: swift,
            sourceAppName: "Xcode"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.matchedCategories.contains(.code), "Should be in code category")
        XCTAssertTrue(result.contentTags.contains(.code), "Should have code tag")
        XCTAssertEqual(result.detectedLanguage, .swift, "Should detect Swift language")
        // Verify language action was created
        let langAction = result.suggestedActions.first(where: { $0.type == .language })
        XCTAssertNotNil(langAction, "Should have language action")
        XCTAssertEqual(langAction?.label, "Swift", "Language action label should be 'Swift'")
    }

    // MARK: - suggestedActions(for:) — Reconstructs Actions from Stored Tags

    func testSuggestedActionsForEmailTag() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Stored",
            previewText: "alice@test.com",
            textValue: "alice@test.com",
            sourceAppName: "Test"
        )
        clip.contentTags = [.email]
        let actions = ContentClassifier.suggestedActions(for: clip)
        let emailAction = actions.first(where: { $0.type == .email })
        XCTAssertNotNil(emailAction, "Should produce email action from stored tag")
        XCTAssertEqual(emailAction?.value, "alice@test.com", "Should extract email from text")
    }

    func testSuggestedActionsForPhoneTag() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Stored",
            previewText: "(555) 999-0000",
            textValue: "(555) 999-0000",
            sourceAppName: "Test"
        )
        clip.contentTags = [.phoneNumber]
        let actions = ContentClassifier.suggestedActions(for: clip)
        let callAction = actions.first(where: { $0.type == .call })
        XCTAssertNotNil(callAction, "Should produce call action from stored tag")
    }

    func testSuggestedActionsForColorTag() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Color",
            previewText: "#FF5733",
            textValue: "#FF5733",
            sourceAppName: "Test"
        )
        clip.contentTags = [.colorValue]
        let actions = ContentClassifier.suggestedActions(for: clip)
        let swatchAction = actions.first(where: { $0.type == .colorSwatch })
        XCTAssertNotNil(swatchAction, "Should produce colorSwatch action from stored tag")
        XCTAssertEqual(swatchAction?.value, "#FF5733", "Swatch value should be the color")
    }

    func testSuggestedActionsForLinkClip() {
        let clip = ClipItemModel(
            typeRaw: ClipType.link.rawValue,
            title: "Link",
            previewText: "example.com",
            urlValue: "https://example.com",
            sourceAppName: "Safari"
        )
        let actions = ContentClassifier.suggestedActions(for: clip)
        let urlAction = actions.first(where: { $0.type == .openURL })
        XCTAssertNotNil(urlAction, "Link clips should have openURL action")
        XCTAssertEqual(urlAction?.value, "https://example.com")
    }

    func testSuggestedActionsForDetectedLanguage() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Code",
            previewText: "func test()",
            textValue: "func test()",
            sourceAppName: "Test"
        )
        clip.detectedLanguage = .python
        let actions = ContentClassifier.suggestedActions(for: clip)
        let langAction = actions.first(where: { $0.type == .language })
        XCTAssertNotNil(langAction, "Should produce language action from stored language")
        XCTAssertEqual(langAction?.label, "Python")
    }

    // MARK: - Detector Input Cap (large pastes)

    func testHugeFillerClipClassifiesWithoutFalseSignals() {
        // ~108k chars of plain filler, classify must return quickly and match nothing.
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 4_000)
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Huge",
            previewText: String(filler.prefix(100)),
            textValue: filler,
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.contentTags.isEmpty, "Filler-only text should produce no content tags")
        XCTAssertFalse(result.matchedCategories.contains(.links), "No URLs in filler")
        XCTAssertFalse(result.isSensitive, "Filler should not be sensitive")
    }

    func testSignalsNearStartOfHugeClipStillDetected() {
        let text = "Contact john@example.com, call (555) 123-4567, see https://example.com/page\n"
            + String(repeating: "lorem ipsum dolor sit amet ", count: 4_000)
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Huge with signals",
            previewText: String(text.prefix(100)),
            textValue: text,
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertTrue(result.contentTags.contains(.email), "Email near the start must survive the cap")
        XCTAssertTrue(result.contentTags.contains(.phoneNumber), "Phone near the start must survive the cap")
        XCTAssertTrue(result.matchedCategories.contains(.links), "URL near the start must survive the cap")
    }

    func testSignalBeyondDetectorCapIsNotDetected() {
        // Documents the deliberate tradeoff: content past 20k chars is not scanned.
        let text = String(repeating: "a ", count: 15_000) + "john@example.com"
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Signal past cap",
            previewText: String(text.prefix(100)),
            textValue: text,
            sourceAppName: "Test"
        )
        let result = ContentClassifier.classify(item: clip)
        XCTAssertFalse(result.contentTags.contains(.email),
                       "Email placed beyond the 20k detector cap should not be detected")
    }

    func testSuggestedActionsCappedAtThree() {
        let clip = ClipItemModel(
            typeRaw: ClipType.text.rawValue,
            title: "Everything",
            previewText: "alice@test.com (555) 123-4567 #FF0000 123 Main Street",
            textValue: "alice@test.com (555) 123-4567 #FF0000 123 Main Street",
            sourceAppName: "Test"
        )
        clip.contentTags = [.email, .phoneNumber, .colorValue, .address]
        clip.detectedLanguage = .swift
        let actions = ContentClassifier.suggestedActions(for: clip)
        XCTAssertLessThanOrEqual(actions.count, 3, "Actions should be capped at 3")
    }
}
