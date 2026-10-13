import Foundation
import Testing
@testable import KortexFinance

private func account(_ uid: String, _ kind: AccountKind, name: String, last4: String?) -> Account {
    Account(uid: uid, kind: kind, name: name, institution: nil, last4: last4, hasSecret: false, bankType: nil, ifsc: nil,
            linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
            dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
}

private func entry(_ type: TransactionType = .expense, amount: Int64 = 124_900, account: String = "hdfc", to: String? = nil,
                   category: String? = nil, merchant: String? = nil, note: String? = nil, ref: String? = nil) -> Transaction {
    Transaction(uid: "t", type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: LocalDay(year: 2026, month: 9, day: 1)!,
                accountUid: account, toAccountUid: to, categoryUid: category, merchant: merchant, payeeKey: nil, note: note,
                source: .manual, sourceRef: ref, recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil,
                createdAtMillis: 0, updatedAtMillis: 0)
}

struct EntrySearchTests {
    private let data: FinanceData = {
        var data = FinanceData()
        data.apply([RemoteRow.live(account("hdfc", .bank, name: "HDFC Savings", last4: "4471")), .live(account("cash", .cash, name: "Cash", last4: nil))])
        return data
    }()

    private func finds(_ query: String, _ tx: Transaction) -> Bool { EntrySearch.matches(tx, query: query, data: data) }

    @Test func matchesMerchantNoteAndReference() {
        #expect(finds("swiggy", entry(merchant: "Swiggy Instamart")))
        #expect(finds("plumber", entry(note: "Paid the plumber")))
        #expect(finds("UTR6612", entry(ref: "UTR661204")))
        #expect(!finds("zomato", entry(merchant: "Swiggy", note: "Dinner")))
    }

    @Test func matchesCategoryName() {
        #expect(finds("food", entry(category: BuiltInCategories.food.uid)))
        #expect(!finds("travel", entry(category: BuiltInCategories.food.uid)))
        #expect(!finds("food", entry()), "Uncategorised has no name to match")
    }

    @Test func matchesEitherAccountByNameOrLast4() {
        #expect(finds("savings", entry()))
        #expect(finds("4471", entry()))
        #expect(finds("savings", entry(.transfer, account: "cash", to: "hdfc")))
        #expect(finds("4471", entry(.transfer, account: "cash", to: "hdfc")))
        #expect(!finds("4471", entry(account: "cash")))
    }

    @Test func amountQueriesMatchTheExactAmount() {
        for query in ["1249", "1,249", "1,249.00", "1249.0", "₹1,249", "₹ 1,249"] {
            #expect(finds(query, entry(account: "cash")), "\(query)")
        }
        #expect(finds("42.50", entry(amount: 4_250, account: "cash")))
        #expect(!finds("1249", entry(amount: 124_950, account: "cash")))
        #expect(!finds("249", entry(account: "cash")), "Part of an amount isn't that amount")
    }

    @Test func everyWordHasToMatch() {
        let tx = entry(amount: 24_000, merchant: "Swiggy")
        #expect(finds("swiggy hdfc", tx))
        #expect(finds("swiggy 240", tx))
        #expect(finds("  swiggy   4471 ", tx))
        #expect(!finds("swiggy cash", tx))
        #expect(!finds("swiggy 250", tx))
    }

    @Test func ignoresCaseAndAccents() {
        #expect(finds("CAFE", entry(merchant: "Café Coffee Day")))
        #expect(finds("café", entry(merchant: "Cafe Coffee Day")))
        #expect(finds("Ünion", entry(note: "union square")))
    }

    @Test func blankQueryMatchesEverything() {
        #expect(EntrySearch("   ").isEmpty)
        #expect(!EntrySearch("a").isEmpty)
        #expect(finds("", entry()))
        #expect(finds(" ", entry()))
    }
}
