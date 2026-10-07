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
    /// included rows are added, and the entries Kortex has in its dates that no row matched.
    public func reconciliation(in data: FinanceData) -> ImportReconciliation? {
        guard let uid = existingAccountUid, let account = data.accounts[uid] else { return nil }
        let txs = data.transactions.values
        let matched = Set(rows.compactMap { $0.match?.transactionUid })
        let added = rows.filter(\.include).reduce(Int64(0)) { $0 + StatementImport.effect($1, kind: account.kind) }
        return ImportReconciliation(
            kortexOpeningMinor: Balances.balance(of: account, transactions: txs, accounts: data.accounts, upTo: openingOn.adding(days: -1)),
            kortexClosingMinor: Balances.balance(of: account, transactions: txs, accounts: data.accounts, upTo: closingOn) + added,
            notOnStatement: txs.filter { tx in
                tx.type != .opening && tx.occurredOn >= openingOn && tx.occurredOn <= closingOn && !matched.contains(tx.uid)
                    && Balances.effect(of: tx, on: account, accounts: data.accounts) != 0
            }.sorted { ($0.occurredOn, $0.occurredAtMillis) < ($1.occurredOn, $1.occurredAtMillis) }
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

public enum StatementImportRules {
    /// The accounts you have that a statement could go into: bank accounts for a bank statement,
    /// credit cards for a card's.
    public static func accounts(for extracted: ExtractedAccount, in data: FinanceData) -> [Account] {
        let kind: AccountKind = extracted.kind == .credit_card ? .creditCard : .bank
        return data.accounts.values.filter { $0.kind == kind && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    /// The account you have that this statement is for, by its last 4 digits.
    public static func existingAccount(for extracted: ExtractedAccount, in data: FinanceData) -> Account? {
        guard let last4 = extracted.numberLast4.map({ String($0.filter(\.isASCIIDigit).suffix(4)) }), last4.count == 4 else { return nil }
        return accounts(for: extracted, in: data).first { $0.last4 == last4 }
    }

    /// Turns the model's reading of one account into a reviewable import: amounts to paise, dates
    /// parsed, categories checked against yours, merchant memory applied, and every row checked
    /// against the running balance printed beside it. Into an account you have (`into`), each row is
    /// also matched against its entries, and rows already there are left out.
    public static func prepare(_ extracted: ExtractedAccount, into existingUid: String? = nil, in data: FinanceData, today: LocalDay) -> StatementImport {
        let kind: AccountKind = extracted.kind == .credit_card ? .creditCard : .bank
        let existing = existingUid.flatMap { data.accounts[$0] }.flatMap { $0.kind == kind ? $0 : nil }
        // A card's bill payment is from your bank when you have one; with several it's unknown until shown.
        let banks = data.accounts.values.filter { $0.kind == .bank && !$0.archived }
        let onlyBank = banks.count == 1 ? banks.first : nil
        var rows: [ImportRow] = []
        var seen: [String: Int] = [:]
        for (i, t) in extracted.transactions.enumerated() {
            let day = parseDay(t.date) ?? parseDay(extracted.periodStart) ?? today
            let rowKind: ImportRow.Kind = kind == .creditCard
                ? (t.direction == .debit ? .expense : .cardPayment)
                : (t.direction == .credit ? .income : .expense)
            let categoryKind: CategoryKind = rowKind == .income ? .income : .expense
            let merchant = t.merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let remembered = merchant.isEmpty ? nil : EntryRules.rememberedCategory(for: merchant, in: data)
            let suggested = t.categoryId.flatMap { data.categories[$0]?.kind == categoryKind ? $0 : nil }
            rows.append(ImportRow(
                id: i, include: true, date: day, description: t.description.trimmingCharacters(in: .whitespacesAndNewlines),
                merchant: merchant, kind: rowKind, amountMinor: minor(t.amount),
                categoryUid: rowKind == .cardPayment ? nil : (remembered.flatMap { data.categories[$0]?.kind == categoryKind ? $0 : nil } ?? suggested),
                fromAccountUid: rowKind == .cardPayment ? onlyBank?.uid : nil,
                reference: t.reference,
                printedBalanceMinor: t.balanceAfter.map { signedBalance($0, debit: t.balanceAfterIsDebit, kind: kind) },
                issue: nil
            ))
            // Two identical rows (two coffees on one day) are told apart by their order.
            let base = "\(t.date)|\(t.direction.rawValue)|\(minor(t.amount))|\(FinanceIds.payeeKey(t.description))"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            rows[i].key = n == 0 ? base : "\(base)|\(n)"
        }

        let opening = extracted.openingBalance.map { signedBalance($0, debit: extracted.openingBalanceIsDebit, kind: kind) }
            ?? inferOpening(rows, kind: kind) ?? 0
        rows = check(rows, opening: opening, kind: kind)
        for i in rows.indices {
            if rows[i].amountMinor <= 0 { rows[i].include = false; rows[i].issue = "No amount was read." }
            if kind == .creditCard && rows[i].kind == .cardPayment && !looksLikePayment(rows[i].description) {
                // A credit that isn't a bill payment: a refund, a reversal, cashback.
                rows[i].kind = .cardCredit
                rows[i].fromAccountUid = nil
            }
        }
        let last4 = existing?.last4 ?? extracted.numberLast4.map { String($0.filter(\.isASCIIDigit).suffix(4)) }
        let transferHints = extracted.transactions.map { $0.ownTransfer == true }
        if kind == .bank {
            rows = markCardPayments(rows, hints: extracted.transactions.map { $0.cardBillPayment == true }, in: data)
            rows = markTransfers(rows, hints: transferHints, into: existing?.uid, in: data)
        }
        if let existing { rows = reconcile(rows, with: existing, in: data) }
        if kind == .bank {
            rows = matchOnCards(rows, in: data)
            rows = matchTransfers(rows, hints: transferHints, into: existing?.uid, last4: last4, in: data)
        }
        if kind == .creditCard { rows = matchOnBanks(rows, cardLast4: last4, in: data) }
        rows = suggestRepeats(markMandates(rows), hints: extracted.transactions.map { $0.recurring == true }, in: data)

        let institution = extracted.institution?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [institution, extracted.productName.map(tidyProduct)].compactMap { $0 }.joined(separator: " ")
        var draft = AccountDraft(
            kind: kind,
            name: name.isEmpty ? (kind == .creditCard ? "Credit card" : "Bank account") : name,
            institution: institution,
            last4: extracted.numberLast4.flatMap { digits -> String? in
                let d = digits.filter(\.isASCIIDigit)
                return d.count >= 4 ? String(d.suffix(4)) : nil
            },
            bankType: kind == .bank ? ((extracted.productName ?? "").localizedCaseInsensitiveContains("current") ? .current : .savings) : nil,
            ifsc: extracted.ifsc,
            holder: extracted.holder.map(TextReading.tidyName)
        )
        var bill: ImportBill?
        if kind == .creditCard {
            draft.creditLimitMinor = extracted.creditLimit.map(minor)
            let statementOn = parseDay(extracted.statementDate) ?? parseDay(extracted.periodEnd)
            let dueOn = parseDay(extracted.paymentDueDate)
            draft.statementDay = statementOn?.day
            draft.dueDay = dueOn?.day
            if let statementOn, let dueOn, let total = extracted.totalDue, total > 0 {
                bill = ImportBill(statementOn: statementOn, dueOn: dueOn, totalMinor: minor(total),
                                  minMinor: extracted.minimumDue.map(minor) ?? 0, periodStart: parseDay(extracted.periodStart))
            }
        }
        let firstDay = rows.map(\.date).min()
        let lastDay = rows.map(\.date).max()
        let openingOn = parseDay(extracted.periodStart) ?? firstDay ?? today
        let closingOn = parseDay(extracted.periodEnd) ?? parseDay(extracted.statementDate) ?? lastDay ?? today
        return StatementImport(
            account: draft,
            openingMinor: opening,
            openingOn: min(openingOn, firstDay ?? openingOn),
            closingMinor: extracted.closingBalance.map { signedBalance($0, debit: extracted.closingBalanceIsDebit, kind: kind) }
                ?? rows.last(where: { $0.printedBalanceMinor != nil })?.printedBalanceMinor,
            closingOn: max(closingOn, lastDay ?? closingOn),
            rows: rows,
            bill: bill,
            accountUid: existing?.uid ?? FinanceIds.random(),
            existingAccountUid: existing?.uid
        )
    }

    // MARK: Reconciling with an account you have

    /// How many days a statement's date may be from the entry's: cards post a few days after the purchase.
    static let matchWindowDays = 3

    /// Pairs each row with the entry already in the account that it is, at most one each way, the
    /// closest pairs first. An entry matches when it moves the balance by the same amount the same way
    /// (so a card bill paid from this account, or a transfer out, matches a debit) within a few days,
    /// or carries the row's reference. Matched rows are left out.
    static func reconcile(_ input: [ImportRow], with account: Account, in data: FinanceData) -> [ImportRow] {
        struct Pair { let row: Int; let tx: Transaction; let sure: Bool; let rank: Int; let gap: Int; let reason: String }
        var rows = input
        let candidates = data.transactions.values.compactMap { tx -> (Transaction, Int64)? in
            guard tx.type != .opening else { return nil }
            let effect = Balances.effect(of: tx, on: account, accounts: data.accounts)
            return effect == 0 ? nil : (tx, effect)
        }
        var pairs: [Pair] = []
        for (i, row) in rows.enumerated() {
            let effect = StatementImport.effect(row, kind: account.kind)
            let importedUid = importedEntryUid(accountUid: account.uid, key: row.key)
            for (tx, txEffect) in candidates where txEffect == effect {
                let gap = abs(row.date.days(to: tx.occurredOn))
                let names = nameAgreement(row, tx)
                let days = gap == 1 ? "1 day apart" : "\(gap) days apart"
                if tx.uid == importedUid {
                    pairs.append(Pair(row: i, tx: tx, sure: true, rank: 0, gap: gap, reason: "Imported from this statement before"))
                } else if sameReference(row, tx) {
                    pairs.append(Pair(row: i, tx: tx, sure: true, rank: 0, gap: gap, reason: "Same reference"))
                } else if gap <= matchWindowDays {
                    switch (gap, names) {
                    case (0, .some(true)): pairs.append(Pair(row: i, tx: tx, sure: true, rank: 1, gap: gap, reason: "Same amount, day and payee"))
                    case (0, .none): pairs.append(Pair(row: i, tx: tx, sure: true, rank: 1, gap: gap, reason: "Same amount and day"))
                    // Nothing to go by but the amount (a transfer, a bill payment): a day apart is how banks post them.
                    case (1, .none): pairs.append(Pair(row: i, tx: tx, sure: true, rank: 2, gap: gap, reason: "Same amount, a day apart"))
                    case (_, .some(true)): pairs.append(Pair(row: i, tx: tx, sure: true, rank: 2, gap: gap, reason: "Same amount and payee, \(days)"))
                    case (0, .some(false)): pairs.append(Pair(row: i, tx: tx, sure: false, rank: 3, gap: gap, reason: "Same amount and day, under another name"))
                    default: pairs.append(Pair(row: i, tx: tx, sure: false, rank: 3, gap: gap, reason: "Same amount, \(days)"))
                    }
                }
            }
        }
        var usedRows: Set<Int> = []
        var usedTxs: Set<String> = []
        for p in pairs.sorted(by: { ($0.rank, $0.gap, $0.row, $0.tx.uid) < ($1.rank, $1.gap, $1.row, $1.tx.uid) }) {
            guard !usedRows.contains(p.row), !usedTxs.contains(p.tx.uid) else { continue }
            usedRows.insert(p.row)
            usedTxs.insert(p.tx.uid)
            rows[p.row].match = ImportMatch(transactionUid: p.tx.uid, sure: p.sure, reason: p.reason)
            rows[p.row].include = false
        }
        return rows
    }

    /// The id a statement row is saved under in an account: from what was read, so importing the
    /// same statement twice writes the same documents.
    static func importedEntryUid(accountUid: String, key: String) -> String {
        "imp_" + FinanceIds.hash("\(accountUid)|\(key)")
    }

    /// The entry's reference is the row's, or printed in its details (a UPI or IMPS reference number).
    private static func sameReference(_ row: ImportRow, _ tx: Transaction) -> Bool {
        guard let ref = tx.sourceRef?.cleaned, ref.count >= 6 else { return false }
        return row.reference?.cleaned == ref || row.description.localizedCaseInsensitiveContains(ref)
    }

    /// True when the row and the entry name the same payee, false when both have names that differ,
    /// nil when the entry has no name to go by (a transfer).
    private static func nameAgreement(_ row: ImportRow, _ tx: Transaction) -> Bool? {
        let theirs = [tx.merchant, tx.payeeKey, tx.note].compactMap { $0.map(FinanceIds.payeeKey) }.filter { !$0.isEmpty }
        guard !theirs.isEmpty else { return nil }
        let ours = [row.merchant, row.description].map(FinanceIds.payeeKey).filter { !$0.isEmpty }
        return ours.contains { a in
            theirs.contains { b in a == b || (b.count >= 4 && a.contains(b)) || (a.count >= 4 && b.contains(a)) }
        }
    }

    /// Walks the rows against the balance printed beside each. A row whose amount only fits the
    /// other way round is turned round and flagged; one that fits neither way is flagged.
    static func check(_ input: [ImportRow], opening: Int64, kind: AccountKind) -> [ImportRow] {
        var rows = input
        var running = opening
        for i in rows.indices {
            let effect = StatementImport.effect(rows[i], kind: kind)
            guard let printed = rows[i].printedBalanceMinor else { running += effect; continue }
            if running + effect == printed {
                running = printed
                continue
            }
            if running - effect == printed {
                rows[i].kind = flipped(rows[i].kind, kind: kind, description: rows[i].description)
                rows[i].issue = "Direction corrected to match the printed balance."
            } else {
                rows[i].issue = "Doesn't match the printed balance of \(Money.format(printed)). Check the amount."
            }
            running = printed
        }
        return rows
    }

    private static func flipped(_ k: ImportRow.Kind, kind: AccountKind, description: String) -> ImportRow.Kind {
        if kind == .creditCard { return k == .expense ? (looksLikePayment(description) ? .cardPayment : .cardCredit) : .expense }
        switch k {
        case .transferOut: return .transferIn
        case .transferIn: return .transferOut
        case .income: return .expense
        default: return .income
        }
    }

    /// The balance before the first row, from the first printed balance.
    private static func inferOpening(_ rows: [ImportRow], kind: AccountKind) -> Int64? {
        guard let first = rows.first, let printed = first.printedBalanceMinor else { return nil }
        return printed - StatementImport.effect(first, kind: kind)
    }

    /// A bank balance printed DR is overdrawn (negative). A card's balance is what's owed, positive
    /// when printed DR (or plain); a credit balance on a card is negative.
    static func signedBalance(_ value: Double, debit: Bool?, kind: AccountKind) -> Int64 {
        let m = minor(abs(value))
        if kind == .creditCard { return debit == false || value < 0 ? -m : m }
        return debit == true || value < 0 ? -m : m
    }

    static func minor(_ rupees: Double) -> Int64 {
        Int64((Decimal(rupees) * 100 as NSDecimalNumber).rounding(accordingToBehavior:
            NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
                                   raiseOnUnderflow: false, raiseOnDivideByZero: false)).int64Value)
    }

    static func parseDay(_ text: String?) -> LocalDay? { text.flatMap(LocalDay.init) }

    // MARK: Card bills paid from a bank account

    /// Turns the debits that pay a credit card bill into card payments, each to the card it paid when
    /// that can be told. One the model flagged or whose details read like a card bill is one. With no
    /// card to pay, it stays money out, flagged: as spending it would count the card's purchases twice.
    static func markCardPayments(_ input: [ImportRow], hints: [Bool], in data: FinanceData) -> [ImportRow] {
        var rows = input
        let cards = data.accounts.values.filter { $0.kind == .creditCard && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        for i in rows.indices where rows[i].kind == .expense {
            let flagged = rows[i].id < hints.count && hints[rows[i].id]
            guard flagged || looksLikeCardBill(rows[i].description, cards: cards) else { continue }
            guard !cards.isEmpty else {
                rows[i].otherSideMissing = true
                rows[i].categoryUid = nil
                if rows[i].issue == nil {
                    rows[i].issue = "Looks like a credit card bill, with no card in Kortex to pay. It's added as money out for now; importing the card's statement turns it into the bill payment."
                }
                continue
            }
            rows[i].kind = .cardPayment
            rows[i].categoryUid = nil
            rows[i].cardUid = paidCard(rows[i], cards: cards, in: data)
        }
        return rows
    }

    /// Card bill wording as Indian banks print it, or one of your cards' numbers beside a card word.
    /// A debit card's purchases and cash withdrawals never are.
    static func looksLikeCardBill(_ description: String, cards: [Account]) -> Bool {
        let d = description.lowercased()
        let w = words(d)
        guard !d.contains("debit card"), w.isDisjoint(with: ["pos", "atm"]) else { return false }
        if cardBillPhrases.contains(where: d.contains) { return true }
        let mentionsCard = d.contains("card") || !w.isDisjoint(with: ["cc", "bbps", "billpay"])
        return mentionsCard && cards.contains { mentionsNumber(d, of: $0.last4) }
    }

    private static let cardBillPhrases = ["credit card", "creditcard", "cc payment", "ccpayment", "cc pymt", "cc bill", "card bill", "cred club", "credclub"]

    /// The details carry the card's last 4 digits, at the end of a run of digits ("XXXXXXXXXXXX4321").
    private static func mentionsNumber(_ text: String, of last4: String?) -> Bool {
        guard let last4, last4.count == 4 else { return false }
        return text.split { !$0.isASCIIDigit }.contains { $0.hasSuffix(last4) }
    }

    /// The card a bill payment went to, when only one fits: the card whose number is in the details,
    /// else whose bill on or before that day was for this amount (in full or the minimum), else whose
    /// bank the details name, else your only card.
    static func paidCard(_ row: ImportRow, cards: [Account], in data: FinanceData) -> String? {
        let d = row.description.lowercased()
        let byBill: (Account) -> Bool = { card in
            guard let bill = billPaid(card.uid, on: row.date, in: data) else { return false }
            return [bill.totalDueMinor, bill.minDueMinor].contains(row.amountMinor)
        }
        let byBank: (Account) -> Bool = { card in
            guard let bank = card.institution?.split(separator: " ").first?.lowercased(), bank.count >= 3 else { return false }
            return words(d).contains(bank) || d.contains(bank + "card")
        }
        let tests: [(Account) -> Bool] = [{ mentionsNumber(d, of: $0.last4) }, byBill, byBank, { _ in true }]
        for test in tests {
            let fits = cards.filter(test)
            if fits.count == 1 { return fits[0].uid }
            if fits.count > 1 { return nil }
        }
        return nil
    }

    static func billPaid(_ cardUid: String, on day: LocalDay, in data: FinanceData) -> CardStatement? {
        EntryRules.billPaid(cardUid, on: day, in: data)
    }

    /// A bill payment a card already has from another account is the same payment as a debit here
    /// when it's for the same amount within a few days. The row then takes its place rather than paying
    /// the card twice, and saving records it as paid from this account. A card payment row matches its
    /// card's payments. So does a debit with no payee, against a payment whose account is unknown (a
    /// card's statement imported before this bank's): the amount is all there is to go by, and the
    /// debit becomes that card's bill payment.
    static func matchOnCards(_ input: [ImportRow], in data: FinanceData) -> [ImportRow] {
        var rows = input
        var taken = Set(rows.compactMap { $0.match?.transactionUid })
        for i in rows.indices where rows[i].include && rows[i].match == nil && rows[i].replaces == nil {
            let row = rows[i]
            let isPayment = row.kind == .cardPayment
            guard isPayment || (row.kind == .expense && row.merchant.cleaned == nil) else { continue }
            let found = data.transactions.values.filter { tx in
                guard tx.type == .cardPayment, !tx.isCardCredit, tx.amountMinor == row.amountMinor, !taken.contains(tx.uid),
                      tx.toAccountUid.flatMap({ data.accounts[$0] })?.kind == .creditCard,
                      abs(row.date.days(to: tx.occurredOn)) <= matchWindowDays else { return false }
                if isPayment { return row.cardUid == nil || tx.toAccountUid == row.cardUid }
                return tx.accountUid == FinanceIds.unknownAccount
            }.min { (abs(row.date.days(to: $0.occurredOn)), $0.uid) < (abs(row.date.days(to: $1.occurredOn)), $1.uid) }
            guard let tx = found, let cardUid = tx.toAccountUid else { continue }
            taken.insert(tx.uid)
            if !isPayment {
                rows[i].kind = .cardPayment
                rows[i].categoryUid = nil
                rows[i].repeats = .no
                rows[i].mandateRef = nil
            }
            rows[i].cardUid = cardUid
            rows[i].replaces = tx.uid
            let card = data.accounts[cardUid].map { c in c.last4.map { "\(c.name) ••\($0)" } ?? c.name } ?? "The card"
            let day = tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
            rows[i].issue = tx.accountUid == FinanceIds.unknownAccount
                ? "\(card) has a bill payment of this amount on \(day) from an unknown account: this is it. Saving records it as paid from this account."
                : "\(card) already has this payment, recorded from \(data.accounts[tx.accountUid]?.name ?? "another account"). Saving records it as paid from this account instead."
        }
        return rows
    }

    /// A card statement's bill payment that a bank statement already recorded as money out (imported
    /// before the card was in Kortex) is that debit: the same amount within a few days, from a bank,
    /// cash or wallet, reading like a card bill or carrying the row's reference, else with no name and
    /// no category (how such a debit is often saved). The row is then paid from that account and
    /// saving turns the debit into this payment, so it's no longer spending and the card isn't paid
    /// twice. Debits paying a recurring payment are left alone.
    static func matchOnBanks(_ input: [ImportRow], cardLast4: String?, in data: FinanceData) -> [ImportRow] {
        var rows = input
        var taken = Set(rows.compactMap { $0.match?.transactionUid })
        let probe = cardLast4.map { last4 in [Account(
            uid: "", kind: .creditCard, name: "", institution: nil, last4: last4, hasSecret: false, bankType: nil, ifsc: nil,
            linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil, dueDay: nil,
            colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)] } ?? []
        for i in rows.indices where rows[i].kind == .cardPayment && rows[i].include && rows[i].match == nil {
            let row = rows[i]
            // How each debit fits: 0 reads like this bill, 1 has nothing to say otherwise; nil doesn't fit.
            func fit(_ tx: Transaction) -> Int? {
                guard tx.type == .expense, tx.recurringUid == nil, tx.amountMinor == row.amountMinor, !taken.contains(tx.uid),
                      abs(row.date.days(to: tx.occurredOn)) <= matchWindowDays,
                      let from = data.accounts[Balances.ledger(of: tx.accountUid, in: data.accounts)], !from.kind.isCard
                else { return nil }
                let details = [tx.merchant, tx.note].compactMap { $0 }.joined(separator: " ")
                if looksLikeCardBill(details, cards: probe) || sameReference(row, tx) { return 0 }
                return tx.merchant == nil && tx.categoryUid == nil ? 1 : nil
            }
            let found = data.transactions.values.compactMap { tx in fit(tx).map { (tx, $0) } }
                .min { ($0.1, abs(row.date.days(to: $0.0.occurredOn)), $0.0.uid) < ($1.1, abs(row.date.days(to: $1.0.occurredOn)), $1.0.uid) }?.0
            guard let tx = found else { continue }
            taken.insert(tx.uid)
            let bank = Balances.ledger(of: tx.accountUid, in: data.accounts)
            rows[i].fromAccountUid = bank
            rows[i].replaces = tx.uid
            let day = tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
            let what = (tx.merchant ?? tx.note).map { "\"\($0)\"" } ?? "A debit with no details"
            rows[i].issue = "\(what), money out from \(data.accounts[bank]?.name ?? "a bank") on \(day), is this payment. Saving makes it "
                + "the card's bill payment, so it no longer counts as spending. Pick another paid-from account to keep it as it is."
        }
        return rows
    }

    // MARK: Transfers between your accounts

    /// Your accounts a transfer can be with: banks, cash and wallets, other than this statement's.
    public static func transferAccounts(into existingUid: String?, in data: FinanceData) -> [Account] {
        data.accounts.values.filter { !$0.archived && !$0.kind.isCard && $0.uid != existingUid }.sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    /// Turns money out and in between this account and another of yours into transfers, when the other
    /// account can be told: the one whose number the details print, else whose bank they name. One the
    /// model flagged must name it this way or be found among that account's entries (`matchTransfers`);
    /// one it didn't must print the number and name no payee. Anything less stays money out or in: a
    /// payment to someone else is real spending, and guessing a transfer would hide it.
    static func markTransfers(_ input: [ImportRow], hints: [Bool], into existingUid: String?, in data: FinanceData) -> [ImportRow] {
        var rows = input
        let mine = transferAccounts(into: existingUid, in: data)
        for i in rows.indices where rows[i].kind == .expense || rows[i].kind == .income {
            let row = rows[i]
            let d = row.description.lowercased()
            let flagged = row.id < hints.count && hints[row.id]
            let byNumber = mine.filter { mentionsNumber(d, of: $0.last4) }
            let byBank = mine.filter { a in
                guard let bank = a.institution?.split(separator: " ").first?.lowercased(), bank.count >= 3 else { return false }
                return words(d).contains(bank)
            }
            let other: Account? = if byNumber.count == 1 && (flagged || row.merchant.cleaned == nil) { byNumber[0] }
                else if flagged && byNumber.isEmpty && byBank.count == 1 { byBank[0] }
                else { nil }
            guard let other else { continue }
            rows[i] = madeTransfer(row, with: other.uid)
        }
        return rows
    }

    /// Finds the other side of transfers among your other accounts' entries: money in there for money
    /// out here (or the other way round), the same amount within a few days, not paying a recurring
    /// payment. Its details printing this account's number, or the same reference, make it the other
    /// side of any row; for a row already taken for a transfer, or one the model flagged, so does having
    /// no payee and no category (how a transfer to an account not yet in Kortex is saved). Saving turns
    /// it into the transfer, so neither side counts as spending or income. A flagged row with no other
    /// side found stays money out or in, in no category, waiting for the other account's statement.
    static func matchTransfers(_ input: [ImportRow], hints: [Bool], into existingUid: String?, last4: String?,
                               in data: FinanceData) -> [ImportRow] {
        var rows = input
        var taken = Set(rows.compactMap { $0.match?.transactionUid })
        let mine = Set(transferAccounts(into: existingUid, in: data).map(\.uid))
        for i in rows.indices where rows[i].include && rows[i].match == nil && rows[i].replaces == nil {
            let row = rows[i]
            guard row.kind == .expense || row.kind == .income || row.kind.isTransfer else { continue }
            let flagged = row.kind.isTransfer || (row.id < hints.count && hints[row.id])
            let other: TransactionType = row.kind.isMoneyIn ? .expense : .income
            // How each entry fits: 0 names this account or shares the reference, 1 has nothing to say otherwise.
            func fit(_ tx: Transaction) -> Int? {
                let ledger = Balances.ledger(of: tx.accountUid, in: data.accounts)
                guard tx.type == other, tx.recurringUid == nil, tx.amountMinor == row.amountMinor, !taken.contains(tx.uid),
                      abs(row.date.days(to: tx.occurredOn)) <= matchWindowDays, mine.contains(ledger),
                      row.transferAccountUid == nil || row.transferAccountUid == ledger
                else { return nil }
                let details = [tx.merchant, tx.note].compactMap { $0 }.joined(separator: " ")
                if mentionsNumber(details, of: last4) || sameReference(row, tx) { return 0 }
                return flagged && tx.merchant == nil && tx.categoryUid == nil ? 1 : nil
            }
            let found = data.transactions.values.compactMap { tx in fit(tx).map { (tx, $0) } }
                .min { ($0.1, abs(row.date.days(to: $0.0.occurredOn)), $0.0.uid) < ($1.1, abs(row.date.days(to: $1.0.occurredOn)), $1.0.uid) }?.0
            guard let tx = found else {
                if flagged && !row.kind.isTransfer {
                    rows[i].otherSideMissing = true
                    rows[i].categoryUid = nil
                    if rows[i].issue == nil {
                        rows[i].issue = "Looks like a transfer \(row.kind == .income ? "from" : "to") another of your accounts. If it's in Kortex, set Type "
                            + "to Transfer and pick it; if not, it's added as money \(row.kind == .income ? "in" : "out") in no category, and importing that account's statement makes it the transfer."
                    }
                }
                continue
            }
            taken.insert(tx.uid)
            let account = Balances.ledger(of: tx.accountUid, in: data.accounts)
            rows[i] = madeTransfer(row, with: account)
            rows[i].replaces = tx.uid
            let what = (tx.merchant ?? tx.note).map { "\"\($0)\"" } ?? "An entry with no details"
            let day = tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
            let side = other == .income ? "money in to" : "money out from"
            rows[i].issue = "\(what), \(side) \(data.accounts[account]?.name ?? "another account") on \(day), is the other side of this transfer. "
                + "Saving makes it the transfer, so it no longer counts as \(other == .income ? "income" : "spending"). Pick another account to keep it as it is."
        }
        return rows
    }

    /// The row as a transfer with `account`: no category, never repeating.
    private static func madeTransfer(_ input: ImportRow, with account: String) -> ImportRow {
        var row = input
        if !row.kind.isTransfer { row.kind = row.kind == .income ? .transferIn : .transferOut }
        row.transferAccountUid = account
        row.categoryUid = nil
        row.repeats = .no
        row.mandateRef = nil
        row.otherSideMissing = false
        return row
    }

    private static func looksLikePayment(_ description: String) -> Bool {
        let d = description.lowercased()
        return ["payment", "paymt", "pymt", "thank you", "neft", "imps", "upi", "autopay", "auto debit", "bbps"].contains { d.contains($0) }
    }

    private static func tidyProduct(_ product: String) -> String {
        TextReading.tidyName(product.replacingOccurrences(of: "-RES", with: "").replacingOccurrences(of: "ACCOUNT", with: "Account"))
    }

    // MARK: Recurring

    /// How rows are matched to each other: by the name a payment from them would get.
    static func repeatKey(_ row: ImportRow) -> String { FinanceIds.payeeKey(paymentName(row)) }

    /// A recurring payment's name: the merchant, else what's left of the details once references,
    /// codes and the mandate's own wording are dropped. "NACH trxn ACH/INDIAN CLEARING
    /// CORP/ICIC7020807210000150/…" → "Indian Clearing"; "ACH D- HOME LOAN EMI 00123" → "Home Loan EMI".
    public static func paymentName(_ row: ImportRow) -> String {
        if let merchant = row.merchant.cleaned { return String(merchant.prefix(maxNameLength)) }
        for segment in row.description.split(separator: "/") {
            let kept = segment.split { $0.isWhitespace || $0 == "-" || $0 == ":" }
                .filter { word in word.allSatisfy(\.isLetter) && !detailNoise.contains(word.lowercased()) }
            if !kept.isEmpty {
                let name = TextReading.tidyName(kept.joined(separator: " "))
                    .split(separator: " ").map { $0.lowercased() == "emi" || $0.lowercased() == "sip" ? $0.uppercased() : String($0) }
                    .joined(separator: " ")
                return String(name.prefix(maxNameLength))
            }
        }
        return "Recurring payment"
    }

    private static let maxNameLength = 40

    /// Words in a statement's details that say how money moved, not to whom.
    private static let detailNoise: Set<String> = [
        "nach", "ecs", "ach", "mandate", "trxn", "txn", "trf", "dr", "cr", "d", "c", "debit", "credit", "si", "upi", "imps",
        "neft", "rtgs", "pos", "ref", "to", "by", "autopay", "auto",
    ]

    /// Rows that are one payment. The same merchant is. Without a merchant the name comes from the
    /// details, which may only name a clearing house that carries several mandates, so the amount
    /// must be about the same too.
    static func samePayment(_ a: ImportRow, _ b: ImportRow) -> Bool {
        if let ra = a.mandateRef, let rb = b.mandateRef { return ra == rb }
        let key = repeatKey(a)
        guard key == repeatKey(b), a.merchant.cleaned != nil || key != "recurring payment" else { return false }
        return (a.merchant.cleaned != nil && b.merchant.cleaned != nil) || similar(a.amountMinor, b.amountMinor, percent: 10)
    }

    /// Finds the mandate reference of debits that carry one: a code in the details (8+ letters and
    /// digits, with a digit) that comes back on two or more debits, never twice in one month, always for
    /// about the same amount. A code two mandates share, like the route's (a clearing house's), fails
    /// one of those and is ignored. Where several qualify, the one on the most debits wins.
    static func markMandates(_ input: [ImportRow]) -> [ImportRow] {
        var rows = input
        var seen: [String: [Int]] = [:]
        for i in rows.indices where rows[i].kind == .expense {
            for code in referenceCodes(rows[i].description) { seen[code, default: []].append(i) }
        }
        let mandates = seen.filter { _, found in
            let amounts = found.map { rows[$0].amountMinor }
            return found.count >= 2 && Set(found.map { rows[$0].date.yearMonth }).count == found.count
                && amounts.allSatisfy { similar($0, amounts[0], percent: 10) }
        }
        for i in rows.indices where rows[i].kind == .expense {
            rows[i].mandateRef = mandates.filter { $0.value.contains(i) }
                .max { ($0.value.count, $0.key) < ($1.value.count, $1.key) }?.key
        }
        return rows
    }

    private static func referenceCodes(_ text: String) -> Set<String> {
        Set(text.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { code in
            code.count >= 8 && code.contains(where: \.isNumber) && code.allSatisfy { $0.isASCII }
        })
    }

    /// Which expenses repeat, as first suggested. One that matches recurring payments you have pays
    /// one of them: a month's debits that match the same payments share them out in date order, so
    /// with two ₹2,000 instalments to one payee the month's first debit pays the one usually due
    /// first, and its second the other. One the model flagged, that reads like a mandate debit, or
    /// whose merchant took about the same amount about a month before or after, starts one.
    static func suggestRepeats(_ input: [ImportRow], hints: [Bool], in data: FinanceData) -> [ImportRow] {
        var rows = input
        let payments = data.recurring.values.sorted { ($0.anchorDay, $0.createdAtMillis, $0.uid) < ($1.anchorDay, $1.createdAtMillis, $1.uid) }
        let eligible = rows.indices.filter { rows[$0].kind == .expense && rows[$0].include && !rows[$0].otherSideMissing }
        var candidates: [Int: [Recurring]] = [:]
        for i in eligible {
            let found = payments.filter { matches(rows[i], $0) }
            if !found.isEmpty { candidates[i] = found }
        }
        let shares = Dictionary(grouping: candidates.keys) { i in
            candidates[i]!.map(\.uid).joined(separator: ",") + "|\(rows[i].date.yearMonth.year)-\(rows[i].date.yearMonth.month)"
        }
        var paying: Set<Int> = []
        for found in shares.values {
            let ordered = found.sorted { (rows[$0].date, rows[$0].id) < (rows[$1].date, rows[$1].id) }
            let choices = candidates[ordered[0]]!
            // A debit beyond the payments it matches may be a mandate you don't track yet.
            for (n, i) in ordered.enumerated() where n < choices.count {
                rows[i].repeats = .pays(recurringUid: choices[n].uid)
                paying.insert(i)
            }
        }
        for i in eligible where !paying.contains(i) {
            let row = rows[i]
            let monthApart = input.contains { other in
                other.id != row.id && other.kind == .expense && samePayment(row, other)
                    && similar(other.amountMinor, row.amountMinor, percent: 5) && (26...35).contains(abs(other.date.days(to: row.date)))
            }
            let flagged = row.id < hints.count && hints[row.id]
            if flagged || monthApart || !words(row.description).isDisjoint(with: mandateWords) {
                rows[i].repeats = .new(guessKind(row))
            }
        }
        return rows
    }

    /// The same payee (by merchant or details) and an amount within 10%: prices and EMIs change a little.
    static func matches(_ row: ImportRow, _ r: Recurring) -> Bool {
        let name = FinanceIds.payeeKey(r.name)
        guard !name.isEmpty, similar(row.amountMinor, r.amountMinor, percent: 10) else { return false }
        return [FinanceIds.payeeKey(row.merchant), FinanceIds.payeeKey(row.description)].contains { key in
            !key.isEmpty && (key == name || (name.count >= 4 && key.contains(name)) || (key.count >= 4 && name.contains(key)))
        }
    }

    private static func similar(_ a: Int64, _ b: Int64, percent: Int64) -> Bool {
        abs(a - b) * 100 <= max(a, b) * percent
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }

    /// Auto-debit mandates as Indian statements print them.
    private static let mandateWords: Set<String> = ["nach", "ecs", "ach", "emi", "mandate", "sip"]
    private static let fixedWords: Set<String> = mandateWords.union(["loan", "rent", "insurance", "premium", "lic", "maintenance"])

    /// EMIs, rent, SIPs and premiums are fixed; anything else that repeats is taken for a subscription.
    private static func guessKind(_ row: ImportRow) -> RecurringKind {
        words(row.description + " " + row.merchant).isDisjoint(with: fixedWords) ? .subscription : .fixed
    }

    /// The recurring payments saving will start, soonest due first.
    public static func newRecurring(_ draft: StatementImport) -> [Recurring] {
        startedPayments(draft, now: 0).payments.sorted { ($0.nextDueOn, $0.name) < ($1.nextDueOn, $1.name) }
    }

    /// Monthly and yearly are all a new payment can be for now.
    public static let newFrequencies: [Frequency] = [.monthly, .yearly]

    /// The payments the included expenses marked as starting one start. Rows that are the same
    /// payment (`samePayment`) are one, unless they come more than once in most months: then each
    /// month's debits, in date order, are split between that many payments (`splitByRank`). Each takes
    /// its latest row's amount, kind and category, falls on its rows' middle day of the month, and is
    /// next due after its latest row. Repeats as the reviewer chose, else yearly when its rows are that
    /// far apart, else monthly. `byRow` says which payment each row starts, by row id.
    static func startedPayments(_ draft: StatementImport, now: Int64) -> (payments: [Recurring], byRow: [Int: String]) {
        let starting = draft.rows.filter { row in
            guard row.include, row.kind == .expense, case .new = row.repeats else { return false }
            return true
        }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        var families: [[ImportRow]] = []
        for row in starting {
            if let i = families.lastIndex(where: { samePayment($0[$0.count - 1], row) }) { families[i].append(row) } else { families.append([row]) }
        }
        let groups = families.flatMap(splitByRank)
        var payments: [Recurring] = []
        var byRow: [Int: String] = [:]
        for group in groups {
            let latest = group[group.count - 1]
            let gaps = zip(group, group.dropFirst()).map { $0.date.days(to: $1.date) }.sorted()
            let gap = gaps.isEmpty ? 30 : gaps[gaps.count / 2]
            let uid = "imp_" + FinanceIds.hash("\(draft.accountUid)|recurring|\(repeatKey(group[0]))|\(group[0].id)")
            let frequency = draft.frequencies[uid] ?? (gap >= 300 ? .yearly : .monthly)
            guard case .new(let kind) = latest.repeats else { continue }
            let days = group.map(\.date.day).sorted()
            var r = Recurring(
                uid: uid,
                name: paymentName(latest),
                kind: kind, amountMinor: latest.amountMinor, currency: "INR", frequency: frequency, interval: 1,
                anchorDay: frequency == .monthly ? days[days.count / 2] : RecurringRules.anchorDay(frequency, latest.date),
                nextDueOn: latest.date,
                accountUid: draft.accountUid, categoryUid: latest.categoryUid, remindDaysBefore: -1,
                autoMarkPaid: false, paused: false, createdAtMillis: now, updatedAtMillis: now
            )
            r.nextDueOn = RecurringSchedule.nextAfter(r, RecurringSchedule.nearestDue(r, to: latest.date))
            payments.append(r)
            for row in group { byRow[row.id] = uid }
        }
        return (payments, byRow)
    }

    /// One payment's rows, or several when they come more than once in most months: as many payments
    /// as the usual count, each month's debits in date order going first to the first, second to the
    /// second. Any beyond the usual count go to the last.
    static func splitByRank(_ family: [ImportRow]) -> [[ImportRow]] {
        let months = Dictionary(grouping: family) { $0.date.yearMonth }
        let usual = Dictionary(grouping: months.values.map(\.count)) { $0 }.max { ($0.value.count, $0.key) < ($1.value.count, $1.key) }?.key ?? 1
        guard usual > 1 else { return [family] }
        var groups = Array(repeating: [ImportRow](), count: usual)
        for month in months.values {
            for (rank, row) in month.sorted(by: { ($0.date, $0.id) < ($1.date, $1.id) }).enumerated() {
                groups[min(rank, usual - 1)].append(row)
            }
        }
        return groups.map { $0.sorted { ($0.date, $0.id) < ($1.date, $1.id) } }
    }

    // MARK: Saving

    /// The account, its opening entry on the statement's first day, every included row as an entry,
    /// the merchants they teach, the recurring payments rows start or pay, and (for a card) its bill.
    /// Into an account you have, only the included rows (and a bill it doesn't have yet) are added.
    /// One change, so the phone never sees half.
    public static func commit(_ draft: StatementImport, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        var writes: [RecordWrite] = []
        var working = data
        let now = clock.nowMillis
        if draft.intoExisting {
            guard data.accounts[draft.accountUid] != nil else { return .failure(.notFound) }
        } else {
            switch newAccount(draft, in: data, clock: clock) {
            case .success(let account):
                writes.append(.account(account))
                working.apply([RemoteRow.live(account)])
            case .failure(let error):
                return .failure(error)
            }
        }

        let opening = max(draft.openingMinor, 0)
        if !draft.intoExisting && opening > 0 {
            writes.append(.transaction(Transaction(
                uid: "imp_" + FinanceIds.hash("\(draft.accountUid)|opening"), type: .opening, amountMinor: opening, currency: "INR",
                occurredAtMillis: clock.millisOn(draft.openingOn), occurredOn: draft.openingOn, accountUid: draft.accountUid,
                toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .statement, sourceRef: nil,
                recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: now, updatedAtMillis: now
            )))
        }

        // A row that repeats is saved as the occurrence it pays (`rec_…`, as Mark paid writes it), so
        // an occurrence the phone already recorded is replaced by the statement's row, not doubled.
        let started = startedPayments(draft, now: now)
        var payments = Dictionary(uniqueKeysWithValues: started.payments.map { ($0.uid, $0) })
        working.apply(started.payments.map { RemoteRow.live($0) })
        var paid: Set<String> = []
        var lastDue: [String: LocalDay] = [:]

        var merchants: [String: Merchant] = [:]
        for row in draft.rows where row.include {
            let isPayment = row.kind == .cardPayment
            let isCard = draft.account.kind == .creditCard
            if isPayment && !isCard && row.cardUid == nil { return .failure(.cardPaymentNeedsCard) }
            if row.kind.isTransfer && row.transferAccountUid == nil { return .failure(.transferNeedsAccount) }
            let paidCard = isPayment ? (isCard ? draft.accountUid : row.cardUid) : nil
            // Where the money comes from and goes to: this account, unless the row says otherwise.
            let (fromUid, toUid): (String, String?) = switch row.kind {
            case .cardPayment: (isCard ? (row.fromAccountUid ?? FinanceIds.unknownAccount) : draft.accountUid, paidCard)
            case .cardCredit: (FinanceIds.cardCredit, draft.accountUid)
            case .transferOut: (draft.accountUid, row.transferAccountUid)
            case .transferIn: (row.transferAccountUid ?? "", draft.accountUid)
            case .expense, .income: (draft.accountUid, nil)
            }
            // This entry as Kortex already has it: the card's payment recorded from another account, a
            // bank's debit saved as money out before the card was in Kortex, or the other account's side
            // of a transfer saved as money in or out. Each becomes this entry.
            let moved = row.replaces.flatMap { data.transactions[$0] }.flatMap { tx -> Transaction? in
                let ledger = Balances.ledger(of: tx.accountUid, in: data.accounts)
                switch row.kind {
                case .cardPayment:
                    if tx.type == .cardPayment { return tx.toAccountUid == paidCard ? tx : nil }
                    return isCard && tx.type == .expense && tx.recurringUid == nil && ledger == row.fromAccountUid ? tx : nil
                case .transferOut: return tx.type == .income && ledger == row.transferAccountUid ? tx : nil
                case .transferIn: return tx.type == .expense && tx.recurringUid == nil && ledger == row.transferAccountUid ? tx : nil
                case .expense, .income, .cardCredit: return nil
                }
            }
            // A debit turned into the payment or transfer keeps the day the money left.
            let movedDebit = moved?.type == .expense ? moved : nil
            var paying: Recurring?
            if row.kind == .expense {
                switch row.repeats {
                case .no: break
                case .new: paying = started.byRow[row.id].flatMap { payments[$0] }
                case .pays(let uid): paying = payments[uid] ?? data.recurring[uid]
                }
            }
            var dueOn: LocalDay?
            var uid = moved?.uid ?? importedEntryUid(accountUid: draft.accountUid, key: row.key)
            if let r = paying {
                let due = RecurringSchedule.nearestDue(r, to: row.date)
                let occurrence = FinanceIds.recurringOccurrence(r.uid, dueOn: due)
                // Two rows for one due date: the second stays a plain entry.
                if paid.insert(occurrence).inserted {
                    dueOn = due
                    uid = occurrence
                    payments[r.uid] = r
                    lastDue[r.uid] = max(lastDue[r.uid] ?? due, due)
                } else {
                    paying = nil
                }
            }
            let type: TransactionType = switch row.kind {
            case .cardPayment, .cardCredit: .cardPayment
            case .transferOut, .transferIn: .transfer
            case .income: .income
            case .expense: .expense
            }
            let entry = TransactionDraft(
                type: type,
                amountMinor: row.amountMinor,
                accountUid: fromUid,
                toAccountUid: toUid,
                categoryUid: toUid == nil ? row.categoryUid : nil,
                merchant: toUid == nil && !row.merchant.isEmpty ? row.merchant : nil,
                note: (row.otherSideMissing || row.kind == .cardCredit) && row.merchant.isEmpty ? row.description
                    : (row.merchant.isEmpty || row.merchant == row.description ? nil : row.description),
                occurredAtMillis: movedDebit?.occurredAtMillis ?? clock.millisOn(row.date),
                source: .statement,
                sourceRef: row.reference ?? moved?.sourceRef,
                recurringUid: paying?.uid,
                dueOn: dueOn,
                statementUid: paidCard.flatMap { moved?.statementUid ?? billPaid($0, on: movedDebit?.occurredOn ?? row.date, in: data)?.uid },
                // Derived from the import, so saving it twice writes the same documents.
                uid: uid
            )
            switch EntryRules.prepare(entry, in: working, clock: clock, existing: data.transactions[uid]) {
            case .success(let (tx, merchant)):
                var dated = tx
                dated.occurredOn = movedDebit?.occurredOn ?? row.date
                writes.append(.transaction(dated))
                if let merchant { merchants[merchant.uid] = merchant }
            case .failure(let error):
                return .failure(error)
            }
        }
        writes.append(contentsOf: merchants.values.map { .merchant($0) })

        // New payments, and existing ones whose next due date the statement has now paid, move on to
        // the first occurrence not paid by this import or already.
        for (uid, var r) in payments.sorted(by: { $0.key < $1.key }) {
            let isNew = started.byRow.values.contains(uid)
            if let last = lastDue[uid], last >= r.nextDueOn {
                var next = RecurringSchedule.nextAfter(r, last)
                for _ in 0..<60 {
                    let occurrence = FinanceIds.recurringOccurrence(uid, dueOn: next)
                    guard paid.contains(occurrence) || data.transactions[occurrence] != nil else { break }
                    next = RecurringSchedule.nextAfter(r, next)
                }
                r.nextDueOn = next
                r.updatedAtMillis = now
            } else if !isNew {
                continue
            }
            writes.append(.recurring(r))
        }

        // A card you have may already have this bill, from the phone or an earlier import.
        if let bill = draft.bill, !billExists(draft, in: data) {
            writes.append(.statement(CardStatement(
                uid: FinanceIds.statement(cardUid: draft.accountUid, statementOn: bill.statementOn), cardUid: draft.accountUid,
                periodStart: bill.periodStart ?? bill.statementOn.adding(days: -30), statementOn: bill.statementOn, dueOn: bill.dueOn,
                totalDueMinor: bill.totalMinor, minDueMinor: bill.minMinor, source: .manual, createdAtMillis: now, updatedAtMillis: now
            )))
        }
        return .success(Change(writes))
    }

    /// The new account as the review left it, under the import's uid and with no opening balance:
    /// the import writes its own opening entry, dated to the statement.
    private static func newAccount(_ draft: StatementImport, in data: FinanceData, clock: FinanceClock) -> Result<Account, FinanceError> {
        var accountDraft = draft.account
        accountDraft.openingMinor = 0
        return AccountRules.add(accountDraft, in: data, clock: clock).flatMap { change in
            guard case .account(let a) = change.writes.first else { return .failure(.notFound) }
            return .success(Account(
                uid: draft.accountUid, kind: a.kind, name: a.name, institution: a.institution, last4: a.last4,
                hasSecret: false, bankType: a.bankType, ifsc: a.ifsc, linkedAccountUid: a.linkedAccountUid,
                network: a.network, expiry: a.expiry, holder: a.holder, creditLimitMinor: a.creditLimitMinor,
                statementDay: a.statementDay, dueDay: a.dueDay, colorToken: a.colorToken, archived: false,
                createdAtMillis: a.createdAtMillis, updatedAtMillis: a.updatedAtMillis
            ))
        }
    }

    /// Whether the card already has a bill for this statement.
    public static func billExists(_ draft: StatementImport, in data: FinanceData) -> Bool {
        guard draft.intoExisting, let bill = draft.bill else { return false }
        return data.statements.values.contains { $0.cardUid == draft.accountUid && abs($0.statementOn.days(to: bill.statementOn)) <= matchWindowDays }
    }
}
