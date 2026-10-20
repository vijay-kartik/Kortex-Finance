/// What recurring payments add up to (Figma: Recurring 01), as kortex's RecurringSchedule.totals.
public struct RecurringTotals: Sendable {
    public let perMonthMinor: Int64
    public let subscriptionsPerMonthMinor: Int64
    public let subscriptionCount: Int
    public let fixedPerMonthMinor: Int64
    public let fixedCount: Int
    public var perYearMinor: Int64 { perMonthMinor * 12 }
}

public extension RecurringSchedule {
    /// Paused payments aren't counted.
    static func totals(_ recurring: [Recurring]) -> RecurringTotals {
        let active = recurring.filter { !$0.paused }
        let subs = active.filter { $0.kind == .subscription }
        let fixed = active.filter { $0.kind == .fixed }
        let subsMonthly = subs.reduce(0) { $0 + perMonthMinor($1) }
        let fixedMonthly = fixed.reduce(0) { $0 + perMonthMinor($1) }
        return RecurringTotals(perMonthMinor: subsMonthly + fixedMonthly, subscriptionsPerMonthMinor: subsMonthly,
                               subscriptionCount: subs.count, fixedPerMonthMinor: fixedMonthly, fixedCount: fixed.count)
    }

    /// "monthly", "every 2 weeks".
    static func frequencyLabel(_ r: Recurring) -> String {
        if r.interval > 1 { return "every \(r.interval) \(r.frequency.unit)s" }
        return switch r.frequency { case .weekly: "weekly"; case .monthly: "monthly"; case .yearly: "yearly" }
    }

    /// "Every month", "Every 2 weeks".
    static func repeatsLabel(_ r: Recurring) -> String { repeatsLabel(r.frequency, interval: r.interval) }

    static func repeatsLabel(_ frequency: Frequency, interval: Int) -> String {
        interval > 1 ? "Every \(interval) \(frequency.unit)s" : "Every \(frequency.unit)"
    }

    static func reminderLabel(_ days: Int) -> String {
        switch days {
        case ..<0: "Off"
        case 0: "On the day"
        case 1: "1 day before"
        default: "\(days) days before"
        }
    }
}

public extension Frequency {
    /// "week", "month", "year".
    var unit: String {
        switch self { case .weekly: "week"; case .monthly: "month"; case .yearly: "year" }
    }
}

public extension RecurringKind {
    var pendingKind: PendingKind { self == .subscription ? .subscription : .fixed }
}

public extension Spending {
    /// "Added by you · 9 entries": transactions per category.
    static func entriesPerCategory(_ txs: some Sequence<Transaction>) -> [String: Int] {
        var counts: [String: Int] = [:]
        for tx in txs { if let uid = tx.categoryUid { counts[uid, default: 0] += 1 } }
        return counts
    }
}

public extension Pending {
    /// Which days of `month` money leaves on: unpaid recurring occurrences (from each payment's next
    /// due date on) and unpaid latest card bills. Feeds the Pending payments calendar.
    static func dueDays(in month: YearMonth, statements: [CardStatement], recurring: [Recurring], transactions txs: [Transaction]) -> [LocalDay: [PendingKind]] {
        var days: [LocalDay: [PendingKind]] = [:]
        for r in recurring {
            for day in RecurringSchedule.occurrences(r, until: month.lastDay, limit: 400) where day >= month.firstDay {
                days[day, default: []].append(r.kind.pendingKind)
            }
        }
        for s in Statements.latestPerCard(statements) where Statements.unpaidMinor(s, txs) > 0 && s.dueOn.isWithin(month.firstDay, month.lastDay) {
            days[s.dueOn, default: []].append(.cardBill)
        }
        return days
    }

    /// A pending row's second line: "Card bill · min ₹1,200", "Subscription · every 2 weeks", or just
    /// "Subscription" when the recurring payment isn't loaded.
    static func subtitle(_ item: PendingItem, recurring: Recurring?) -> String {
        switch item.kind {
        case .cardBill:
            return item.minDueMinor.map { "Card bill · min \(Money.format($0, wholeUnits: true))" } ?? "Card bill"
        case .subscription, .fixed:
            let kind = item.kind == .subscription ? "Subscription" : "Fixed"
            return [kind, recurring.map(RecurringSchedule.frequencyLabel)].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
