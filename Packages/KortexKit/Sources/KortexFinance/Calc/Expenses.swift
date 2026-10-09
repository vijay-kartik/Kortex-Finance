import Foundation

public enum ExpensesMode: String, CaseIterable, Sendable {
    case daily = "Daily", monthly = "Monthly", yearly = "Yearly"
}

/// Which day, month or year Expenses shows. Never steps past today.
public struct ExpensesPeriod: Sendable, Hashable {
    public var mode: ExpensesMode
    public var day: LocalDay
    public var month: YearMonth
    public var year: Int

    public static func startingAt(_ today: LocalDay) -> ExpensesPeriod {
        ExpensesPeriod(mode: .monthly, day: today, month: today.yearMonth, year: today.year)
    }

    public var range: (from: LocalDay, to: LocalDay) {
        switch mode {
        case .daily: (day, day)
        case .monthly: (month.firstDay, month.lastDay)
        case .yearly: (LocalDay(year: year, month: 1, day: 1)!, LocalDay(year: year, month: 12, day: 31)!)
        }
    }

    public func previous() -> ExpensesPeriod {
        var p = self
        switch mode {
        case .daily: p.day = day.adding(days: -1)
        case .monthly: p.month = month.adding(months: -1)
        case .yearly: p.year -= 1
        }
        return p
    }

    public func next(today: LocalDay) -> ExpensesPeriod {
        var p = self
        switch mode {
        case .daily: p.day = min(day.adding(days: 1), today)
        case .monthly: p.month = min(month.adding(months: 1), today.yearMonth)
        case .yearly: p.year = min(year + 1, today.year)
        }
        return p
    }

    public func canGoNext(today: LocalDay) -> Bool {
        switch mode {
        case .daily: day < today
        case .monthly: month < today.yearMonth
        case .yearly: year < today.year
        }
    }
}

/// "What stood out" in a month: a sentence with one highlighted part, as kortex's ExpensesUi.standouts.
public struct Standout: Sendable, Hashable {
    public enum Tone: Sendable { case good, warn, neutral }
    public let before: String
    public let highlight: String
    public let after: String
    public let tone: Tone
}

public enum ExpensesInsights {
    /// The biggest category, against last month, the biggest single spend, recurring payments made.
    /// `to` is today for the current month, else the month's last day.
    public static func standouts(_ data: FinanceData, month: YearMonth, to: LocalDay, today: LocalDay,
                                 money: (Int64, Bool) -> String, monthName: (YearMonth) -> String, dayName: (LocalDay) -> String) -> [Standout] {
        let from = month.firstDay
        let last = month.adding(months: -1)
        // One pass over all of history down to the days compared below (this month, last month,
        // last month to today's date); every sum after that runs over just those.
        let windowFrom = min(last.firstDay, today.yearMonth.adding(months: -1).firstDay)
        let windowTo = max(to, last.lastDay)
        let txs = data.transactions.values.filter { $0.occurredOn.isWithin(windowFrom, windowTo) }
        let spent = Spending.spentMinor(txs, from: from, to: to)
        guard spent > 0 else { return [] }
        var out: [Standout] = []
        if let top = Spending.whereItWent(txs, categories: data.categories, from: from, to: to).first(where: { $0.category != nil }) {
            out.append(Standout(before: "\(top.category!.name) was ", highlight: "\(top.percent)%",
                                after: " of what you spent — \(money(top.amountMinor, true)).", tone: .neutral))
        }
        let lastSpent = to == today ? Spending.monthToDate(txs, today: today).lastMonthMinor : Spending.month(txs, last).spentMinor
        if lastSpent > 0 {
            let change = Int((Double(spent - lastSpent) * 100 / Double(lastSpent)).rounded())
            let by = to == today ? " by the same date." : "."
            if change < 0 {
                out.append(Standout(before: "", highlight: "\(-change)% less", after: " than \(monthName(last))\(by)", tone: .good))
            } else if change > 0 {
                out.append(Standout(before: "", highlight: "\(change)% more", after: " than \(monthName(last))\(by)", tone: .warn))
            } else {
                out.append(Standout(before: "", highlight: "The same", after: " as \(monthName(last))\(by)", tone: .neutral))
            }
        }
        let expenses = Spending.expenses(txs, from: from, to: to)
        if let biggest = expenses.max(by: { $0.amountMinor < $1.amountMinor }) {
            let what = biggest.merchant ?? biggest.note ?? biggest.categoryUid.flatMap { data.categories[$0]?.name } ?? "an expense"
            out.append(Standout(before: "Biggest single spend: \(what), ", highlight: money(biggest.amountMinor, false),
                                after: " on \(dayName(biggest.occurredOn)).", tone: .neutral))
        }
        let recurring = expenses.filter { $0.recurringUid != nil }
        if !recurring.isEmpty {
            let noun = recurring.count == 1 ? "recurring payment" : "recurring payments"
            out.append(Standout(before: "\(recurring.count) \(noun) made for ", highlight: money(recurring.reduce(0) { $0 + $1.amountMinor }, false),
                                after: ".", tone: .neutral))
        }
        return out
    }
}
