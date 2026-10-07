/// What Add / Edit account collects, as kortex's AddAccount.kt `AccountDraft`.
public struct AccountDraft: Sendable {
    public var kind: AccountKind
    public var name: String
    public var institution: String?
    public var last4: String?
    public var bankType: BankType?
    public var ifsc: String?
    public var linkedAccountUid: String?
    public var network: String?
    public var expiry: String?
    public var holder: String?
    public var creditLimitMinor: Int64?
    public var statementDay: Int?
    public var dueDay: Int?
    public var colorToken: String?
    /// "Opening balance", or a credit card's "Outstanding today". Saved as the first entry. On edit it's
    /// `update`'s `opening` instead.
    public var openingMinor: Int64
    /// The full card or account number, sealed into finSecrets on save. Nil keeps the one saved.
    public var fullNumber: String?

    public init(kind: AccountKind, name: String = "", institution: String? = nil, last4: String? = nil, bankType: BankType? = nil,
                ifsc: String? = nil, linkedAccountUid: String? = nil, network: String? = nil, expiry: String? = nil,
                holder: String? = nil, creditLimitMinor: Int64? = nil, statementDay: Int? = nil, dueDay: Int? = nil,
                colorToken: String? = nil, openingMinor: Int64 = 0, fullNumber: String? = nil) {
        self.kind = kind
        self.name = name
        self.institution = institution
        self.last4 = last4
        self.bankType = bankType
        self.ifsc = ifsc
        self.linkedAccountUid = linkedAccountUid
        self.network = network
        self.expiry = expiry
        self.holder = holder
        self.creditLimitMinor = creditLimitMinor
        self.statementDay = statementDay
        self.dueDay = dueDay
        self.colorToken = colorToken
        self.openingMinor = openingMinor
        self.fullNumber = fullNumber
    }

    public init(_ a: Account) {
        self.init(kind: a.kind, name: a.name, institution: a.institution, last4: a.last4, bankType: a.bankType, ifsc: a.ifsc,
                  linkedAccountUid: a.linkedAccountUid, network: a.network, expiry: a.expiry, holder: a.holder,
                  creditLimitMinor: a.creditLimitMinor, statementDay: a.statementDay, dueDay: a.dueDay, colorToken: a.colorToken)
    }
}

/// Accounts and cards, as kortex's AddAccount.kt and EditAccount.kt.
public enum AccountRules {
    /// Adds an account or card. Its starting balance isn't a field on it but an OPENING entry saved
    /// alongside, so balances only ever change through entries.
    /// A full number is sealed with `key` into finSecrets, in the same batch as the account.
    public static func add(_ draft: AccountDraft, in data: FinanceData, key: DataKey? = nil, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let name = draft.name.cleaned else { return .failure(.blankName) }
        let number: String?
        switch AccountNumbers.clean(draft.fullNumber) {
        case .failure(let error): return .failure(error)
        case .success(let n): number = n
        }
        let last4 = draft.last4?.cleaned ?? number.map { String($0.suffix(4)) }
        if let last4, last4.count != 4 || !last4.allSatisfy(\.isNumber) { return .failure(.invalidLast4) }
        if let number, String(number.suffix(4)) != last4 { return .failure(.invalidNumber) }
        if number != nil && key == nil { return .failure(.noFinanceKey) }
        if [draft.statementDay, draft.dueDay].compactMap({ $0 }).contains(where: { !(1...31).contains($0) }) { return .failure(.invalidDay) }
        if draft.openingMinor < 0 || (draft.creditLimitMinor ?? 0) < 0 { return .failure(.invalidAmount) }
        var linked: Account?
        if let uid = draft.linkedAccountUid {
            guard let found = data.accounts[uid], found.kind == .bank else { return .failure(.unknownLinkedAccount) }
            linked = found
        }
        let now = clock.nowMillis
        let kind = draft.kind
        let uid = FinanceIds.random()
        var sealed: SealedSecret?
        if let number, let key {
            guard let s = SecretBox.seal(number, accountUid: uid, key: key) else { return .failure(.noFinanceKey) }
            sealed = s
        }
        let account = Account(
            uid: uid,
            kind: kind,
            name: name,
            institution: draft.institution?.cleaned,
            last4: last4,
            hasSecret: sealed != nil,
            bankType: kind == .bank ? draft.bankType : nil,
            ifsc: draft.ifsc?.cleaned?.uppercased(),
            linkedAccountUid: kind == .debitCard ? linked?.uid : nil,
            network: draft.network?.cleaned,
            expiry: draft.expiry?.cleaned,
            holder: draft.holder?.cleaned,
            creditLimitMinor: kind == .creditCard ? draft.creditLimitMinor : nil,
            statementDay: kind == .creditCard ? draft.statementDay : nil,
            dueDay: kind == .creditCard ? draft.dueDay : nil,
            colorToken: draft.colorToken,
            archived: false,
            createdAtMillis: now,
            updatedAtMillis: now
        )
        var writes: [RecordWrite] = [.account(account)]
        if let sealed { writes.append(.secret(accountUid: uid, sealed, atMillis: now)) }
        // A linked debit card has no money of its own; its bank account already has an opening entry.
        if draft.openingMinor > 0 && account.linkedAccountUid == nil {
            writes.append(.transaction(Transaction(
                uid: FinanceIds.random(), type: .opening, amountMinor: draft.openingMinor, currency: "INR",
                occurredAtMillis: now, occurredOn: clock.dayOf(now), accountUid: account.uid, toAccountUid: nil,
                categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual, sourceRef: nil,
                recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: now, updatedAtMillis: now
            )))
        }
        return .success(Change(writes))
    }

