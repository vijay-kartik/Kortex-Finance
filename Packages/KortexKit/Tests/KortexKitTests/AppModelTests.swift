import Foundation
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

    @Test func recurringEngineRunsOnceADayForEachUserOnLiveData() throws {
        let finance = PreviewFinanceStore.sample()
        let bank = try #require(finance.data.moneyAccounts.first?.uid)
        let clock = FinanceClock(nowMillis: 1_790_674_200_000, zone: TimeZone(identifier: "Asia/Kolkata")!)
        finance.apply(RecurringRules.save(nil, RecurringDraft(name: "Rent", kind: .fixed, amountMinor: 2_500_000, frequency: .monthly,
                                                             nextDueOn: LocalDay(year: 2026, month: 9, day: 1)!, accountUid: bank,
                                                             autoMarkPaid: true), in: finance.data, clock: clock))
        let model = AppModel()
        let rentPaid = { finance.data.transactions.values.filter { $0.source == .recurring }.count }

        finance.status = .offline
        model.runRecurringEngine(on: finance, userUid: "me", clock: clock)
        #expect(rentPaid() == 0, "waits for the server's data")

        finance.status = .live
        model.runRecurringEngine(on: finance, userUid: "me", clock: clock)
        #expect(rentPaid() == 1)

        finance.apply(RecurringRules.save(nil, RecurringDraft(name: "Gym", kind: .subscription, amountMinor: 150_000, frequency: .monthly,
                                                             nextDueOn: clock.today, accountUid: bank, autoMarkPaid: true),
                                          in: finance.data, clock: clock))
        model.runRecurringEngine(on: finance, userUid: "me", clock: clock)
        #expect(rentPaid() == 1, "once a day")

        var tomorrow = clock
        tomorrow.nowMillis += 86_400_000
        model.runRecurringEngine(on: finance, userUid: "me", clock: tomorrow)
        #expect(rentPaid() == 2)

        let changes = finance.changes.count
        model.runRecurringEngine(on: finance, userUid: "someone else", clock: tomorrow)
        #expect(finance.changes.count == changes, "nothing more is due, so nothing is written")
    }

    @Test func dismissWithNothingShowingStaysClosed() {
        let model = AppModel()
        model.dismiss(.recurring(nil))
        #expect(model.sheet == nil)
    }
}
