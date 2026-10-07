/// An entry from any screen, as kortex's AddTransaction.kt `TransactionDraft`.
public struct TransactionDraft: Sendable {
    public var type: TransactionType
    public var amountMinor: Int64
    public var accountUid: String
    public var toAccountUid: String?
    public var categoryUid: String?
    public var merchant: String?
    /// What the merchant is remembered by when it isn't its name (a UPI id).
    public var payeeKey: String?
    public var note: String?
    /// Defaults to now.
    public var occurredAtMillis: Int64?
    public var source: TransactionSource = .manual
    public var sourceRef: String?
    public var recurringUid: String?
    public var dueOn: LocalDay?
    public var statementUid: String?
    public var receipt: Receipt?
    /// A derived id (`rec_…`, `sms_…`); random when nil.
    public var uid: String?

    public init(type: TransactionType, amountMinor: Int64, accountUid: String, toAccountUid: String? = nil,
                categoryUid: String? = nil, merchant: String? = nil, payeeKey: String? = nil, note: String? = nil,
                occurredAtMillis: Int64? = nil, source: TransactionSource = .manual, sourceRef: String? = nil,
                recurringUid: String? = nil, dueOn: LocalDay? = nil, statementUid: String? = nil,
                receipt: Receipt? = nil, uid: String? = nil) {
        self.type = type
        self.amountMinor = amountMinor
        self.accountUid = accountUid
        self.toAccountUid = toAccountUid
        self.categoryUid = categoryUid
        self.merchant = merchant
        self.payeeKey = payeeKey
        self.note = note
        self.occurredAtMillis = occurredAtMillis
        self.source = source
        self.sourceRef = sourceRef
        self.recurringUid = recurringUid
        self.dueOn = dueOn
        self.statementUid = statementUid
        self.receipt = receipt
        self.uid = uid
    }
}