    /// The kind can't change. `opening` sets the balance it started with (`setOpening`); nil leaves it.
    /// A new full number replaces the one kept; nil keeps it.
    public static func update(_ uid: String, _ draft: AccountDraft, opening: Int64? = nil, in data: FinanceData, key: DataKey? = nil,
                              clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard var a = data.accounts[uid] else { return .failure(.notFound) }
        guard let name = draft.name.cleaned else { return .failure(.blankName) }
        let number: String?
        switch AccountNumbers.clean(draft.fullNumber) {
        case .failure(let error): return .failure(error)
        case .success(let n): number = n
        }
        let last4 = number.map { String($0.suffix(4)) } ?? draft.last4?.cleaned
        if let last4, last4.count != 4 || !last4.allSatisfy(\.isNumber) { return .failure(.invalidLast4) }
        if [draft.statementDay, draft.dueDay].compactMap({ $0 }).contains(where: { !(1...31).contains($0) }) { return .failure(.invalidDay) }
        if (draft.creditLimitMinor ?? 0) < 0 { return .failure(.invalidAmount) }
        let kind = a.kind
        a.name = name
        a.institution = draft.institution?.cleaned
        a.last4 = last4
        a.bankType = kind == .bank ? draft.bankType : nil
        a.ifsc = draft.ifsc?.cleaned?.uppercased()
        a.network = draft.network?.cleaned
        a.expiry = draft.expiry?.cleaned
        a.holder = draft.holder?.cleaned
        a.creditLimitMinor = kind == .creditCard ? draft.creditLimitMinor : nil
        a.statementDay = kind == .creditCard ? draft.statementDay : nil
        a.dueDay = kind == .creditCard ? draft.dueDay : nil
        a.colorToken = draft.colorToken ?? a.colorToken
        a.updatedAtMillis = clock.nowMillis
        var writes: [RecordWrite] = []
        if let number {
            guard let key, let sealed = SecretBox.seal(number, accountUid: uid, key: key) else { return .failure(.noFinanceKey) }
            a.hasSecret = true
            writes.append(.secret(accountUid: uid, sealed, atMillis: a.updatedAtMillis))
        }
        if let opening {
            switch setOpening(uid, to: opening, in: data, clock: clock) {
            case .success(let change): writes += change.writes
            case .failure(let error): return .failure(error)
            }
        }
        return .success(Change([.account(a)] + writes))
    }

    /// The balance an account started with (a credit card's, what it owed): its opening entries, together.
    public static func openingMinor(of uid: String, in data: FinanceData) -> Int64 {
        data.transactions.values.filter { $0.type == .opening && $0.accountUid == uid }.reduce(0) { $0 + $1.amountMinor }
    }

    /// The day an account's opening balance is on: its opening entry's, else its first entry's, else today.
    public static func openingDay(of uid: String, in data: FinanceData, clock: FinanceClock = .system) -> LocalDay {
        let mine = data.transactions.values.filter { $0.accountUid == uid || $0.toAccountUid == uid }
        return mine.filter { $0.type == .opening }.map(\.occurredOn).min() ?? mine.map(\.occurredOn).min() ?? clock.today
    }

    /// Sets the balance an account started with. Balances only change through entries, so it's the
    /// opening entry that changes: the first one takes the amount (any others go, as they'd add to it),
    /// a new one is dated to the account's first entry so its history never starts below it, and 0
    /// removes it. A linked debit card has no balance of its own. Unchanged writes nothing.
    public static func setOpening(_ uid: String, to minor: Int64, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let account = data.accounts[uid] else { return .failure(.notFound) }
        guard minor >= 0 else { return .failure(.invalidAmount) }
        if account.kind == .debitCard && account.linkedAccountUid != nil { return .success(Change([])) }
        guard minor != openingMinor(of: uid, in: data) else { return .success(Change([])) }
        let now = clock.nowMillis
        let openings = data.transactions.values.filter { $0.type == .opening && $0.accountUid == uid }
            .sorted { ($0.occurredAtMillis, $0.uid) < ($1.occurredAtMillis, $1.uid) }
        var writes: [RecordWrite] = openings.dropFirst().map { .delete(.transactions, uid: $0.uid, atMillis: now) }
        if var first = openings.first {
            if minor == 0 {
                writes.append(.delete(.transactions, uid: first.uid, atMillis: now))
            } else {
                first.amountMinor = minor
                first.updatedAtMillis = now
                writes.append(.transaction(first))
            }
        } else if minor > 0 {
            let day = openingDay(of: uid, in: data, clock: clock)
            writes.append(.transaction(Transaction(
                uid: FinanceIds.random(), type: .opening, amountMinor: minor, currency: "INR",
                occurredAtMillis: clock.millisOn(day), occurredOn: day, accountUid: uid, toAccountUid: nil,
                categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual, sourceRef: nil,
                recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: now, updatedAtMillis: now
            )))
        }
        return .success(Change(writes))
    }

