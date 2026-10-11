import Testing
@testable import KortexFinance
@testable import KortexKit

/// The statement review's kept summaries: the same as working them out afresh, whatever was edited.
@MainActor
struct ReviewSummariesTests {
    private let today = LocalDay(year: 2026, month: 10, day: 6)!

    private func bankData(_ entries: [KortexFinance.Transaction] = []) -> FinanceData {
        var data = FinanceData()
        data.apply([RemoteRow.live(Account(
            uid: "bank", kind: .bank, name: "Bank", institution: nil, last4: "9001", hasSecret: false, bankType: .savings, ifsc: nil,
            linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil, dueDay: nil,
            colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0))])
        data.apply([row("open", .opening, 1_000_000, on: "2026-08-31")] + entries.map { RemoteRow.live($0) })
        return data
    }

    private func entry(_ uid: String, _ type: TransactionType, _ amount: Int64, on: String) -> KortexFinance.Transaction {
        KortexFinance.Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: LocalDay(on)!,
                                  accountUid: "bank", toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil,
                                  source: .sms, sourceRef: nil, recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil,
                                  createdAtMillis: 1, updatedAtMillis: 1)
    }

    private func row(_ uid: String, _ type: TransactionType, _ amount: Int64, on: String) -> RemoteRow<KortexFinance.Transaction> {
        .live(entry(uid, type, amount, on: on))
    }

    private func draft(in data: FinanceData) -> StatementImport {
        let tx = { (date: String, desc: String, amount: Double, merchant: String) in
            ExtractedTransaction(date: date, description: desc, merchant: merchant, amount: amount, direction: .debit,
                                 balanceAfter: nil, balanceAfterIsDebit: nil, reference: nil, categoryId: nil)
        }
        let statement = ExtractedAccount(
            kind: .bank, institution: "Test Bank", productName: "SAVINGS", numberLast4: "9001", ifsc: nil, holder: nil, currency: "INR",
            periodStart: "2026-09-01", periodEnd: "2026-09-30", statementDate: "2026-09-30", openingBalance: 10_000, openingBalanceIsDebit: false,
            closingBalance: nil, closingBalanceIsDebit: false, creditLimit: nil, totalDue: nil, minimumDue: nil, paymentDueDate: nil,
            transactions: [tx("2026-09-03", "NETFLIX", 649, "Netflix"), tx("2026-09-10", "UPI/CAFE", 200, "Cafe")])
        return StatementImportRules.prepare(statement, into: "bank", in: data, today: today)
    }

    @Test func theCheckAgainstKortexFollowsTheRowsFiguresAndTheData() throws {
        let summaries = ReviewSummaries()
        var data = bankData()
        var s = draft(in: data)
        #expect(try #require(summaries.reconciliation(s, in: data)).kortexClosingMinor == 1_000_000 - 64_900 - 20_000)

        s.rows[1].merchant = "Blue Tokai"
        #expect(try #require(summaries.reconciliation(s, in: data)).kortexClosingMinor == 1_000_000 - 64_900 - 20_000)

        s.rows[1].include = false
        #expect(try #require(summaries.reconciliation(s, in: data)).kortexClosingMinor == 1_000_000 - 64_900)

        s.rows[0].amountMinor = 49_900
        #expect(try #require(summaries.reconciliation(s, in: data)).kortexClosingMinor == 1_000_000 - 49_900)

        data.apply([row("cash", .expense, 5_000, on: "2026-09-20")])
        let r = try #require(summaries.reconciliation(s, in: data))
        #expect(r.kortexClosingMinor == 1_000_000 - 5_000 - 49_900, "an entry synced meanwhile counts")
        #expect(r.notOnStatement.map(\.uid) == ["cash"])
    }

    @Test func newRecurringPaymentsFollowTheRowsStartingThem() {
        let summaries = ReviewSummaries()
        var s = draft(in: bankData())
        #expect(summaries.newRecurring(s).isEmpty)

        s.setRepeats(.new(.subscription), forRow: s.rows[0].id)
        #expect(summaries.newRecurring(s).map(\.name) == StatementImportRules.newRecurring(s).map(\.name))
        #expect(summaries.newRecurring(s).count == 1)

        s.rows[1].merchant = "Blue Tokai"
        #expect(summaries.newRecurring(s).map(\.name) == StatementImportRules.newRecurring(s).map(\.name))

        s.rows[0].merchant = "Netflix India"
        #expect(summaries.newRecurring(s).map(\.name) == StatementImportRules.newRecurring(s).map(\.name), "a payment's name is its merchant's")

        let uid = summaries.newRecurring(s)[0].uid
        s.frequencies[uid] = .yearly
        #expect(summaries.newRecurring(s).map(\.frequency) == [.yearly])
    }
}
