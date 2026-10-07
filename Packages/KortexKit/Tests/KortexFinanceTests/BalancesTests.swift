import Testing
@testable import KortexFinance

struct BalancesTests {
    private func account(_ uid: String, _ kind: AccountKind, linked: String? = nil) -> Account {
        Account(uid: uid, kind: kind, name: uid, institution: nil, last4: nil, hasSecret: false, bankType: nil, ifsc: nil,
                linkedAccountUid: linked, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
    }

    private func tx(_ uid: String, _ type: TransactionType, _ amount: Int64, from: String, to: String? = nil, on day: Int = 1) -> Transaction {
        Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0,
                    occurredOn: LocalDay(year: 2026, month: 9, day: day)!, accountUid: from, toAccountUid: to,
                    categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual, sourceRef: nil,
                    recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
    }

    @Test func bankCardAndDebitCardLedgers() {
        let bank = account("bank", .bank)
        let credit = account("credit", .creditCard)
        let debit = account("debit", .debitCard, linked: "bank")
        let accounts = Dictionary(uniqueKeysWithValues: [bank, credit, debit].map { ($0.uid, $0) })
        let entries = [
            tx("o", .opening, 100_000, from: "bank"),
            tx("i", .income, 50_000, from: "bank"),
            tx("d", .expense, 2_000, from: "debit"),        // lands on the linked bank account
            tx("c", .expense, 4_250, from: "credit"),       // raises what's owed
            tx("p", .cardPayment, 4_000, from: "bank", to: "credit"),
            tx("r", .income, 999, from: "credit"),          // card credits count for nothing in v1
        ]
        #expect(Balances.balance(of: bank, transactions: entries, accounts: accounts) == 144_000)
        #expect(Balances.balance(of: debit, transactions: entries, accounts: accounts) == 144_000)
        #expect(Balances.balance(of: credit, transactions: entries, accounts: accounts) == 250)
        #expect(Balances.totalBalance(accounts: accounts, transactions: entries) == 144_000, "cards never count")
    }

    @Test func transfersAndCutOffDay() {
        let a = account("a", .bank)
        let b = account("b", .wallet)
        let accounts = ["a": a, "b": b]
        let entries = [
            tx("o", .opening, 10_000, from: "a", on: 1),
            tx("t", .transfer, 3_000, from: "a", to: "b", on: 5),
        ]
        #expect(Balances.balance(of: a, transactions: entries, accounts: accounts) == 7_000)
        #expect(Balances.balance(of: b, transactions: entries, accounts: accounts) == 3_000)
        #expect(Balances.balance(of: a, transactions: entries, accounts: accounts, upTo: LocalDay(year: 2026, month: 9, day: 4)) == 10_000)
        #expect(Balances.totalBalance(accounts: accounts, transactions: entries) == 10_000, "a transfer moves nothing out")
    }

    @Test func cardsOutstandingAddsUpCreditCardsOnly() {
        var data = FinanceData()
        var closed = account("closed", .creditCard)
        closed.archived = true
        data.apply([account("bank", .bank), account("gold", .creditCard), account("plat", .creditCard),
                    account("debit", .debitCard, linked: "bank"), closed].map { RemoteRow.live($0) })
        data.apply([
            tx("o", .opening, 50_000, from: "bank"),
            tx("g", .expense, 3_000, from: "gold"),
            tx("p", .expense, 7_000, from: "plat"),
            tx("pay", .cardPayment, 2_000, from: "bank", to: "plat"),
            tx("c", .expense, 9_000, from: "closed"),
        ].map { RemoteRow.live($0) })
        #expect(data.cardsOutstandingMinor == 3_000 + 5_000, "not the debit card's bank balance, nor an archived card")
    }
}