extension String {
    /// Trimmed, nil when empty: kortex's `clean()`.
    var cleaned: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Adding, editing and deleting entries, with the same validation, duplicate check and merchant
/// learning as kortex's AddTransaction.kt, whichever screen started it.
public enum EntryRules {
    /// What a card payment from `FinanceIds.unknownAccount` or `FinanceIds.cardCredit` is checked
    /// against: a bank under that uid, never saved.
    private static func standIn(_ uid: String) -> Account {
        Account(uid: uid, kind: .bank, name: uid, institution: nil, last4: nil, hasSecret: false, bankType: nil, ifsc: nil,
                linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
    }

    /// A validated entry and the merchant it teaches, not yet saved.
    public static func prepare(_ draft: TransactionDraft, in data: FinanceData, clock: FinanceClock,
                               existing: Transaction? = nil) -> Result<(Transaction, Merchant?), FinanceError> {
        guard draft.amountMinor > 0 else { return .failure(.invalidAmount) }
        guard draft.type != .opening else { return .failure(.invalidTarget) }
        if existing == nil, let uid = draft.uid, data.transactions[uid] != nil { return .failure(.alreadySaved) }
        // A card bill paid from an account not in Kortex yet, or a card credit, has no account of its own.
        let unknownSource = draft.type == .cardPayment && [FinanceIds.unknownAccount, FinanceIds.cardCredit].contains(draft.accountUid)
        guard let account = data.accounts[draft.accountUid] ?? (unknownSource ? standIn(draft.accountUid) : nil) else { return .failure(.unknownAccount) }

        let movesBetweenAccounts = draft.type == .transfer || draft.type == .cardPayment
        if movesBetweenAccounts {
            guard let toUid = draft.toAccountUid, toUid != account.uid, let target = data.accounts[toUid] else {
                return .failure(.invalidTarget)
            }
            let valid = draft.type == .cardPayment
                ? target.kind == .creditCard && account.kind != .creditCard
                : target.kind != .creditCard && account.kind != .creditCard
            guard valid else { return .failure(.invalidTarget) }
        } else {
            if draft.type == .income && account.kind == .creditCard { return .failure(.refundNotSupported) }
            if let uid = draft.categoryUid {
                let wanted: CategoryKind = draft.type == .income ? .income : .expense
                guard data.categories[uid]?.kind == wanted else { return .failure(.wrongCategoryKind) }
            }
        }

        let now = clock.nowMillis
        let at = draft.occurredAtMillis ?? now
        let merchantName = movesBetweenAccounts ? nil : draft.merchant?.cleaned
        let payeeKey = merchantName.map { FinanceIds.payeeKey(draft.payeeKey?.cleaned ?? $0) }
        let categoryUid = movesBetweenAccounts ? nil : draft.categoryUid
        let tx = Transaction(
            uid: existing?.uid ?? draft.uid ?? FinanceIds.random(),
            type: draft.type,
            amountMinor: draft.amountMinor,
            currency: existing?.currency ?? "INR",
            occurredAtMillis: at,
            occurredOn: clock.dayOf(at),
            accountUid: account.uid,
            toAccountUid: movesBetweenAccounts ? draft.toAccountUid : nil,
            categoryUid: categoryUid,
            merchant: merchantName,
            payeeKey: payeeKey,
            note: draft.note?.cleaned,
            source: draft.source,
            sourceRef: draft.sourceRef?.cleaned,
            recurringUid: draft.recurringUid,
            dueOn: draft.dueOn,
            // Only a bill of the card it pays.
            statementUid: draft.type == .cardPayment ? draft.statementUid.flatMap { data.statements[$0]?.cardUid == draft.toAccountUid ? $0 : nil } : nil,
            receipt: draft.receipt,
            createdAtMillis: existing?.createdAtMillis ?? now,
            updatedAtMillis: now
        )
        // Remember the payee's name and the category picked for it, so the next entry is suggested.
        let merchant = payeeKey.map { key -> Merchant in
            let known = data.merchants.values.first { $0.payeeKey == key }
            return Merchant(uid: known?.uid ?? FinanceIds.merchant(key), payeeKey: key, displayName: merchantName!,
                            categoryUid: categoryUid ?? known?.categoryUid, updatedAtMillis: now)
        }
        return .success((tx, merchant))
    }

    public static func add(_ draft: TransactionDraft, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        prepare(draft, in: data, clock: clock).map { tx, merchant in
            Change([.transaction(tx)] + (merchant.map { [.merchant($0)] } ?? []))
        }
    }

    /// Edits an entry in place. Where it came from (source, reference, receipt, the recurring payment it
    /// paid) stays as it was; a card payment's bill is the draft's.
    public static func edit(_ uid: String, _ draft: TransactionDraft, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let existing = data.transactions[uid] else { return .failure(.notFound) }
        guard existing.type != .opening else { return .failure(.invalidTarget) }
        var d = draft
        d.source = existing.source
        d.sourceRef = existing.sourceRef
        d.receipt = existing.receipt
        d.recurringUid = existing.recurringUid
        d.dueOn = existing.dueOn
        // A card payment's bill is part of what's edited: it may have been paired with the wrong one.
        d.statementUid = draft.type == .cardPayment ? draft.statementUid : existing.statementUid
        d.payeeKey = d.merchant?.cleaned == existing.merchant ? existing.payeeKey : nil
        return prepare(d, in: data, clock: clock, existing: existing).map { tx, merchant in
            Change([.transaction(tx)] + (merchant.map { [.merchant($0)] } ?? []))
        }
    }

    /// The other entries from the payee that `uid` is from once `draft` is saved, of its type and filed
    /// under another category than the draft's, newest first: the ones the edit offers to refile. The
    /// payee is told by name, or by the key the entry already had when its name is kept.
    public static func samePayee(as uid: String, _ draft: TransactionDraft, in data: FinanceData) -> [Transaction] {
        guard draft.type == .expense || draft.type == .income, let name = draft.merchant?.cleaned else { return [] }
        let existing = data.transactions[uid]
        let kept = existing?.merchant == name ? existing?.payeeKey : nil
        let keys = Set([FinanceIds.payeeKey(name), kept].compactMap { $0 }.filter { !$0.isEmpty })
        guard !keys.isEmpty else { return [] }
        return data.transactions.values.filter { tx in
            guard tx.uid != uid, tx.type == draft.type, tx.categoryUid != draft.categoryUid else { return false }
            return tx.payeeKey.map(keys.contains) == true || tx.merchant.map { keys.contains(FinanceIds.payeeKey($0)) } == true
        }.sorted { ($0.occurredAtMillis, $0.uid) > ($1.occurredAtMillis, $1.uid) }
    }

    /// How many days apart a transfer's two sides may be recorded: banks post them a day or two apart.
    public static let transferWindowDays = 3

    /// Making money out or in into a transfer (`draft`): the other account's record of the same money,
    /// which then is this transfer's other side. For money out of this account, money in to the one it
    /// went to; for money in, money out of the one it came from. The same amount within
    /// `transferWindowDays`, not paying a recurring payment, the closest first. Nil when there's none,
    /// or the edit doesn't keep the entry's own account on one end.
    public static func transferOtherSide(of uid: String, _ draft: TransactionDraft, in data: FinanceData,
                                         clock: FinanceClock = .system) -> Transaction? {
        guard draft.type == .transfer, let existing = data.transactions[uid], existing.type == .expense || existing.type == .income,
              let toUid = draft.toAccountUid else { return nil }
        let ledger = { (uid: String) in Balances.ledger(of: uid, in: data.accounts) }
        let here = ledger(existing.accountUid)
        let (other, recorded): (String, TransactionType)
        if here == ledger(draft.accountUid) { (other, recorded) = (ledger(toUid), .income) }
        else if here == ledger(toUid) { (other, recorded) = (ledger(draft.accountUid), .expense) }
        else { return nil }
        let day = clock.dayOf(draft.occurredAtMillis ?? existing.occurredAtMillis)
        return data.transactions.values.filter { tx in
            tx.uid != uid && tx.type == recorded && tx.recurringUid == nil && tx.amountMinor == draft.amountMinor
                && ledger(tx.accountUid) == other && abs(day.days(to: tx.occurredOn)) <= transferWindowDays
        }.min { (abs(day.days(to: $0.occurredOn)), $0.uid) < (abs(day.days(to: $1.occurredOn)), $1.uid) }
    }

    /// Making an entry a card bill payment from one of your accounts: the payment the card already has
    /// from an unknown account (its statement imported before this bank's), for the same amount within
    /// `transferWindowDays`, which then is this one. Nil when there's none.
    public static func cardPaymentOtherSide(of uid: String, _ draft: TransactionDraft, in data: FinanceData,
                                            clock: FinanceClock = .system) -> Transaction? {
        guard draft.type == .cardPayment, let cardUid = draft.toAccountUid, data.accounts[draft.accountUid] != nil,
              let existing = data.transactions[uid] else { return nil }
        let day = clock.dayOf(draft.occurredAtMillis ?? existing.occurredAtMillis)
        return data.transactions.values.filter { tx in
            tx.uid != uid && tx.type == .cardPayment && tx.accountUid == FinanceIds.unknownAccount && tx.toAccountUid == cardUid
                && tx.amountMinor == draft.amountMinor && abs(day.days(to: tx.occurredOn)) <= transferWindowDays
        }.min { (abs(day.days(to: $0.occurredOn)), $0.uid) < (abs(day.days(to: $1.occurredOn)), $1.uid) }
    }

    /// Edits an entry and, when the money it now moves between your accounts is already recorded on
    /// the other end (`transferOtherSide` for a transfer made of money out or in, `cardPaymentOtherSide`
    /// for a card payment), deletes that record in the same change: counted once, and neither side left
    /// as spending or income. A card payment takes over the other's bill when it has none of its own.
    public static func editMerging(_ uid: String, _ draft: TransactionDraft, in data: FinanceData,
                                   clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        var d = draft
        let other: Transaction? = switch draft.type {
        case .transfer: transferOtherSide(of: uid, draft, in: data, clock: clock)
        case .cardPayment: cardPaymentOtherSide(of: uid, draft, in: data, clock: clock)
        default: nil
        }
        if draft.type == .cardPayment, d.statementUid == nil { d.statementUid = other?.statementUid }
        return edit(uid, d, in: data, clock: clock).map { change in
            Change(change.writes + (other.map { [.delete(.transactions, uid: $0.uid, atMillis: clock.nowMillis)] } ?? []))
        }
    }

    /// The bill a card payment on `day` pays: the card's latest statement on or before it, from the last two months.
    public static func billPaid(_ cardUid: String, on day: LocalDay, in data: FinanceData) -> CardStatement? {
        data.statements.values
            .filter { $0.cardUid == cardUid && $0.statementOn <= day && $0.statementOn.days(to: day) <= 62 }
            .max { $0.statementOn < $1.statementOn }
    }

    /// Edits an entry and files `others` (from `samePayee`) under its new category too, in one change.
    public static func edit(_ uid: String, _ draft: TransactionDraft, alsoRefiling others: [String], in data: FinanceData,
                            clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        edit(uid, draft, in: data, clock: clock).map { change in
            let refiled = others.compactMap { data.transactions[$0] }.filter { $0.uid != uid && $0.type == draft.type }.map { tx -> RecordWrite in
                var t = tx
                t.categoryUid = draft.categoryUid
                t.updatedAtMillis = clock.nowMillis
                return .transaction(t)
            }
            return Change(change.writes + refiled)
        }
    }

    public static func delete(_ uid: String, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard data.transactions[uid] != nil else { return .failure(.notFound) }
        return .success(Change([.delete(.transactions, uid: uid, atMillis: clock.nowMillis)]))
    }

    /// Deletes several entries at once. Opening balances stay with their account; ones already gone are skipped.
    public static func delete(_ uids: some Collection<String>, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        let gone = uids.filter { data.transactions[$0].map { $0.type != .opening } == true }.sorted()
        guard !gone.isEmpty else { return .failure(.notFound) }
        return .success(Change(gone.map { .delete(.transactions, uid: $0, atMillis: clock.nowMillis) }))
    }

    /// Files several entries under `categoryUid`, or none when nil. Only expenses take an expense
    /// category and only income an income one; other entries, and ones already there, are left as they
    /// are. A category teaches each payee among them, as editing one entry does.
    public static func setCategory(_ uids: some Collection<String>, to categoryUid: String?, in data: FinanceData,
                                   clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        let kind = categoryUid.flatMap { data.categories[$0]?.kind }
        if categoryUid != nil && kind == nil { return .failure(.notFound) }
        let now = clock.nowMillis
        let changed = uids.compactMap { data.transactions[$0] }.filter { tx in
            guard tx.categoryUid != categoryUid else { return false }
            switch tx.type {
            case .expense: return kind == nil || kind == .expense
            case .income: return kind == nil || kind == .income
            default: return false
            }
        }.sorted { $0.uid < $1.uid }.map { tx -> Transaction in
            var t = tx
            t.categoryUid = categoryUid
            t.updatedAtMillis = now
            return t
        }
        var merchants: [String: Merchant] = [:]
        if let categoryUid {
            for tx in changed {
                guard let name = tx.merchant, let key = tx.payeeKey ?? Optional(FinanceIds.payeeKey(name)), !key.isEmpty else { continue }
                let known = data.merchants.values.first { $0.payeeKey == key }
                merchants[key] = Merchant(uid: known?.uid ?? FinanceIds.merchant(key), payeeKey: key, displayName: known?.displayName ?? name,
                                          categoryUid: categoryUid, updatedAtMillis: now)
            }
        }
        return .success(Change(changed.map { .transaction($0) } + merchants.keys.sorted().map { .merchant(merchants[$0]!) }))
    }

    /// Pay card bill: a card payment from an account against the statement.
    public static func payBill(statementUid: String, amountMinor: Int64, from accountUid: String, paidOn: LocalDay?,
                               in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let statement = data.statements[statementUid] else { return .failure(.notFound) }
        return add(TransactionDraft(type: .cardPayment, amountMinor: amountMinor, accountUid: accountUid,
                                    toAccountUid: statement.cardUid, occurredAtMillis: clock.millisOn(paidOn ?? clock.today),
                                    statementUid: statement.uid), in: data, clock: clock)
    }

    /// Scan receipt 05: the receipt joins an expense already saved; nothing is counted twice.
    public static func attachReceipt(_ receipt: Receipt, to uid: String, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard var tx = data.transactions[uid] else { return .failure(.notFound) }
        tx.receipt = receipt
        tx.updatedAtMillis = clock.nowMillis
        return .success(Change([.transaction(tx)]))
    }

    /// The amount a picked category's merchant memory suggests: the category remembered for this payee.
    public static func rememberedCategory(for merchant: String, in data: FinanceData) -> String? {
        let key = FinanceIds.payeeKey(merchant)
        guard !key.isEmpty else { return nil }
        return data.merchants.values.first { $0.payeeKey == key }?.categoryUid
    }
}
