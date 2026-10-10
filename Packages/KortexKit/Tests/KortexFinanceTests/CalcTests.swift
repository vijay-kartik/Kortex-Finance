import Foundation
import Testing
@testable import KortexFinance

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d)! }

private func tx(_ uid: String, _ type: TransactionType, _ amount: Int64, on: LocalDay, account: String = "bank",
                category: String? = nil, recurring: String? = nil, dueOn: LocalDay? = nil, statement: String? = nil) -> Transaction {
    Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: on,
                accountUid: account, toAccountUid: nil, categoryUid: category, merchant: nil, payeeKey: nil, note: nil,
                source: .manual, sourceRef: nil, recurringUid: recurring, dueOn: dueOn, statementUid: statement,
                receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
}

private func monthly(_ uid: String, anchor: Int, next: LocalDay, amount: Int64 = 64_900, kind: RecurringKind = .subscription) -> Recurring {
    Recurring(uid: uid, name: uid, kind: kind, amountMinor: amount, currency: "INR", frequency: .monthly, interval: 1,
              anchorDay: anchor, nextDueOn: next, accountUid: "card", categoryUid: nil, remindDaysBefore: -1,
              autoMarkPaid: false, paused: false, createdAtMillis: 0, updatedAtMillis: 0)
}

struct CalendarTests {
    @Test func monthArithmeticAndClamping() {
        #expect(YearMonth(year: 2026, month: 1).adding(months: -1) == YearMonth(year: 2025, month: 12))
        #expect(YearMonth(year: 2026, month: 2).lengthOfMonth == 28)
        #expect(YearMonth(year: 2026, month: 9).day(31) == day(2026, 9, 30))
        #expect(day(2026, 9, 29).adding(days: 3) == day(2026, 10, 2))
        #expect(day(2026, 10, 1).isoWeekday == 4, "1 Oct 2026 is a Thursday")
        #expect(day(2026, 9, 29).days(to: day(2026, 10, 6)) == 7)
    }

    @Test func dateConversionIsGregorianWhateverTheMacCalendar() {
        let zones = ["UTC", "Asia/Kolkata", "America/Los_Angeles", "Pacific/Kiritimati"].map { TimeZone(identifier: $0)! }
        for zone in zones {
            for d in [day(2026, 9, 1), day(2026, 10, 11), day(2024, 2, 29), day(2026, 12, 31)] {
                #expect(LocalDay(date: d.date(in: zone), in: zone) == d)
            }
        }

        // Days that broke `Calendar.current`: Hebrew month 13 and Hebrew day 30, plus Japanese era years.
        let utc = TimeZone(identifier: "UTC")!
        func noon(_ d: LocalDay) -> Date { LocalDay.calendar(in: utc).date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12))! }
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = utc
        #expect(hebrew.component(.month, from: noon(day(2026, 9, 1))) == 13)
        #expect(LocalDay(date: noon(day(2026, 9, 1)), in: utc) == day(2026, 9, 1))
        #expect(hebrew.component(.day, from: noon(day(2026, 10, 11))) == 30)
        #expect(LocalDay(date: noon(day(2026, 10, 11)), in: utc) == day(2026, 10, 11))
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = utc
        #expect(japanese.component(.year, from: noon(day(2026, 10, 10))) != 2026)
        #expect(LocalDay(date: noon(day(2026, 10, 10)), in: utc) == day(2026, 10, 10))
    }
}

struct CalcTests {
    @Test func percentsAlwaysAddUpTo100() {
        #expect(roundedPercents([1, 1, 1]) == [34, 33, 33])
        #expect(roundedPercents([0, 0]) == [0, 0])
        #expect(roundedPercents([124_050, 60_400, 50_900, 47_700, 35_000]).reduce(0, +) == 100)
    }

