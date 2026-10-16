import Foundation

// MARK: Recurring

extension StatementImportRules {
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
}
