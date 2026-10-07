/// Balances are never stored: each is the sum of its account's transactions from the opening entry on.
/// For a credit card the "balance" is what's owed. Same rules as kortex's domain/calc/Balances.kt.
public enum Balances {
    /// The account a transaction's money really moves on. A debit card's spends land on its linked
    /// bank account; an unlinked debit card is its own ledger.
    public static func ledger(of accountUid: String, in accounts: [String: Account]) -> String {
        guard let account = accounts[accountUid], account.kind == .debitCard else { return accountUid }
        return account.linkedAccountUid ?? accountUid
    }

    /// What a transaction does to `target`'s balance: positive raises a bank balance or a card's
    /// outstanding. Income and transfers into a credit card count for nothing (no refunds in v1).
    public static func effect(of transaction: Transaction, on target: Account, accounts: [String: Account]) -> Int64 {
        let amount = transaction.amountMinor
        let isFrom = ledger(of: transaction.accountUid, in: accounts) == target.uid
        let isTo = transaction.toAccountUid.map { ledger(of: $0, in: accounts) } == target.uid
        if target.kind == .creditCard {
            switch transaction.type {
            case .opening, .expense: return isFrom ? amount : 0
            case .cardPayment: return isTo ? -amount : 0
            case .income, .transfer: return 0
            }
        }
        switch transaction.type {
        case .opening, .income: return isFrom ? amount : 0
        case .expense, .cardPayment: return isFrom ? -amount : 0
        case .transfer: return (isTo ? amount : 0) - (isFrom ? amount : 0)
        }
    }

    /// The account's balance (a credit card's outstanding), counting transactions up to and including
    /// `upTo` when given. A linked debit card reports its bank account's balance.
    public static func balance(
        of account: Account,
        transactions: some Sequence<Transaction>,
        accounts: [String: Account],
        upTo: LocalDay? = nil
    ) -> Int64 {
        let ledgerAccount = accounts[ledger(of: account.uid, in: accounts)] ?? account
        return transactions.reduce(0) { sum, tx in
            if let upTo, tx.occurredOn > upTo { return sum }
            return sum + effect(of: tx, on: ledgerAccount, accounts: accounts)
        }
    }

    /// Bank, cash and wallets that aren't archived. Cards never count.
    public static func totalBalance(accounts: [String: Account], transactions: some Collection<Transaction>) -> Int64 {
        accounts.values
            .filter { $0.kind.countsInTotal && !$0.archived }
            .reduce(0) { $0 + balance(of: $1, transactions: transactions, accounts: accounts) }
    }
}