    @Test func monthToDateComparesTheSameDayOfLastMonth() {
        let txs = [
            tx("a", .expense, 1_000, on: day(2026, 9, 3)),
            tx("b", .expense, 9_000, on: day(2026, 9, 30)),   // after day 29: not counted
            tx("c", .expense, 2_000, on: day(2026, 10, 2)),
        ]
        let mtd = Spending.monthToDate(txs, today: day(2026, 10, 29))
        #expect(mtd.thisMonthMinor == 2_000)
        #expect(mtd.lastMonthMinor == 1_000)
        #expect(mtd.deltaMinor == 1_000)
    }

    @Test func onlyExpensesAreSpendingAndOnlyIncomeIsIncome() {
        let txs = [
            tx("o", .opening, 100_000, on: day(2026, 9, 1)),
            tx("i", .income, 542_000, on: day(2026, 9, 1)),
            tx("e", .expense, 318_050, on: day(2026, 9, 2)),
            tx("p", .cardPayment, 140_000, on: day(2026, 9, 3)),
            tx("t", .transfer, 5_000, on: day(2026, 9, 4)),
        ]
        let flow = Spending.monthlyFlows(txs, endMonth: YearMonth(year: 2026, month: 9)).last!
        #expect(flow.inMinor == 542_000)
        #expect(flow.outMinor == 318_050)
        #expect(flow.keptPercent == 41)
    }

    @Test func whereItWentKeepsTopCategoriesAndFoldsTheRestIntoOther() {
        let cats = Dictionary(uniqueKeysWithValues: BuiltInCategories.all.map { ($0.uid, $0) })
        let txs = [
            tx("1", .expense, 500, on: day(2026, 9, 1), category: "food"),
            tx("2", .expense, 300, on: day(2026, 9, 1), category: "travel"),
            tx("3", .expense, 200, on: day(2026, 9, 1), category: nil),
            tx("4", .expense, 100, on: day(2026, 9, 1), category: "deleted-category"),
        ]
        let shares = Spending.whereItWent(txs, categories: cats, from: day(2026, 9, 1), to: day(2026, 9, 30), top: 1)
        #expect(shares.map(\.category?.uid) == ["food", nil])
        #expect(shares.map(\.amountMinor) == [500, 600])
        #expect(shares.map(\.percent).reduce(0, +) == 100)
    }

    @Test func monthlyRecurringKeepsItsAnchorDay() {
        let rent = monthly("rent", anchor: 31, next: day(2026, 8, 31))
        #expect(RecurringSchedule.nextAfter(rent, day(2026, 8, 31)) == day(2026, 9, 30))
        #expect(RecurringSchedule.nextAfter(rent, day(2026, 9, 30)) == day(2026, 10, 31))
    }

    @Test func pendingSkipsPaidOccurrencesAndPaidBills() {
        let today = day(2026, 9, 29)
        let netflix = monthly("netflix", anchor: 3, next: day(2026, 10, 3))
        let gym = monthly("gym", anchor: 5, next: day(2026, 10, 5), amount: 150_000, kind: .fixed)
        let statement = CardStatement(uid: "s1", cardUid: "card", periodStart: day(2026, 8, 26), statementOn: day(2026, 9, 25),
                                      dueOn: day(2026, 10, 15), totalDueMinor: 140_000, minDueMinor: 20_000, source: .auto,
                                      createdAtMillis: 0, updatedAtMillis: 0)
        let txs = [
            tx("paid-gym", .expense, 150_000, on: day(2026, 9, 28), recurring: "gym", dueOn: day(2026, 10, 5)),
            tx("part", .cardPayment, 40_000, on: day(2026, 9, 28), statement: "s1"),
        ]
        let summary = Pending.summary(today: today, statements: [statement], recurring: [netflix, gym], transactions: txs)
        #expect(summary.items.map(\.sourceUid) == ["netflix", "s1"])
        #expect(summary.cardBillsMinor == 100_000)
        #expect(summary.items.last?.minDueMinor == 0)
        #expect(summary.totalMinor == 164_900)
        #expect(Pending.urgency(day(2026, 10, 3), today: today) == .soon)
        #expect(Pending.urgency(day(2026, 10, 15), today: today) == .later)
        #expect(Pending.urgency(day(2026, 9, 28), today: today) == .overdue)
    }
}

