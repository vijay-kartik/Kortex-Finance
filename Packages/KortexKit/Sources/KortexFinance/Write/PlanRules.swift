/// Add recurring payment / editing one, as kortex's RecurringPayments.kt `RecurringDraft`.
public struct RecurringDraft: Sendable {
    public var name: String
    public var kind: RecurringKind
    public var amountMinor: Int64
    public var frequency: Frequency
    public var interval: Int
    public var nextDueOn: LocalDay
    public var accountUid: String
    public var categoryUid: String?
    public var remindDaysBefore: Int
    public var autoMarkPaid: Bool
    public var paused: Bool

    public init(name: String, kind: RecurringKind, amountMinor: Int64, frequency: Frequency, interval: Int = 1,
                nextDueOn: LocalDay, accountUid: String, categoryUid: String? = nil, remindDaysBefore: Int = -1,
                autoMarkPaid: Bool = false, paused: Bool = false) {
        self.name = name
        self.kind = kind
        self.amountMinor = amountMinor
        self.frequency = frequency
        self.interval = interval
        self.nextDueOn = nextDueOn
        self.accountUid = accountUid
        self.categoryUid = categoryUid
        self.remindDaysBefore = remindDaysBefore
        self.autoMarkPaid = autoMarkPaid
        self.paused = paused
    }

    public init(_ r: Recurring) {
        self.init(name: r.name, kind: r.kind, amountMinor: r.amountMinor, frequency: r.frequency, interval: r.interval,
                  nextDueOn: r.nextDueOn, accountUid: r.accountUid, categoryUid: r.categoryUid,
                  remindDaysBefore: r.remindDaysBefore, autoMarkPaid: r.autoMarkPaid, paused: r.paused)
    }
}

/// Mark as paid's fields; each defaults to the recurring payment's own.
public struct PaymentDraft: Sendable {
    public var amountMinor: Int64?
    public var accountUid: String?
    public var paidOn: LocalDay?

    public init(amountMinor: Int64? = nil, accountUid: String? = nil, paidOn: LocalDay? = nil) {
        self.amountMinor = amountMinor
        self.accountUid = accountUid
        self.paidOn = paidOn
    }
}

/// Recurring payments, as kortex's RecurringPayments.kt.
public enum RecurringRules {
    public static let maxRemindDays = 7

    public static func anchorDay(_ frequency: Frequency, _ dueOn: LocalDay) -> Int {
        frequency == .weekly ? dueOn.isoWeekday : dueOn.day
    }

    /// Adds a recurring payment when `uid` is nil, otherwise edits that one. Nothing is paid by saving.
    public static func save(_ uid: String?, _ draft: RecurringDraft, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let name = draft.name.cleaned else { return .failure(.blankName) }
        guard draft.amountMinor > 0 else { return .failure(.invalidAmount) }
        guard (-1...maxRemindDays).contains(draft.remindDaysBefore) else { return .failure(.invalidReminder) }
        guard data.accounts[draft.accountUid] != nil else { return .failure(.unknownAccount) }
        if let c = draft.categoryUid, data.categories[c]?.kind != .expense { return .failure(.wrongCategoryKind) }
        var existing: Recurring?
        if let uid {
            guard let found = data.recurring[uid] else { return .failure(.notFound) }
            existing = found
        }
        let now = clock.nowMillis
        // Unchanged dates keep their anchor, so a payment on the 31st that fell on the 30th this
        // month goes back to the 31st next month.
        let keepsAnchor = existing.map { $0.nextDueOn == draft.nextDueOn && $0.frequency == draft.frequency } ?? false
        let r = Recurring(
            uid: existing?.uid ?? FinanceIds.random(),
            name: name,
            kind: draft.kind,
            amountMinor: draft.amountMinor,
            currency: existing?.currency ?? "INR",
            frequency: draft.frequency,
            interval: max(draft.interval, 1),
            anchorDay: keepsAnchor ? existing!.anchorDay : anchorDay(draft.frequency, draft.nextDueOn),
            nextDueOn: draft.nextDueOn,
            accountUid: draft.accountUid,
            categoryUid: draft.categoryUid,
            remindDaysBefore: draft.remindDaysBefore,
            autoMarkPaid: draft.autoMarkPaid,
            paused: draft.paused,
            createdAtMillis: existing?.createdAtMillis ?? now,
            updatedAtMillis: now
        )
        return .success(Change([.recurring(r)]))
    }

    /// Deleting a recurring payment keeps the expenses it recorded.
    public static func delete(_ uid: String, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard data.recurring[uid] != nil else { return .failure(.notFound) }
        return .success(Change([.delete(.recurring, uid: uid, atMillis: clock.nowMillis)]))
    }

    public static func setPaused(_ uid: String, _ paused: Bool, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard var r = data.recurring[uid] else { return .failure(.notFound) }
        r.paused = paused
        r.updatedAtMillis = clock.nowMillis
        return .success(Change([.recurring(r)]))
    }

