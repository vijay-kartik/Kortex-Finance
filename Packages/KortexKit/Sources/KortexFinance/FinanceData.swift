/// Everything synced for the signed-in user, keyed by uid. Deleted records are dropped as their
/// delete markers arrive; built-in categories are always present since they're never synced.
public struct FinanceData: Sendable {
    public private(set) var accounts: [String: Account] = [:]
    public private(set) var transactions: [String: Transaction] = [:]
    public var categories: [String: Category] = Dictionary(uniqueKeysWithValues: BuiltInCategories.all.map { ($0.uid, $0) })
    public var recurring: [String: Recurring] = [:]
    public var statements: [String: CardStatement] = [:]
    public var merchants: [String: Merchant] = [:]
    /// Rebuilt whenever accounts or transactions change: a debit card's link moves its spends between ledgers.
    public private(set) var ledgers = LedgerIndex()

    public init() {}

    public mutating func apply(_ rows: [RemoteRow<Account>]) {
        Self.merge(rows, into: &accounts)
        ledgers = LedgerIndex(transactions: transactions.values, accounts: accounts)
    }

    public mutating func apply(_ rows: [RemoteRow<Transaction>]) {
        Self.merge(rows, into: &transactions)
        ledgers = LedgerIndex(transactions: transactions.values, accounts: accounts)
    }
    public mutating func apply(_ rows: [RemoteRow<Recurring>]) { Self.merge(rows, into: &recurring) }
    public mutating func apply(_ rows: [RemoteRow<CardStatement>]) { Self.merge(rows, into: &statements) }
    public mutating func apply(_ rows: [RemoteRow<Merchant>]) { Self.merge(rows, into: &merchants) }

    /// A synced category can't replace or delete a built-in one: built-ins are fixed on every device.
    public mutating func apply(_ rows: [RemoteRow<Category>]) {
        let builtIn = Set(BuiltInCategories.all.map(\.uid))
        Self.merge(rows.filter { row in
            switch row {
            case .live(let c): !builtIn.contains(c.uid)
            case .deleted(let uid): !builtIn.contains(uid)
            }
        }, into: &categories)
    }

    /// A change as its documents would come back through the listeners, without the round trip.
    /// Secrets and budgets aren't part of the data and are skipped.
    public mutating func apply(_ change: Change) {
        var accounts: [RemoteRow<Account>] = [], transactions: [RemoteRow<Transaction>] = [], categories: [RemoteRow<Category>] = []
        var recurring: [RemoteRow<Recurring>] = [], statements: [RemoteRow<CardStatement>] = [], merchants: [RemoteRow<Merchant>] = []
        for write in change.writes {
            switch write {
            case .account(let a): accounts.append(.live(a))
            case .transaction(let t): transactions.append(.live(t))
            case .category(let c): categories.append(.live(c))
            case .recurring(let r): recurring.append(.live(r))
            case .statement(let s): statements.append(.live(s))
            case .merchant(let m): merchants.append(.live(m))
            case .secret: break
            case .delete(let collection, let uid, _):
                switch collection {
                case .accounts: accounts.append(.deleted(uid: uid))
                case .transactions: transactions.append(.deleted(uid: uid))
                case .categories: categories.append(.deleted(uid: uid))
                case .recurring: recurring.append(.deleted(uid: uid))
                case .statements: statements.append(.deleted(uid: uid))
                case .merchants: merchants.append(.deleted(uid: uid))
                case .secrets, .budgets: break
                }
            }
        }
        if !categories.isEmpty { apply(categories) }
        if !accounts.isEmpty { apply(accounts) }
        if !statements.isEmpty { apply(statements) }
        if !recurring.isEmpty { apply(recurring) }
        if !merchants.isEmpty { apply(merchants) }
        if !transactions.isEmpty { apply(transactions) }
    }

    // MARK: Derived

    /// Accounts that aren't cards, newest last like the phone's list.
    public var moneyAccounts: [Account] {
        accounts.values.filter { !$0.kind.isCard && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    public var cards: [Account] {
        accounts.values.filter { $0.kind.isCard && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    /// What's owed on all your credit cards that aren't archived. Debit cards owe nothing: their
    /// balance is their bank account's.
    public var cardsOutstandingMinor: Int64 {
        accounts.values.filter { $0.kind == .creditCard && !$0.archived }.reduce(0) { $0 + balanceMinor(of: $1) }
    }

    /// Bank, cash and wallets that aren't archived, as `Balances.totalBalance`.
    public var totalBalanceMinor: Int64 {
        accounts.values.filter { $0.kind.countsInTotal && !$0.archived }.reduce(0) { $0 + balanceMinor(of: $1) }
    }

    /// As `Balances.balance`, looked up in `ledgers`. An account that isn't synced (yet) is summed
    /// from its ledger's entries alone.
    public func balanceMinor(of account: Account) -> Int64 {
        let ledgerAccount = accounts[Balances.ledger(of: account.uid, in: accounts)] ?? account
        return ledgers.balanceMinor(on: ledgerAccount.uid)
            ?? Balances.balance(of: account, transactions: ledgers.entries(on: ledgerAccount.uid), accounts: accounts)
    }

    /// The transactions on the account's ledger, either side: what `Balances.touches` picks out.
    public func ledgerEntries(of account: Account) -> [Transaction] {
        ledgers.entries(on: Balances.ledger(of: account.uid, in: accounts))
    }

    /// The day of the latest entry on the account's ledger, opening entries aside.
    public func lastEntryOn(of account: Account) -> LocalDay? {
        ledgers.lastEntryOn(Balances.ledger(of: account.uid, in: accounts))
    }

    /// Newest first, by day and then by time.
    public var transactionsNewestFirst: [Transaction] {
        transactions.values.sorted {
            ($0.occurredOn, $0.occurredAtMillis) > ($1.occurredOn, $1.occurredAtMillis)
        }
    }

    private static func merge<Row: Identifiable & Sendable>(_ rows: [RemoteRow<Row>], into map: inout [String: Row]) where Row.ID == String {
        for row in rows {
            switch row {
            case .live(let record): map[record.id] = record
            case .deleted(let uid): map[uid] = nil
            }
        }
    }
}
