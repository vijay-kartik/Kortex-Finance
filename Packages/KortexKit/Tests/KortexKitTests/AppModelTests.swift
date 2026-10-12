import Testing
@testable import KortexKit

@MainActor
struct AppModelTests {
    @Test func dismissClosesTheSheetItBelongsTo() {
        let model = AppModel()
        model.sheet = .account(nil, .bank)
        model.dismiss(.account(nil, .bank))
        #expect(model.sheet == nil)
    }

    @Test func lateDismissLeavesTheNextSheetOpen() {
        let model = AppModel()
        model.sheet = .account(nil, .creditCard)
        model.sheet = .newEntry(.expense)
        model.dismiss(.account(nil, .creditCard))
        #expect(model.sheet == .newEntry(.expense))
    }

    @Test func dismissWithNothingShowingStaysClosed() {
        let model = AppModel()
        model.dismiss(.recurring(nil))
        #expect(model.sheet == nil)
    }
}
