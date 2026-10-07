/// Everything synced for the signed-in user, keyed by uid. Deleted records are dropped as their
/// delete markers arrive; built-in categories are always present since they're never synced.
public struct FinanceData: Sendable {
    public var accounts: [String: Account] = [:]
    public var transactions: [String: Transaction] = [:]
    public var categories: [String: Category] = Dictionary(uniqueKeysWithValues: BuiltInCategories.all.map { ($0.uid, $0) })
    public var recurring: [String: Recurring] = [:]
    public var statements: [String: CardStatement] = [:]
    public var merchants: [String: Merchant] = [:]

    public init() {}

    public mutating func apply(_ rows: [RemoteRow<Account>]) { Self.merge(rows, into: &accounts) }
    public mutating func apply(_ rows: [RemoteRow<Transaction>]) { Self.merge(rows, into: &transactions) }
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
        cards.filter { $0.kind == .creditCard }.reduce(0) { $0 + balanceMinor(of: $1) }
    }

    public var totalBalanceMinor: Int64 {
        Balances.totalBalance(accounts: accounts, transactions: Array(transactions.values))
    }

    public func balanceMinor(of account: Account) -> Int64 {
        Balances.balance(of: account, transactions: transactions.values, accounts: accounts)
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
