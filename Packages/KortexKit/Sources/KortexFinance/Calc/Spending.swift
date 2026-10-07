/// One month's bars in Cash flow.
public struct MonthFlow: Sendable, Hashable {
    public let month: YearMonth
    public let inMinor: Int64
    public let outMinor: Int64

    public var netMinor: Int64 { inMinor - outMinor }

    /// "You kept 41%": what's left of income, 0–100 rounded; nil with no income.
    public var keptPercent: Int? {
        inMinor > 0 ? Int(roundDiv(netMinor * 100, inMinor)) : nil
    }
}

public struct PeriodSummary: Sendable, Hashable {
    public let spentMinor: Int64
    public let incomeMinor: Int64

    public var savingsMinor: Int64 { incomeMinor - spentMinor }
    public var savingsRate: Double? { incomeMinor > 0 ? Double(savingsMinor) / Double(incomeMinor) : nil }
}

/// This month so far against last month by the same day: "₹438 less than August by day 29".
public struct MonthToDate: Sendable, Hashable {
    public let day: Int
    public let thisMonthMinor: Int64
    public let lastMonthMinor: Int64

    /// Negative: spent less than last month.
    public var deltaMinor: Int64 { thisMonthMinor - lastMonthMinor }
}

/// A slice of Where it went. `category` is nil for Other, which also holds Uncategorised.
public struct CategoryShare: Sendable, Hashable {
    public let category: Category?
    public let amountMinor: Int64
    public let percent: Int
}

/// Spending and income totals, as kortex's calc/Spending.kt. Only EXPENSE is spending and only INCOME
/// is income: OPENING, TRANSFER and CARD_PAYMENT move money between your own accounts.
public enum Spending {
    public static func expenses(_ txs: [Transaction], from: LocalDay, to: LocalDay) -> [Transaction] {
        txs.filter { $0.type == .expense && $0.occurredOn.isWithin(from, to) }
    }

    public static func spentMinor(_ txs: [Transaction], from: LocalDay, to: LocalDay) -> Int64 {
        expenses(txs, from: from, to: to).reduce(0) { $0 + $1.amountMinor }
    }

    public static func incomeMinor(_ txs: [Transaction], from: LocalDay, to: LocalDay) -> Int64 {
        txs.filter { $0.type == .income && $0.occurredOn.isWithin(from, to) }.reduce(0) { $0 + $1.amountMinor }
    }

    public static func period(_ txs: [Transaction], from: LocalDay, to: LocalDay) -> PeriodSummary {
        PeriodSummary(spentMinor: spentMinor(txs, from: from, to: to), incomeMinor: incomeMinor(txs, from: from, to: to))
    }

    public static func month(_ txs: [Transaction], _ month: YearMonth) -> PeriodSummary {
        period(txs, from: month.firstDay, to: month.lastDay)
    }

    /// The Cash flow chart: `months` months ending with `endMonth`, oldest first.
    public static func monthlyFlows(_ txs: [Transaction], endMonth: YearMonth, months: Int = 6) -> [MonthFlow] {
        (0..<months).reversed().map { back in
            let m = endMonth.adding(months: -back)
            let summary = month(txs, m)
            return MonthFlow(month: m, inMinor: summary.incomeMinor, outMinor: summary.spentMinor)
        }
    }

    /// Days 1…N of this month against days 1…min(N, its length) of last month, N being today's day.
    public static func monthToDate(_ txs: [Transaction], today: LocalDay) -> MonthToDate {
        let lastMonth = today.yearMonth.adding(months: -1)
        return MonthToDate(
            day: today.day,
            thisMonthMinor: spentMinor(txs, from: today.yearMonth.firstDay, to: today),
            lastMonthMinor: spentMinor(txs, from: lastMonth.firstDay, to: lastMonth.day(today.day))
        )
    }

    /// Spending so far by the end of each day of `month`, days 1…`throughDay` (Pace vs last month).
    public static func cumulativeByDay(_ txs: [Transaction], month: YearMonth, throughDay: Int? = nil) -> [Int64] {
        let days = min(max(throughDay ?? month.lengthOfMonth, 0), month.lengthOfMonth)
        var perDay = [Int64](repeating: 0, count: days)
        for tx in expenses(txs, from: month.firstDay, to: month.lastDay) where tx.occurredOn.day - 1 < days {
            perDay[tx.occurredOn.day - 1] += tx.amountMinor
        }
        var running: Int64 = 0
        return perDay.map { running += $0; return running }
    }

    /// "At this pace, month ends near ₹3,290": spent so far ÷ days gone × days in the month.
    public static func projectedMonthEndMinor(_ txs: [Transaction], today: LocalDay) -> Int64 {
        let spent = spentMinor(txs, from: today.yearMonth.firstDay, to: today)
        return roundDiv(spent * Int64(today.yearMonth.lengthOfMonth), Int64(today.day))
    }

    /// Where it went: the `top` biggest categories by spend, then Other for the rest and
    /// Uncategorised. Percentages add up to exactly 100.
    public static func whereItWent(_ txs: [Transaction], categories: [String: Category], from: LocalDay, to: LocalDay, top: Int = 4) -> [CategoryShare] {
        var totals: [String?: Int64] = [:]
        for tx in expenses(txs, from: from, to: to) {
            let key = tx.categoryUid.flatMap { categories[$0] == nil ? nil : $0 }
            totals[key, default: 0] += tx.amountMinor
        }
        let named = totals.compactMap { key, value in key.map { ($0, value) } }.sorted { $0.1 > $1.1 }
        let shown = named.prefix(top)
        let otherMinor = (totals[nil] ?? 0) + named.dropFirst(top).reduce(0) { $0 + $1.1 }
        var slices: [(Category?, Int64)] = shown.map { (categories[$0.0], $0.1) }
        if otherMinor > 0 { slices.append((nil, otherMinor)) }
        let percents = roundedPercents(slices.map(\.1))
        return slices.enumerated().map { i, slice in CategoryShare(category: slice.0, amountMinor: slice.1, percent: percents[i]) }
    }
}
