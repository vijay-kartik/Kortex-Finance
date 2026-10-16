import Foundation

// MARK: What the model extracts

/// One statement as the model read it: every account on it (a composite statement has several).
/// Field names are the JSON schema's; amounts are in rupees as printed, made positive.
public struct ExtractedStatement: Codable, Sendable {
    public var accounts: [ExtractedAccount]

    public init(accounts: [ExtractedAccount]) { self.accounts = accounts }
}

public struct ExtractedAccount: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case bank, credit_card, loan, other }

    public var kind: Kind
    /// "HSBC", "HDFC Bank".
    public var institution: String?
    /// The product, as printed: "Savings Account", "Platinum Credit Card".
    public var productName: String?
    /// Only the last four digits of the account or card number.
    public var numberLast4: String?
    public var ifsc: String?
    public var holder: String?
    public var currency: String?
    public var periodStart: String?
    public var periodEnd: String?
    public var statementDate: String?
    /// Opening / closing balance; for a card, what was owed. `…IsDebit` when printed DR (overdrawn,
    /// or a card balance owed).
    public var openingBalance: Double?
    public var openingBalanceIsDebit: Bool?
    public var closingBalance: Double?
    public var closingBalanceIsDebit: Bool?
    public var creditLimit: Double?
    public var totalDue: Double?
    public var minimumDue: Double?
    public var paymentDueDate: String?
    public var transactions: [ExtractedTransaction]

    public var id: String { [kind.rawValue, numberLast4 ?? "", productName ?? ""].joined(separator: "|") }
}

public struct ExtractedTransaction: Codable, Sendable {
    public enum Direction: String, Codable, Sendable { case debit, credit }

    public var date: String
    /// The details column, joined into one line.
    public var description: String
    /// A short, tidy payee name when there is one ("Swiggy", "Acme Corp"); nil for transfers, fees, interest.
    public var merchant: String?
    public var amount: Double
    public var direction: Direction
    public var balanceAfter: Double?
    public var balanceAfterIsDebit: Bool?
    public var reference: String?
    /// One of the category ids the model was given, or nil.
    public var categoryId: String?
    /// The model's guess that this repeats on a schedule: an EMI, rent, a SIP, a subscription, a mandate debit.
    public var recurring: Bool? = nil
    /// The model's guess that this debit pays a credit card bill (bank statements).
    public var cardBillPayment: Bool? = nil
    /// The model's guess that this moves money between the holder's own accounts (bank statements).
    public var ownTransfer: Bool? = nil
}

// MARK: The reviewed import

/// One entry in the review table. Everything here is editable before the import is saved.
public extension ImportRow.Kind {
    /// Raises a bank balance: money in, or a transfer in from another of your accounts.
    var isMoneyIn: Bool { self == .income || self == .transferIn }
    var isTransfer: Bool { self == .transferOut || self == .transferIn }
}

public struct ImportRow: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Money out (bank) or a purchase (card).
        case expense
        /// Money in to a bank account.
        case income
        /// A credit card bill: paid from another account (a card's statement) or paid to a card (a bank's).
        case cardPayment
        /// Money to another of your accounts (bank statements).
        case transferOut
        /// Money from another of your accounts (bank statements).
        case transferIn
        /// A refund, reversal or cashback on a card (card statements): lowers what it owes, isn't a bill payment.
        case cardCredit
    }

    public let id: Int
    public var include: Bool
    public var date: LocalDay
    public var description: String
    public var merchant: String
    public var kind: Kind
    public var amountMinor: Int64
    public var categoryUid: String?
    /// For a card payment on a card's statement: the account it was paid from; nil when that isn't
    /// known (saved from `FinanceIds.unknownAccount` until a bank statement shows it).
    public var fromAccountUid: String?
    /// For a card payment on a bank statement: the card it paid.
    public var cardUid: String? = nil
    /// For a transfer: your other account, that the money went to or came from.
    public var transferAccountUid: String? = nil
    /// Read as a card bill or a transfer between your accounts, with the card or other account not in
    /// Kortex yet. Saved as money out or in, it keeps its details and no category, so importing the
    /// other side's statement can find it and make it what it is.
    public var otherSideMissing = false
    public var reference: String?
    /// The balance printed after this row, signed as a balance of this account.
    public var printedBalanceMinor: Int64?
    /// Why this row needs a look, if it does.
    public var issue: String?
    /// Whether this expense repeats. Only expenses can.
    public var repeats: ImportRepeats = .no
    /// A code in the details that comes back on every debit of one mandate and no other, when the
    /// statement prints one. It tells apart two instalments with the same payee and amount.
    public var mandateRef: String? = nil
    /// When importing into an account you have: the entry already in Kortex that this row is.
    public var match: ImportMatch? = nil
    /// The row as it was read (date, direction, amount, details), fixed while it's edited. The
    /// entry's id derives from it, so importing the same statement again finds what it added.
    public var key: String = ""
    /// For a card payment or transfer, the entry already in Kortex that is this one under another
    /// guise, which saving turns into it. For a card payment on a bank statement: the card's payment
    /// recorded from another account (a card statement's guess). On a card's statement: the money out
    /// a bank statement recorded before the card was in Kortex. For a transfer: the other account's
    /// side of it, recorded as money in or out before this account was in Kortex.
    public var replaces: String? = nil
}

