public enum StatementStatus: Sendable { case due, partlyPaid, paid, overdue }

/// A credit card's numbers on the Cards screen.
public struct CardPosition: Sendable {
    /// Everything owed: the open statement plus what's been spent since.
    public let outstandingMinor: Int64
    /// Nil when the card has no limit set.
    public let availableMinor: Int64?
    /// Outstanding ÷ limit, 0–1 (above 1 when over the limit); nil without a limit.
    public let utilisation: Double?
}

/// One account's money in and out over a period, opening entries excluded.
public struct LedgerFlow: Sendable {
    public let inMinor: Int64
    public let outMinor: Int64
    public let inCount: Int
    public let outCount: Int
    public var netMinor: Int64 { inMinor - outMinor }
}

/// Each ledger's transactions, balance and latest entry, grouped in one pass so the sidebar and
/// Accounts look them up instead of scanning every transaction per account. Keyed by ledger uid
/// (`Balances.ledger(of:in:)`), so a linked debit card's spends sit under its bank account.
public struct LedgerIndex: Sendable {
    private var entries: [String: [Transaction]] = [:]
    /// Only for ledgers that are accounts: a balance's rules depend on the account's kind.
    private var balances: [String: Int64] = [:]
    private var lastEntryDays: [String: LocalDay] = [:]

    public init() {}

    public init(transactions: some Sequence<Transaction>, accounts: [String: Account]) {
        for tx in transactions {
            let from = Balances.ledger(of: tx.accountUid, in: accounts)
            entries[from, default: []].append(tx)
            if let to = tx.toAccountUid.map({ Balances.ledger(of: $0, in: accounts) }), to != from {
                entries[to, default: []].append(tx)
            }
        }
        for (uid, txs) in entries {
            lastEntryDays[uid] = txs.lazy.filter { $0.type != .opening }.map(\.occurredOn).max()
            guard let ledgerAccount = accounts[uid] else { continue }
            balances[uid] = txs.reduce(0) { $0 + Balances.effect(of: $1, on: ledgerAccount, accounts: accounts) }
        }
    }

    /// The transactions with either side on the ledger, as `Balances.touches` picks them.
    public func entries(on ledgerUid: String) -> [Transaction] { entries[ledgerUid] ?? [] }

    /// Nil when the ledger isn't an account or has no transactions.
    public func balanceMinor(on ledgerUid: String) -> Int64? { balances[ledgerUid] }

    /// The day of the ledger's latest entry, opening entries aside.
    public func lastEntryOn(_ ledgerUid: String) -> LocalDay? { lastEntryDays[ledgerUid] }
}

public extension Balances {
    /// Whether `tx` touches `account`'s ledger, on either side.
    static func touches(_ tx: Transaction, _ account: Account, accounts: [String: Account]) -> Bool {
        let ledgerUid = ledger(of: account.uid, in: accounts)
        return ledger(of: tx.accountUid, in: accounts) == ledgerUid
            || tx.toAccountUid.map { ledger(of: $0, in: accounts) } == ledgerUid
    }

    /// The balance at the end of each day from `from` to `to`, for the account's balance chart.
    static func dailySeries(of account: Account, transactions: [Transaction], accounts: [String: Account], from: LocalDay, to: LocalDay) -> [(day: LocalDay, minor: Int64)] {
        let ledgerAccount = accounts[ledger(of: account.uid, in: accounts)] ?? account
        var before: Int64 = 0
        var perDay: [LocalDay: Int64] = [:]
        for tx in transactions {
            let effect = effect(of: tx, on: ledgerAccount, accounts: accounts)
            guard effect != 0 else { continue }
            if tx.occurredOn < from { before += effect } else if tx.occurredOn <= to { perDay[tx.occurredOn, default: 0] += effect }
        }
        var series: [(LocalDay, Int64)] = []
        var running = before
        var day = from
        while day <= to {
            running += perDay[day] ?? 0
            series.append((day, running))
            day = day.adding(days: 1)
        }
        return series
    }

    /// Money in and out of the account's ledger in `from`…`to`. For a credit card, "out" is what was
    /// spent on it and "in" is what was paid off.
    static func flow(of account: Account, transactions: [Transaction], accounts: [String: Account], from: LocalDay, to: LocalDay) -> LedgerFlow {
        let ledgerAccount = accounts[ledger(of: account.uid, in: accounts)] ?? account
        var inMinor: Int64 = 0, outMinor: Int64 = 0, inCount = 0, outCount = 0
        for tx in transactions where tx.type != .opening && tx.occurredOn.isWithin(from, to) {
            var effect = effect(of: tx, on: ledgerAccount, accounts: accounts)
            if ledgerAccount.kind == .creditCard { effect = -effect }
            if effect > 0 { inMinor += effect; inCount += 1 } else if effect < 0 { outMinor -= effect; outCount += 1 }
        }
        return LedgerFlow(inMinor: inMinor, outMinor: outMinor, inCount: inCount, outCount: outCount)
    }

    static func cardPosition(_ card: Account, transactions: [Transaction], accounts: [String: Account]) -> CardPosition {
        let outstanding = balance(of: card, transactions: transactions, accounts: accounts)
        let limit = card.creditLimitMinor.flatMap { $0 > 0 ? $0 : nil }
        return CardPosition(
            outstandingMinor: outstanding,
            availableMinor: limit.map { $0 - outstanding },
            utilisation: limit.map { Double(outstanding) / Double($0) }
        )
    }
}

public extension Statements {
    static func status(_ statement: CardStatement, _ txs: [Transaction], today: LocalDay) -> StatementStatus {
        let paid = paidMinor(statement, txs)
        if paid >= statement.totalDueMinor { return .paid }
        if today > statement.dueOn { return .overdue }
        return paid > 0 ? .partlyPaid : .due
    }

    /// When the bill was paid in full: the day of the payment that cleared it.
    static func paidOn(_ statement: CardStatement, _ txs: [Transaction]) -> LocalDay? {
        var paid: Int64 = 0
        for tx in txs.filter({ $0.type == .cardPayment && $0.statementUid == statement.uid }).sorted(by: { $0.occurredOn < $1.occurredOn }) {
            paid += tx.amountMinor
            if paid >= statement.totalDueMinor { return tx.occurredOn }
        }
        return nil
    }

    /// Spent on `card` after its statement: "Spent since 25 Sep statement".
    static func spentSinceMinor(_ card: Account, _ statement: CardStatement, _ txs: [Transaction], accounts: [String: Account]) -> Int64 {
        txs.filter { $0.type == .expense && Balances.ledger(of: $0.accountUid, in: accounts) == card.uid && $0.occurredOn > statement.statementOn }
            .reduce(0) { $0 + $1.amountMinor }
    }

    static func latest(for cardUid: String, in statements: [CardStatement]) -> CardStatement? {
        statements.filter { $0.cardUid == cardUid }.max { $0.statementOn < $1.statementOn }
    }
}
