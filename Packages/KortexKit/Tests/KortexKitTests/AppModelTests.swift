import KortexFinance
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

    /// The sample's bank account, paying rent due today.
    private func storeWithRent() throws -> (PreviewFinanceStore, rent: String, bank: String) {
        let store = PreviewFinanceStore.sample()
        let bank = try #require(store.data.moneyAccounts.first?.uid)
        store.apply(RecurringRules.save(nil, RecurringDraft(name: "Rent", kind: .fixed, amountMinor: 2_500_000, frequency: .monthly,
                                                            nextDueOn: .today(), accountUid: bank), in: store.data))
        return (store, try #require(store.data.recurring.values.first?.uid), bank)
    }

    @Test func markPaidRecordsThePayment() throws {
        let (store, rent, _) = try storeWithRent()
        let model = AppModel()
        let due = try #require(store.data.recurring[rent]?.nextDueOn)
        model.markPaid(rent, dueOn: due, finance: store)
        #expect(store.data.transactions[FinanceIds.recurringOccurrence(rent, dueOn: due)] != nil)
        #expect(model.sheet == nil && model.refusal == nil)
    }

    @Test func markPaidFromADeletedAccountOpensMarkAsPaid() throws {
        let (store, rent, bank) = try storeWithRent()
        store.apply(AccountRules.delete(bank, in: store.data))
        let model = AppModel()
        let due = try #require(store.data.recurring[rent]?.nextDueOn)
        model.markPaid(rent, dueOn: due, finance: store)
        #expect(model.sheet == .markPaid(recurringUid: rent, dueOn: due))
        #expect(store.data.recurring[rent]?.nextDueOn == due)
    }

    @Test func refusedQuickActionIsShown() {
        let store = PreviewFinanceStore.sample()
        let model = AppModel()
        #expect(!model.apply(RecurringRules.skip("gone", dueOn: .today(), in: store.data), to: store, failing: "Couldn't skip this payment"))
        #expect(model.refusal == Refusal(title: "Couldn't skip this payment", message: FinanceError.notFound.message))
    }
}