struct LedgerIndexTests {
    private func account(_ uid: String, _ kind: AccountKind, linked: String? = nil, archived: Bool = false) -> Account {
        Account(uid: uid, kind: kind, name: uid, institution: nil, last4: nil, hasSecret: false, bankType: nil, ifsc: nil,
                linkedAccountUid: linked, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                dueDay: nil, colorToken: nil, archived: archived, createdAtMillis: 0, updatedAtMillis: 0)
    }

    private func move(_ uid: String, _ type: TransactionType, _ amount: Int64, from: String, to: String? = nil, on d: Int) -> Transaction {
        var t = tx(uid, type, amount, on: day(2026, 9, d), account: from)
        t.toAccountUid = to
        return t
    }

    /// The same answers the full scans give, account by account.
    private func expectMatchesScans(_ data: FinanceData, _ probes: [Account]) {
        let all = Array(data.transactions.values)
        for a in probes {
            let touching = all.filter { Balances.touches($0, a, accounts: data.accounts) }
            #expect(data.balanceMinor(of: a) == Balances.balance(of: a, transactions: all, accounts: data.accounts), "\(a.uid)")
            #expect(Set(data.ledgerEntries(of: a).map(\.uid)) == Set(touching.map(\.uid)), "\(a.uid)")
            #expect(data.lastEntryOn(of: a) == touching.filter { $0.type != .opening }.map(\.occurredOn).max(), "\(a.uid)")
        }
        #expect(data.totalBalanceMinor == Balances.totalBalance(accounts: data.accounts, transactions: all))
        #expect(data.cardsOutstandingMinor == data.cards.filter { $0.kind == .creditCard }
            .reduce(0) { $0 + Balances.balance(of: $1, transactions: all, accounts: data.accounts) })
    }

    @Test func indexedBalancesMatchTheScans() {
        var data = FinanceData()
        let accounts = [account("bank", .bank), account("wallet", .wallet), account("gold", .creditCard),
                        account("debit", .debitCard, linked: "bank"), account("loose", .debitCard),
                        account("old", .creditCard, archived: true)]
        data.apply(accounts.map { RemoteRow.live($0) })
        data.apply([
            move("o", .opening, 100_000, from: "bank", on: 1),
            move("i", .income, 50_000, from: "bank", on: 2),
            move("d", .expense, 2_000, from: "debit", on: 3),               // lands on the linked bank
            move("l", .expense, 700, from: "loose", on: 4),                 // an unlinked debit card is its own ledger
            move("t", .transfer, 3_000, from: "bank", to: "wallet", on: 5),
            move("td", .transfer, 1_000, from: "debit", to: "bank", on: 6), // both sides on one ledger
            move("g", .expense, 4_250, from: "gold", on: 7),
            move("p", .cardPayment, 4_000, from: "debit", to: "gold", on: 8),
            move("r", .income, 999, from: "gold", on: 9),
            move("x", .expense, 9_000, from: "old", on: 10),
            move("u", .cardPayment, 500, from: FinanceIds.unknownAccount, to: "gold", on: 11),
            move("gone", .expense, 5_000, from: "bank", on: 12),
        ].map { RemoteRow.live($0) })
        data.apply([RemoteRow<Transaction>.deleted(uid: "gone")])

        #expect(data.balanceMinor(of: accounts[0]) == 141_000)
        #expect(data.balanceMinor(of: accounts[3]) == 141_000, "a linked debit card shows its bank's balance")
        #expect(data.balanceMinor(of: accounts[2]) == -250)
        #expect(data.lastEntryOn(of: accounts[0]) == day(2026, 9, 8), "the deleted entry is gone")
        expectMatchesScans(data, accounts + [account("unsynced", .wallet)])

        // Linking the card later moves its spends onto the bank's ledger.
        data.apply([RemoteRow.live(account("loose", .debitCard, linked: "bank"))])
        #expect(data.balanceMinor(of: accounts[0]) == 140_300)
        expectMatchesScans(data, accounts)
    }
}