    /// Deletes an account and its full number. Its entries stay in history, naming a deleted account,
    /// unless `withEntries`: then they go too, as `removeLeftovers` removes them.
    public static func delete(_ uid: String, withEntries: Bool = false, in data: FinanceData,
                              clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let a = data.accounts[uid] else { return .failure(.notFound) }
        let now = clock.nowMillis
        var writes: [RecordWrite] = [.delete(.accounts, uid: uid, atMillis: now)]
        if a.hasSecret { writes.append(.delete(.secrets, uid: uid, atMillis: now)) }
        if withEntries { writes += leftoverWrites(leftovers(of: [uid], in: data), now: now) }
        return .success(Change(writes))
    }

    /// What deleted accounts left behind.
    public struct Leftovers: Sendable {
        /// The deleted accounts these are from.
        public var gone: Set<String> = []
        /// Entries that only involve deleted accounts: removed.
        public var entries: [Transaction] = []
        /// Transfers and card payments between a deleted account and one you have. They're part of
        /// that account's balance, so they stay, with the deleted end as `FinanceIds.unknownAccount`.
        public var relabeled: [Transaction] = []
        /// Deleted cards' bills: removed, so they leave Pending payments.
        public var bills: [CardStatement] = []

        public var isEmpty: Bool { entries.isEmpty && relabeled.isEmpty && bills.isEmpty }
    }

    /// The accounts entries and bills name that Kortex no longer has: deleted, here or on the phone.
    public static func deletedAccountUids(in data: FinanceData) -> Set<String> {
        let named = data.transactions.values.flatMap { [$0.accountUid, $0.toAccountUid].compactMap { $0 } } + data.statements.values.map(\.cardUid)
        return Set(named).subtracting(data.accounts.keys).subtracting([FinanceIds.unknownAccount, FinanceIds.cardCredit])
    }

    /// What `gone` left behind: their entries and their cards' bills. An entry goes when every account
    /// it names is gone (the unknown account and a card credit's source name none). One that also
    /// involves an account you have stays, its gone end now the unknown account, so your balances
    /// don't move.
    public static func leftovers(of gone: Set<String>, in data: FinanceData) -> Leftovers {
        let isGone = { (uid: String) in gone.contains(uid) }
        let isLive = { (uid: String) in data.accounts[uid] != nil && !gone.contains(uid) }
        var result = Leftovers(gone: gone)
        for tx in data.transactions.values.sorted(by: { $0.uid < $1.uid }) {
            let ends = [tx.accountUid, tx.toAccountUid].compactMap { $0 }
            guard ends.contains(where: isGone) else { continue }
            if ends.contains(where: isLive) { result.relabeled.append(tx) } else { result.entries.append(tx) }
        }
        result.bills = data.statements.values.filter { isGone($0.cardUid) }.sorted { $0.uid < $1.uid }
        return result
    }

    /// Removes what accounts deleted earlier left behind (`leftovers`), in one change. Nothing to remove is `notFound`.
    public static func removeLeftovers(in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        let found = leftovers(of: deletedAccountUids(in: data), in: data)
        guard !found.isEmpty else { return .failure(.notFound) }
        return .success(Change(leftoverWrites(found, now: clock.nowMillis)))
    }

    /// Deletes the entries and bills, and points the kept entries' gone ends at the unknown account. A
    /// card payment to a gone card no longer pays its bill, which goes.
    private static func leftoverWrites(_ found: Leftovers, now: Int64) -> [RecordWrite] {
        var writes: [RecordWrite] = found.entries.map { .delete(.transactions, uid: $0.uid, atMillis: now) }
        writes += found.relabeled.map { tx in
            var t = tx
            if found.gone.contains(t.accountUid) { t.accountUid = FinanceIds.unknownAccount }
            if let to = t.toAccountUid, found.gone.contains(to) {
                t.toAccountUid = FinanceIds.unknownAccount
                t.statementUid = nil
            }
            t.updatedAtMillis = now
            return .transaction(t)
        }
        writes += found.bills.map { .delete(.statements, uid: $0.uid, atMillis: now) }
        return writes
    }
}
