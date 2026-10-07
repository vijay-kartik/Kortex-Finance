import Testing
@testable import KortexFinance

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d)! }

private func account(_ uid: String, _ kind: AccountKind, limit: Int64? = nil) -> Account {
    Account(uid: uid, kind: kind, name: uid, institution: nil, last4: nil, hasSecret: false, bankType: nil, ifsc: nil,
            linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: limit, statementDay: 25,
            dueDay: 15, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
}

private func tx(_ uid: String, _ type: TransactionType, _ amount: Int64, on: LocalDay, from: String, to: String? = nil, statement: String? = nil) -> Transaction {
    Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: on, accountUid: from,
                toAccountUid: to, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual, sourceRef: nil,
                recurringUid: nil, dueOn: nil, statementUid: statement, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
}

struct LedgerTests {
    let bank = account("bank", .bank)
    let card = account("card", .creditCard, limit: 5_000_000)
    var accounts: [String: Account] { ["bank": bank, "card": card] }

    @Test func dailySeriesStartsFromTheBalanceBeforeTheRange() {
        let txs = [
            tx("o", .opening, 100_000, on: day(2026, 8, 1), from: "bank"),
            tx("e", .expense, 10_000, on: day(2026, 9, 2), from: "bank"),
            tx("i", .income, 50_000, on: day(2026, 9, 3), from: "bank"),
        ]
        let series = Balances.dailySeries(of: bank, transactions: txs, accounts: accounts, from: day(2026, 9, 1), to: day(2026, 9, 3))
        #expect(series.map(\.minor) == [100_000, 90_000, 140_000])
    }

    @Test func flowLeavesOutOpeningAndCountsCardSpendAsOut() {
        let txs = [
            tx("o", .opening, 100_000, on: day(2026, 9, 1), from: "bank"),
            tx("i", .income, 542_000, on: day(2026, 9, 26), from: "bank"),
            tx("p", .cardPayment, 140_000, on: day(2026, 9, 28), from: "bank", to: "card"),
            tx("s", .expense, 4_250, on: day(2026, 9, 28), from: "card"),
        ]
        let bankFlow = Balances.flow(of: bank, transactions: txs, accounts: accounts, from: day(2026, 9, 1), to: day(2026, 9, 30))
        #expect(bankFlow.inMinor == 542_000 && bankFlow.inCount == 1)
        #expect(bankFlow.outMinor == 140_000)
        let cardFlow = Balances.flow(of: card, transactions: txs, accounts: accounts, from: day(2026, 9, 1), to: day(2026, 9, 30))
        #expect(cardFlow.outMinor == 4_250, "spent on the card")
        #expect(cardFlow.inMinor == 140_000, "the bill paid off")
    }

    @Test func cardPositionAndStatementStatus() {
        let statement = CardStatement(uid: "s", cardUid: "card", periodStart: day(2026, 8, 26), statementOn: day(2026, 9, 25),
                                      dueOn: day(2026, 10, 15), totalDueMinor: 140_000, minDueMinor: 20_000, source: .auto,
                                      createdAtMillis: 0, updatedAtMillis: 0)
        let txs = [
            tx("old", .expense, 140_000, on: day(2026, 9, 10), from: "card"),
            tx("new", .expense, 4_250, on: day(2026, 9, 28), from: "card"),
        ]
        let position = Balances.cardPosition(card, transactions: txs, accounts: accounts)
        #expect(position.outstandingMinor == 144_250)
        #expect(position.availableMinor == Int64(4_855_750), "available: \(String(describing: position.availableMinor))")
        #expect(Statements.spentSinceMinor(card, statement, txs, accounts: accounts) == 4_250)
        #expect(Statements.status(statement, txs, today: day(2026, 9, 29)) == .due)
        #expect(Statements.status(statement, txs, today: day(2026, 10, 16)) == .overdue)
        let paid = txs + [tx("p", .cardPayment, 140_000, on: day(2026, 10, 14), from: "bank", to: "card", statement: "s")]
        #expect(Statements.status(statement, paid, today: day(2026, 10, 16)) == .paid)
        #expect(Statements.paidOn(statement, paid) == day(2026, 10, 14))
    }

    @Test func expensesPeriodNeverStepsPastToday() {
        let today = day(2026, 9, 29)
        var period = ExpensesPeriod.startingAt(today)
        #expect(!period.canGoNext(today: today))
        #expect(period.next(today: today).month == today.yearMonth)
        period = period.previous()
        #expect(period.month == YearMonth(year: 2026, month: 8))
        #expect(period.canGoNext(today: today))
        period.mode = .daily
        #expect(period.next(today: today).day == today)
        period.mode = .yearly
        #expect(period.previous().range.from == day(2025, 1, 1))
    }
}