    /// Pays one occurrence: records the expense (`rec_…`, so paying it on two devices is one entry)
    /// and moves the next due date on, as one change. Already paid elsewhere: just moves the date.
    public static func markPaid(_ recurringUid: String, dueOn: LocalDay, payment: PaymentDraft = PaymentDraft(),
                                in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let r = data.recurring[recurringUid] else { return .failure(.notFound) }
        var moved = r
        moved.nextDueOn = nextUnpaid(r, after: dueOn, in: data)
        moved.updatedAtMillis = clock.nowMillis
        let uid = FinanceIds.recurringOccurrence(recurringUid, dueOn: dueOn)
        if data.transactions[uid] != nil {
            return .success(Change(moved.nextDueOn != r.nextDueOn ? [.recurring(moved)] : []))
        }
        let draft = TransactionDraft(
            type: .expense,
            amountMinor: payment.amountMinor ?? r.amountMinor,
            accountUid: payment.accountUid ?? r.accountUid,
            categoryUid: r.categoryUid,
            merchant: r.name,
            occurredAtMillis: clock.millisOn(payment.paidOn ?? clock.today),
            source: .recurring,
            recurringUid: r.uid,
            dueOn: dueOn,
            uid: uid
        )
        return EntryRules.prepare(draft, in: data, clock: clock).map { tx, merchant in
            Change([.recurring(moved), .transaction(tx)] + (merchant.map { [.merchant($0)] } ?? []))
        }
    }

    /// Skip this time: moves the next due date on without recording anything.
    public static func skip(_ recurringUid: String, dueOn: LocalDay, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard var r = data.recurring[recurringUid] else { return .failure(.notFound) }
        r.nextDueOn = nextUnpaid(r, after: dueOn, in: data)
        r.updatedAtMillis = clock.nowMillis
        return .success(Change([.recurring(r)]))
    }

    /// The first occurrence after `dueOn` (or the current next due date, if later) that isn't paid
    /// yet; another device may already have paid the following ones.
    static func nextUnpaid(_ r: Recurring, after dueOn: LocalDay, in data: FinanceData) -> LocalDay {
        var next = dueOn < r.nextDueOn ? r.nextDueOn : RecurringSchedule.nextAfter(r, dueOn)
        for _ in 0..<60 {
            if data.transactions[FinanceIds.recurringOccurrence(r.uid, dueOn: next)] == nil { return next }
            next = RecurringSchedule.nextAfter(r, next)
        }
        return next
    }
}

/// Your own categories, as kortex's usecase/Categories.kt.
public enum CategoryRules {
    public static func add(name: String, kind: CategoryKind, colorToken: String, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let clean = name.cleaned else { return .failure(.blankName) }
        let sameKind = data.categories.values.filter { $0.kind == kind }
        if sameKind.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { return .failure(.nameTaken) }
        let now = clock.nowMillis
        let c = Category(uid: FinanceIds.random(), name: clean, kind: kind, colorToken: colorToken, builtIn: false,
                         sortOrder: (sameKind.map(\.sortOrder).max() ?? 0) + 1, createdAtMillis: now, updatedAtMillis: now)
        return .success(Change([.category(c)]))
    }

    /// Renames or recolours one of your categories; past entries follow, as they hold its uid.
    public static func update(_ uid: String, name: String, colorToken: String, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard var c = data.categories[uid] else { return .failure(.notFound) }
        guard !c.builtIn else { return .failure(.builtIn) }
        guard let clean = name.cleaned else { return .failure(.blankName) }
        if data.categories.values.contains(where: { $0.uid != uid && $0.kind == c.kind && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            return .failure(.nameTaken)
        }
        c.name = clean
        c.colorToken = colorToken
        c.updatedAtMillis = clock.nowMillis
        return .success(Change([.category(c)]))
    }

    /// Deleting never deletes entries: they, recurring payments and remembered merchants move to
    /// `moveTo`, or to Uncategorised when it's nil. Its budget is deleted too, as the phone does: a
    /// phone that pulls the category's marker deletes only the category. Budgets aren't read here, so
    /// the marker is written either way; over a missing document it's only a tombstone.
    public static func delete(_ uid: String, moveTo: String?, in data: FinanceData, clock: FinanceClock = .system) -> Result<Change, FinanceError> {
        guard let c = data.categories[uid] else { return .failure(.notFound) }
        guard !c.builtIn else { return .failure(.builtIn) }
        if let moveTo, moveTo == uid || data.categories[moveTo]?.kind != c.kind { return .failure(.invalidTarget) }
        let now = clock.nowMillis
        var writes: [RecordWrite] = []
        for var tx in data.transactions.values where tx.categoryUid == uid {
            tx.categoryUid = moveTo
            tx.updatedAtMillis = now
            writes.append(.transaction(tx))
        }
        for var r in data.recurring.values where r.categoryUid == uid {
            r.categoryUid = moveTo
            r.updatedAtMillis = now
            writes.append(.recurring(r))
        }
        for var m in data.merchants.values where m.categoryUid == uid {
            m.categoryUid = moveTo
            m.updatedAtMillis = now
            writes.append(.merchant(m))
        }
        writes.append(.delete(.budgets, uid: uid, atMillis: now))
        writes.append(.delete(.categories, uid: uid, atMillis: now))
        return .success(Change(writes))
    }
}
