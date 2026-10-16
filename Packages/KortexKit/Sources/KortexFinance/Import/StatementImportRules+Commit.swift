import Foundation

// MARK: Saving

extension StatementImportRules {
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
        if let opening = openingEntry(draft, clock: clock, now: now) { writes.append(.transaction(opening)) }

        // A row that repeats is saved as the occurrence it pays (`rec_…`, as Mark paid writes it), so
        // an occurrence the phone already recorded is replaced by the statement's row, not doubled.
        let started = startedPayments(draft, now: now)
        var payments = Dictionary(uniqueKeysWithValues: started.payments.map { ($0.uid, $0) })
        working.apply(started.payments.map { RemoteRow.live($0) })
        var paid: Set<String> = []
        var lastDue: [String: LocalDay] = [:]

        var merchants: [String: Merchant] = [:]
        for row in draft.rows where row.include {
            if row.kind == .cardPayment && draft.account.kind != .creditCard && row.cardUid == nil { return .failure(.cardPaymentNeedsCard) }
            if row.kind.isTransfer && row.transferAccountUid == nil { return .failure(.transferNeedsAccount) }
            let moved = replacedEntry(for: row, of: draft, in: data)
            // A debit turned into the payment or transfer keeps the day the money left.
            let movedDebit = moved?.type == .expense ? moved : nil
            var uid = moved?.uid ?? importedEntryUid(accountUid: draft.accountUid, key: row.key)
            var paying = payment(paidBy: row, started: started.byRow, payments: payments, in: data)
            var dueOn: LocalDay?
            if let r = paying, let due = occurrence(of: r, paidBy: row, paid: &paid) {
                dueOn = due
                uid = FinanceIds.recurringOccurrence(r.uid, dueOn: due)
                payments[r.uid] = r
                lastDue[r.uid] = max(lastDue[r.uid] ?? due, due)
            } else {
                paying = nil
            }
            let entry = entryDraft(row, of: draft, replacing: moved, paying: paying, dueOn: dueOn, uid: uid, in: data, clock: clock)
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
        writes.append(contentsOf: advancePayments(payments, started: started.byRow, lastDue: lastDue, paid: paid, in: data, now: now)
            .map { .recurring($0) })
        if let bill = newBill(draft, in: data, now: now) { writes.append(.statement(bill)) }
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

    /// A new account's opening entry on the statement's first day, when it opens with money in it (a
    /// card, owing). An account you have keeps its own.
    private static func openingEntry(_ draft: StatementImport, clock: FinanceClock, now: Int64) -> Transaction? {
        let opening = max(draft.openingMinor, 0)
        guard !draft.intoExisting && opening > 0 else { return nil }
        return Transaction(
            uid: "imp_" + FinanceIds.hash("\(draft.accountUid)|opening"), type: .opening, amountMinor: opening, currency: "INR",
            occurredAtMillis: clock.millisOn(draft.openingOn), occurredOn: draft.openingOn, accountUid: draft.accountUid,
            toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .statement, sourceRef: nil,
            recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: now, updatedAtMillis: now
        )
    }

    /// The card a card payment row pays: this one on a card's statement, the row's on a bank's.
    private static func cardPaid(by row: ImportRow, of draft: StatementImport) -> String? {
        guard row.kind == .cardPayment else { return nil }
        return draft.account.kind == .creditCard ? draft.accountUid : row.cardUid
    }

    /// Where a row's money comes from and goes to: this account, unless the row says otherwise.
    private static func endpoints(of row: ImportRow, in draft: StatementImport) -> (from: String, to: String?) {
        switch row.kind {
        case .cardPayment:
            let from = draft.account.kind == .creditCard ? (row.fromAccountUid ?? FinanceIds.unknownAccount) : draft.accountUid
            return (from, cardPaid(by: row, of: draft))
        case .cardCredit: return (FinanceIds.cardCredit, draft.accountUid)
        case .transferOut: return (draft.accountUid, row.transferAccountUid)
        case .transferIn: return (row.transferAccountUid ?? "", draft.accountUid)
        case .expense, .income: return (draft.accountUid, nil)
        }
    }

    /// This entry as Kortex already has it: the card's payment recorded from another account, a
    /// bank's debit saved as money out before the card was in Kortex, or the other account's side of
    /// a transfer saved as money in or out. Each becomes this entry.
    private static func replacedEntry(for row: ImportRow, of draft: StatementImport, in data: FinanceData) -> Transaction? {
        guard let tx = row.replaces.flatMap({ data.transactions[$0] }) else { return nil }
        let ledger = Balances.ledger(of: tx.accountUid, in: data.accounts)
        switch row.kind {
        case .cardPayment:
            if tx.type == .cardPayment { return tx.toAccountUid == cardPaid(by: row, of: draft) ? tx : nil }
            return draft.account.kind == .creditCard && tx.type == .expense && tx.recurringUid == nil && ledger == row.fromAccountUid ? tx : nil
        case .transferOut: return tx.type == .income && ledger == row.transferAccountUid ? tx : nil
        case .transferIn: return tx.type == .expense && tx.recurringUid == nil && ledger == row.transferAccountUid ? tx : nil
        case .expense, .income, .cardCredit: return nil
        }
    }

    /// The recurring payment an expense pays: the one it starts, or the one you have that it was marked as paying.
    private static func payment(paidBy row: ImportRow, started: [Int: String], payments: [String: Recurring], in data: FinanceData) -> Recurring? {
        guard row.kind == .expense else { return nil }
        switch row.repeats {
        case .no: return nil
        case .new: return started[row.id].flatMap { payments[$0] }
        case .pays(let uid): return payments[uid] ?? data.recurring[uid]
        }
    }

    /// The due date of the occurrence a row pays: the one nearest its date. Two rows for one due date:
    /// the second stays a plain entry, so it pays none.
    private static func occurrence(of r: Recurring, paidBy row: ImportRow, paid: inout Set<String>) -> LocalDay? {
        let due = RecurringSchedule.nearestDue(r, to: row.date)
        return paid.insert(FinanceIds.recurringOccurrence(r.uid, dueOn: due)).inserted ? due : nil
    }

    private static func transactionType(of kind: ImportRow.Kind) -> TransactionType {
        switch kind {
        case .cardPayment, .cardCredit: .cardPayment
        case .transferOut, .transferIn: .transfer
        case .income: .income
        case .expense: .expense
        }
    }

    /// The entry a row is saved as, under `uid`.
    private static func entryDraft(_ row: ImportRow, of draft: StatementImport, replacing moved: Transaction?, paying: Recurring?,
                                   dueOn: LocalDay?, uid: String, in data: FinanceData, clock: FinanceClock) -> TransactionDraft {
        let (fromUid, toUid) = endpoints(of: row, in: draft)
        let movedDebit = moved?.type == .expense ? moved : nil
        return TransactionDraft(
            type: transactionType(of: row.kind),
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
            statementUid: cardPaid(by: row, of: draft).flatMap { moved?.statementUid ?? billPaid($0, on: movedDebit?.occurredOn ?? row.date, in: data)?.uid },
            // Derived from the import, so saving it twice writes the same documents.
            uid: uid
        )
    }

    /// New payments, and existing ones whose next due date the statement has now paid, moved on to the
    /// first occurrence not paid by this import or already. Existing payments it didn't pay are left out.
    private static func advancePayments(_ payments: [String: Recurring], started: [Int: String], lastDue: [String: LocalDay],
                                        paid: Set<String>, in data: FinanceData, now: Int64) -> [Recurring] {
        var advanced: [Recurring] = []
        for (uid, var r) in payments.sorted(by: { $0.key < $1.key }) {
            let isNew = started.values.contains(uid)
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
            advanced.append(r)
        }
        return advanced
    }

    /// The card's bill on this statement, unless the card already has it, from the phone or an earlier import.
    private static func newBill(_ draft: StatementImport, in data: FinanceData, now: Int64) -> CardStatement? {
        guard let bill = draft.bill, !billExists(draft, in: data) else { return nil }
        return CardStatement(
            uid: FinanceIds.statement(cardUid: draft.accountUid, statementOn: bill.statementOn), cardUid: draft.accountUid,
            periodStart: bill.periodStart ?? bill.statementOn.adding(days: -30), statementOn: bill.statementOn, dueOn: bill.dueOn,
            totalDueMinor: bill.totalMinor, minDueMinor: bill.minMinor, source: .manual, createdAtMillis: now, updatedAtMillis: now
        )
    }

    /// Whether the card already has a bill for this statement.
    public static func billExists(_ draft: StatementImport, in data: FinanceData) -> Bool {
        guard draft.intoExisting, let bill = draft.bill else { return false }
        return data.statements.values.contains { $0.cardUid == draft.accountUid && abs($0.statementOn.days(to: bill.statementOn)) <= matchWindowDays }
    }
}
