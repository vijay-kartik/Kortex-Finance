import Foundation
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

    @Test func presentShowsASheetWhenNoneIsShowing() {
        let model = AppModel()
        model.present(.newEntry(.income))
        #expect(model.sheet == .newEntry(.income))
    }

    @Test func presentLeavesAnOpenSheetInPlace() {
        let model = AppModel()
        model.sheet = .statement(URL(fileURLWithPath: "/tmp/statement.pdf"), into: nil)
        model.present(.newEntry(.expense))
        #expect(model.sheet == .statement(URL(fileURLWithPath: "/tmp/statement.pdf"), into: nil))
    }

    @Test func chooseDoesNothingOverAnOpenSheet() {
        let model = AppModel()
        model.sheet = .newEntry(.expense)
        // Both return before running the open panel, so this doesn't block.
        model.chooseReceipt()
        model.chooseStatement()
        #expect(model.sheet == .newEntry(.expense))
    }

    @Test func dismissWithNothingShowingStaysClosed() {
        let model = AppModel()
        model.dismiss(.recurring(nil))
        #expect(model.sheet == nil)
    }
}
