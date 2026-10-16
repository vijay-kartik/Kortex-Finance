import Foundation

// MARK: Reconciling with an account you have

extension StatementImportRules {
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
    static func sameReference(_ row: ImportRow, _ tx: Transaction) -> Bool {
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
}
