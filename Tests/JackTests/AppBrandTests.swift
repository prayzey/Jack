import Testing
@testable import Gilt

struct AppBrandTests {
    @Test
    func feedbackLinksUseTheOwnedWebsite() {
        #expect(AppBrand.feedbackURL.absoluteString == "https://gilt.novor.dev/feedback")
        #expect(AppBrand.bugReportURL.absoluteString == "https://gilt.novor.dev/feedback?type=bug")
        #expect(AppBrand.featureRequestURL.absoluteString == "https://gilt.novor.dev/feedback?type=feature")
    }
}
