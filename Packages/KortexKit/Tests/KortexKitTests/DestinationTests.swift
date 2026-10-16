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

    private func statement(_ uid: String, card: String, on: LocalDay, due: LocalDay, total: Int64, min: Int64) -> CardStatement {
        CardStatement(uid: uid, cardUid: card, periodStart: on.adding(days: -30), statementOn: on, dueOn: due, totalDueMinor: total,
                      minDueMinor: min, source: .auto, createdAtMillis: 0, updatedAtMillis: 0)
    }

    private func payment(_ uid: String, _ type: TransactionType, _ amount: Int64, on: LocalDay, account: String,
                         recurring: String? = nil, dueOn: LocalDay? = nil, statement: String? = nil) -> KortexFinance.Transaction {
        Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: on,
                    accountUid: account, toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil,
                    source: .manual, sourceRef: nil, recurringUid: recurring, dueOn: dueOn, statementUid: statement,
                    receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
    }

    /// The badge reads `FinanceData.payments`; it must agree with a full scan of the transactions.
    @Test func pendingCountMatchesTheFullSummary() {
        let today = day(2026, 9, 29)
        var data = FinanceData()
        data.apply([account("bank", .bank), account("gold", .creditCard), account("silver", .creditCard), account("plat", .creditCard)]
            .map { RemoteRow.live($0) })
        for s in [statement("gold-aug", card: "gold", on: day(2026, 8, 25), due: day(2026, 9, 14), total: 90_000, min: 9_000),
                  statement("gold-sep", card: "gold", on: day(2026, 9, 25), due: day(2026, 10, 14), total: 120_000, min: 12_000),
                  statement("silver-sep", card: "silver", on: day(2026, 9, 20), due: day(2026, 10, 10), total: 50_000, min: 5_000),
                  statement("plat-sep", card: "plat", on: day(2026, 9, 18), due: day(2026, 10, 8), total: 30_000, min: 3_000)] {
            data.statements[s.uid] = s
        }
        data.recurring["netflix"] = monthly("netflix", anchor: 3, next: day(2026, 10, 3))
        data.recurring["gym"] = monthly("gym", anchor: 5, next: day(2026, 10, 5))
        data.recurring["later"] = monthly("later", anchor: 3, next: day(2026, 12, 3))
        data.apply([
            payment("gold-part", .cardPayment, 20_000, on: day(2026, 9, 27), account: "bank", statement: "gold-sep"),
            payment("gold-more", .cardPayment, 10_000, on: day(2026, 9, 28), account: "bank", statement: "gold-sep"),
            payment("silver-all", .cardPayment, 50_000, on: day(2026, 9, 28), account: "bank", statement: "silver-sep"),
            payment("gym-paid", .expense, 64_900, on: day(2026, 9, 28), account: "bank", recurring: "gym", dueOn: day(2026, 10, 5)),
        ].map { RemoteRow.live($0) })

        func scanned() -> PendingSummary {
            Pending.summary(today: today, statements: Array(data.statements.values), recurring: Array(data.recurring.values),
                            transactions: Array(data.transactions.values))
        }
        #expect(scanned().items.map(\.sourceUid) == ["netflix", "plat-sep", "gold-sep"])
        #expect(data.pendingSummary(today: today).items == scanned().items)
        #expect(data.pendingSummary(today: today).items.last?.minDueMinor == 0)
        #expect(Destination.pending.count(in: data, today: today) == scanned().count)

        // A payment recorded later moves the badge with the screen.
        data.apply([RemoteRow.live(payment("plat-all", .cardPayment, 30_000, on: day(2026, 9, 29), account: "bank", statement: "plat-sep"))])
        #expect(scanned().count == 2)
        #expect(Destination.pending.count(in: data, today: today) == scanned().count)
        #expect(data.pendingSummary(today: today).items == scanned().items)
    }

    @Test func pendingHasNoCountWhenNothingIsDue() {
        var data = FinanceData()
        data.recurring["later"] = monthly("later", anchor: 3, next: day(2026, 12, 3))
        #expect(Destination.pending.count(in: data, today: day(2026, 9, 29)) == nil)
        #expect(Destination.accounts.count(in: data, today: day(2026, 9, 29)) == 0)
    }
}
