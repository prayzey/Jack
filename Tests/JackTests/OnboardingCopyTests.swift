import Foundation
import XCTest
@testable import Gilt

final class OnboardingCopyTests: XCTestCase {
    func testTabTitlesLocalizeToGerman() {
        let titles = OnboardingCopy.tabTitles(locale: Locale(identifier: "de"))

        XCTAssertEqual(titles, ["Willkommen", "So geht's", "Berechtigungen", "Setup", "Stil", "Bereit"])
    }

    func testPrimaryActionUsesAccessibilityVariantWhenNeeded() {
        let title = OnboardingCopy.primaryActionTitle(
            isLastStep: true,
            accessibilityGranted: false,
            locale: Locale(identifier: "es")
        )

        XCTAssertEqual(title, "Concede Accesibilidad para empezar")
    }

    func testHowItWorksCardsStayOrderedAndLocalized() {
        let cards = OnboardingCopy.howItWorksCards(locale: Locale(identifier: "en"))

        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards[0], .init(
            number: "01",
            title: "Intelligent Capture",
            description: "Jack silently preserves everything you copy, from code to images."
        ))
        XCTAssertEqual(cards[2].title, "Instant Action")
    }

    func testModeDescriptionLocalizesToSpanish() {
        let description = OnboardingCopy.modeDescription(
            for: .radial,
            locale: Locale(identifier: "es")
        )

        XCTAssertEqual(description, "Anillo de acceso rapido en la posicion del cursor - la forma mas veloz de encontrar y pegar.")
    }
}
