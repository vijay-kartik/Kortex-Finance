import Testing
@testable import KortexFinance

struct AccountTests {
    private func account(_ uid: String, _ kind: AccountKind, last4: String? = nil, archived: Bool = false, createdAt: Int64 = 0) -> Account {
        Account(uid: uid, kind: kind, name: uid, institution: nil, last4: last4, hasSecret: false, bankType: nil, ifsc: nil,
                linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                dueDay: nil, colorToken: nil, archived: archived, createdAtMillis: createdAt, updatedAtMillis: 0)
    }

    @Test func labelAddsTheLastFourWhenThereAreSome() {
        #expect(account("HDFC Checking", .bank, last4: "4471").label == "HDFC Checking ••4471")
        #expect(account("Cash", .cash).label == "Cash")
    }

    @Test func activeListsSkipArchivedAndKeepTheOldestFirst() {
        var data = FinanceData()
        data.apply([
            account("card", .creditCard, createdAt: 3), account("bank", .bank, createdAt: 2), account("debit", .debitCard, createdAt: 1),
            account("old", .wallet, archived: true, createdAt: 0), account("cash", .cash, createdAt: 4),
        ].map { RemoteRow.live($0) })

        #expect(data.activeAccounts.map(\.uid) == ["debit", "bank", "card", "cash"])
        #expect(data.moneyAccounts.map(\.uid) == ["bank", "cash"])
        #expect(data.cards.map(\.uid) == ["debit", "card"])
    }
}