/// An entry already in Kortex that a statement row is taken to be. Rows with one are left out unless
/// ticked, which adds them a second time.
public struct ImportMatch: Sendable, Hashable {
    public var transactionUid: String
    /// Sure: the same reference, an earlier import of this row, the same day, or the same payee. Not
    /// sure: only the amount agrees, a few days apart or under another name. Those are worth a look.
    public var sure: Bool
    /// Why it matched, for the review: "Same amount and day".
    public var reason: String
}

/// Whether an imported expense is a one-off or part of a recurring payment.
public enum ImportRepeats: Sendable, Hashable {
    case no
    /// Starts a recurring payment. Rows with the same merchant start one payment together.
    case new(RecurringKind)
    /// Pays one occurrence of a recurring payment you already have.
    case pays(recurringUid: String)
}

/// A credit card's bill as printed on the statement.
public struct ImportBill: Sendable, Hashable {
    public var statementOn: LocalDay
    public var dueOn: LocalDay
    public var totalMinor: Int64
    public var minMinor: Int64
    public var periodStart: LocalDay?
}

/// What will be added: the account (editable) and its reviewed entries.
public struct StatementImport: Sendable {
    public var account: AccountDraft
    /// Balance at the start of the statement (a card's outstanding), as the opening entry.
    public var openingMinor: Int64
    public var openingOn: LocalDay
    /// The statement's own closing figure, to reconcile against.
    public var closingMinor: Int64?
    /// The statement's last day.
    public var closingOn: LocalDay
    public var rows: [ImportRow]
    /// For a credit card: the bill on this statement.
    public var bill: ImportBill?
    /// The account the entries go to: a new one's uid, fixed for the session so saving twice writes
    /// the same documents, or the existing account's.
    public let accountUid: String
    /// Set when the rows go into an account you already have rather than a new one. Each row is then
    /// matched against that account's entries.
    public let existingAccountUid: String?
    /// How often each new recurring payment repeats, by its uid, where the reviewer chose; otherwise guessed.
    public var frequencies: [String: Frequency] = [:]

    public var intoExisting: Bool { existingAccountUid != nil }

    /// Opening + money in − money out over the included rows, signed as this account's balance.
    public var computedClosingMinor: Int64 {
        rows.filter(\.include).reduce(openingMinor) { sum, row in sum + StatementImport.effect(row, kind: account.kind) }
    }

    /// Whether the included rows land on the statement's closing balance.
    public var reconciles: Bool? { closingMinor.map { $0 == computedClosingMinor } }

    /// Importing into an account you have: Kortex's balance either side of the statement, once the
    /// included rows are added, and the entries Kortex has in its dates that no row matched. One pass
    /// over the account's ledger entries: nothing off its ledger moves its balance.
    public func reconciliation(in data: FinanceData) -> ImportReconciliation? {
        guard let uid = existingAccountUid, let account = data.accounts[uid] else { return nil }
        let ledgerAccount = data.accounts[Balances.ledger(of: uid, in: data.accounts)] ?? account
        let matched = Set(rows.compactMap { $0.match?.transactionUid })
        let added = rows.filter(\.include).reduce(Int64(0)) { $0 + StatementImport.effect($1, kind: account.kind) }
        var opening: Int64 = 0, closing: Int64 = 0
        var notOnStatement: [Transaction] = []
        for tx in data.ledgerEntries(of: account) {
            let effect = Balances.effect(of: tx, on: ledgerAccount, accounts: data.accounts)
            guard effect != 0, tx.occurredOn <= closingOn else { continue }
            closing += effect
            if tx.occurredOn < openingOn {
                opening += effect
            } else if tx.type != .opening && !matched.contains(tx.uid) {
                notOnStatement.append(tx)
            }
        }
        return ImportReconciliation(
            kortexOpeningMinor: opening,
            kortexClosingMinor: closing + added,
            notOnStatement: notOnStatement.sorted { ($0.occurredOn, $0.occurredAtMillis) < ($1.occurredOn, $1.occurredAtMillis) }
        )
    }

    /// Marks a row as one-off or recurring, and every other expense that's the same payment with it:
    /// marking one Netflix row marks them all.
    public mutating func setRepeats(_ repeats: ImportRepeats, forRow id: Int) {
        guard let row = rows.first(where: { $0.id == id }), row.kind == .expense else { return }
        for i in rows.indices where rows[i].id == id || (rows[i].kind == .expense && StatementImportRules.samePayment(row, rows[i])) {
            rows[i].repeats = repeats
        }
    }

    /// What a row does to this account's balance (a card's balance is what's owed).
    static func effect(_ row: ImportRow, kind: AccountKind) -> Int64 {
        if kind == .creditCard {
            switch row.kind {
            case .expense, .transferOut: return row.amountMinor
            case .cardPayment, .income, .transferIn, .cardCredit: return -row.amountMinor
            }
        }
        return row.kind.isMoneyIn ? row.amountMinor : -row.amountMinor
    }
}

/// How an account you have compares with a statement imported into it.
public struct ImportReconciliation: Sendable {
    /// Kortex's balance the day before the statement starts (a card's outstanding).
    public var kortexOpeningMinor: Int64
    /// Kortex's balance on the statement's last day, with the included rows added.
    public var kortexClosingMinor: Int64
    /// Entries in Kortex dated within the statement that no row matched, oldest first.
    public var notOnStatement: [Transaction]

    /// What the statement's period does to the balance in Kortex, against what the statement says it
    /// did. When these agree but the closing balances don't, the difference is from before the statement.
    public var kortexMovementMinor: Int64 { kortexClosingMinor - kortexOpeningMinor }
}
