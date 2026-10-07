/// Credit card bills: what's paid and what's left, as kortex's calc/Statements.kt.
public enum Statements {
    public static func paidMinor(_ statement: CardStatement, _ txs: [Transaction]) -> Int64 {
        txs.filter { $0.type == .cardPayment && $0.statementUid == statement.uid }.reduce(0) { $0 + $1.amountMinor }
    }

    public static func unpaidMinor(_ statement: CardStatement, _ txs: [Transaction]) -> Int64 {
        max(statement.totalDueMinor - paidMinor(statement, txs), 0)
    }

    /// Each card's latest statement. An older one is never pending on its own: whatever was left
    /// unpaid on it was still owed on the next statement day, so the newer bill includes it.
    public static func latestPerCard(_ statements: [CardStatement]) -> [CardStatement] {
        Dictionary(grouping: statements, by: \.cardUid).values.compactMap { $0.max { $0.statementOn < $1.statementOn } }
    }
}

/// When recurring payments fall due, as kortex's calc/RecurringSchedule.kt.
public enum RecurringSchedule {
    /// The occurrence after `dueOn`, keeping to the anchor day (a 31st falls on the 30th, then back on the 31st).
    public static func nextAfter(_ r: Recurring, _ dueOn: LocalDay) -> LocalDay {
        let step = max(r.interval, 1)
        switch r.frequency {
        case .weekly: return dueOn.adding(days: 7 * step).nextOrSame(isoWeekday: min(max(r.anchorDay, 1), 7))
        case .monthly: return dueOn.yearMonth.adding(months: step).day(r.anchorDay)
        case .yearly: return dueOn.yearMonth.adding(months: 12 * step).day(r.anchorDay)
        }
    }

    /// Unpaid occurrences from `nextDueOn` up to and including `until`; the first may be overdue. None while paused.
    public static func occurrences(_ r: Recurring, until: LocalDay, limit: Int = 60) -> [LocalDay] {
        guard !r.paused else { return [] }
        var days: [LocalDay] = []
        var day = r.nextDueOn
        while day <= until, days.count < limit {
            days.append(day)
            day = nextAfter(r, day)
        }
        return days
    }

    /// The scheduled day nearest `day`: the occurrence a payment made on `day` pays, a few days early or late.
    public static func nearestDue(_ r: Recurring, to day: LocalDay) -> LocalDay {
        let candidates: [LocalDay] = switch r.frequency {
        case .weekly: [day.adding(days: -3).nextOrSame(isoWeekday: min(max(r.anchorDay, 1), 7))]
        case .monthly: (-1...1).map { day.yearMonth.adding(months: $0).day(r.anchorDay) }
        case .yearly: (-1...1).map { YearMonth(year: day.year + $0, month: r.nextDueOn.month).day(r.anchorDay) }
        }
        return candidates.min { abs(day.days(to: $0)) < abs(day.days(to: $1)) }!
    }

    /// Monthly as is, weekly × 52 ÷ 12, yearly ÷ 12, each divided by its interval.
    public static func perMonthMinor(_ r: Recurring) -> Int64 {
        let interval = Int64(max(r.interval, 1))
        switch r.frequency {
        case .weekly: return roundDiv(r.amountMinor * 52, 12 * interval)
        case .monthly: return roundDiv(r.amountMinor, interval)
        case .yearly: return roundDiv(r.amountMinor, 12 * interval)
        }
    }
}

public enum PendingKind: Sendable { case cardBill, subscription, fixed }

/// How a due date is coloured: Amber within 7 days, Alarm once past due.
public enum DueUrgency: Sendable { case later, soon, overdue }

/// One row in Pending payments.
public struct PendingItem: Sendable, Hashable, Identifiable {
    public let kind: PendingKind
    /// The statement's or recurring payment's uid.
    public let sourceUid: String
    /// Netflix; for a card bill, the card's uid (show the card's name).
    public let title: String
    public let amountMinor: Int64
    public let dueOn: LocalDay
    /// Card bills only.
    public let minDueMinor: Int64?
    public var id: String { "\(sourceUid)@\(dueOn)" }
}

public struct PendingSummary: Sendable {
    /// By due date, soonest first.
    public let items: [PendingItem]
    public let cardBillsMinor: Int64
    public let cardBillCount: Int
    public let recurringMinor: Int64
    public let recurringCount: Int

    public var totalMinor: Int64 { cardBillsMinor + recurringMinor }
    public var count: Int { items.count }
}

/// Pending payments, as kortex's calc/Pending.kt.
public enum Pending {
    public static let horizonDays = 30
    public static let soonDays = 7

    /// Each card's unpaid latest bill and every recurring occurrence due within `horizonDays` of
    /// `today`, including overdue ones. A weekly payment can appear several times.
    public static func summary(today: LocalDay, statements: [CardStatement], recurring: [Recurring], transactions txs: [Transaction], horizonDays: Int = horizonDays) -> PendingSummary {
        let until = today.adding(days: horizonDays)
        let bills: [PendingItem] = Statements.latestPerCard(statements).compactMap { s in
            let unpaid = Statements.unpaidMinor(s, txs)
            guard unpaid > 0, s.dueOn <= until else { return nil }
            return PendingItem(kind: .cardBill, sourceUid: s.uid, title: s.cardUid, amountMinor: unpaid, dueOn: s.dueOn,
                               minDueMinor: max(s.minDueMinor - Statements.paidMinor(s, txs), 0))
        }
        struct Occurrence: Hashable { let uid: String; let dueOn: LocalDay? }
        let paid = Set(txs.compactMap { tx in tx.recurringUid.map { Occurrence(uid: $0, dueOn: tx.dueOn) } })
        let occurrences: [PendingItem] = recurring.flatMap { payment in
            RecurringSchedule.occurrences(payment, until: until)
                .filter { !paid.contains(Occurrence(uid: payment.uid, dueOn: $0)) }
                .map { PendingItem(kind: payment.kind == .subscription ? .subscription : .fixed, sourceUid: payment.uid,
                                   title: payment.name, amountMinor: payment.amountMinor, dueOn: $0, minDueMinor: nil) }
        }
        return PendingSummary(
            items: (bills + occurrences).sorted { ($0.dueOn, $0.title) < ($1.dueOn, $1.title) },
            cardBillsMinor: bills.reduce(0) { $0 + $1.amountMinor },
            cardBillCount: bills.count,
            recurringMinor: occurrences.reduce(0) { $0 + $1.amountMinor },
            recurringCount: occurrences.count
        )
    }

    public static func urgency(_ dueOn: LocalDay, today: LocalDay) -> DueUrgency {
        if dueOn < today { return .overdue }
        return today.days(to: dueOn) <= soonDays ? .soon : .later
    }
}
