import SwiftUI
import Testing
@testable import KortexFinance
@testable import KortexKit

struct DestinationTests {
    @Test func sidebarGroupsCoverEveryDestinationOnce() {
        let grouped = Destination.overview + Destination.plan
        #expect(Set(grouped) == Set(Destination.allCases))
        #expect(grouped.count == Destination.allCases.count)
    }

    @Test func shortcutsAreUnique() {
        let keys = Destination.allCases.compactMap { $0.shortcut?.character }
        #expect(Set(keys).count == keys.count)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d)! }

    private func account(_ uid: String, _ kind: AccountKind, archived: Bool = false) -> Account {
        Account(uid: uid, kind: kind, name: uid, institution: nil, last4: nil, hasSecret: false, bankType: nil, ifsc: nil,
                linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                dueDay: nil, colorToken: nil, archived: archived, createdAtMillis: 0, updatedAtMillis: 0)
    }

    private func monthly(_ uid: String, anchor: Int, next: LocalDay) -> Recurring {
        Recurring(uid: uid, name: uid, kind: .subscription, amountMinor: 64_900, currency: "INR", frequency: .monthly, interval: 1,
                  anchorDay: anchor, nextDueOn: next, accountUid: "bank", categoryUid: nil, remindDaysBefore: -1,
                  autoMarkPaid: false, paused: false, createdAtMillis: 0, updatedAtMillis: 0)
    }

    @Test func sidebarCountsFollowEachScreen() {
        let today = day(2026, 9, 29)
        var data = FinanceData()
        data.apply([account("bank", .bank), account("cash", .cash), account("old", .wallet, archived: true), account("card", .creditCard)]
            .map { RemoteRow.live($0) })
        data.recurring["netflix"] = monthly("netflix", anchor: 3, next: day(2026, 10, 3))
        data.recurring["later"] = monthly("later", anchor: 3, next: day(2026, 12, 3))

        #expect(Destination.accounts.count(in: data, today: today) == 2)
        #expect(Destination.cards.count(in: data, today: today) == 1)
        #expect(Destination.pending.count(in: data, today: today) == 1)
        #expect(Destination.recurring.count(in: data, today: today) == 2)
        #expect(Destination.categories.count(in: data, today: today) == data.categories.count)
        for destination in [Destination.dashboard, .expenses, .reports] {
            #expect(destination.count(in: data, today: today) == nil)
        }
    }

    @Test func pendingHasNoCountWhenNothingIsDue() {
        var data = FinanceData()
        data.recurring["later"] = monthly("later", anchor: 3, next: day(2026, 12, 3))
        #expect(Destination.pending.count(in: data, today: day(2026, 9, 29)) == nil)
        #expect(Destination.accounts.count(in: data, today: day(2026, 9, 29)) == 0)
    }
}
