import Foundation

// MARK: Transfers between your accounts

extension StatementImportRules {
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
}
