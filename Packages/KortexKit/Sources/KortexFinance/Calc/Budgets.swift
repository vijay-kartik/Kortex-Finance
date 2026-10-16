/// One budgeted expense category's month: "Food ₹3,200 of ₹4,000 · 80%".
public struct CategoryBudget: Sendable, Hashable {
    public let categoryUid: String
    public let name: String
    public let budgetMinor: Int64
    public let spentMinor: Int64
    /// At this pace, what the month ends near; just `spentMinor` once the month is over.
    public let projectedMinor: Int64

    /// Negative: over budget.
    public var leftMinor: Int64 { budgetMinor - spentMinor }

    /// Spent ÷ budget, rounded; can go past 100.
    public var percentUsed: Int { Int(roundDiv(spentMinor * 100, budgetMinor)) }
}

/// The whole month against the sum of the category budgets.
public struct BudgetTotals: Sendable, Hashable {
    public let budgetMinor: Int64
    public let spentMinor: Int64
    public let projectedMinor: Int64

    /// Negative: over budget.
    public var leftMinor: Int64 { budgetMinor - spentMinor }

    /// Spent ÷ budget, rounded; can go past 100.
    public var percentUsed: Int { Int(roundDiv(spentMinor * 100, budgetMinor)) }
}

/// `overall` is nil when no category has a budget: the month isn't budgeted.
public struct BudgetSummary: Sendable, Hashable {
    public let categories: [CategoryBudget]
    public let overall: BudgetTotals?
}

/// Category budgets against the month's spend, as kortex's calc/Budgets.kt. Spend counts as in
/// `Spending.whereItWent`: expenses only, so transfers and card bills never count. Uncategorised spend
/// and spend in a category with no budget are left out, and the overall budget is the sum of the
/// category budgets.
public enum Budgets {
    /// `budgets` maps a category's uid to its monthly amount. Budgets for income categories, unknown
    /// categories or amounts of zero or less are ignored. Categories come most-used first.
    public static func status(_ txs: [Transaction], categories: [Category], budgets: [String: Int64],
                              month: YearMonth, today: LocalDay) -> BudgetSummary {
        let budgeted = categories.filter { $0.kind == .expense && (budgets[$0.uid] ?? 0) > 0 }
        if budgeted.isEmpty { return BudgetSummary(categories: [], overall: nil) }
        let expenses = Spending.expenses(txs, from: month.firstDay, to: month.lastDay)
        var spent: [String: Int64] = [:], paced: [String: Int64] = [:]
        for tx in expenses {
            guard let uid = tx.categoryUid else { continue }
            spent[uid, default: 0] += tx.amountMinor
            if tx.occurredOn <= today { paced[uid, default: 0] += tx.amountMinor }
        }
        let pace = pace(month, today)

        func projected(_ spentMinor: Int64, _ pacedMinor: Int64) -> Int64 {
            guard let pace else { return spentMinor }
            return max(spentMinor, roundDiv(pacedMinor * Int64(pace.days), Int64(pace.gone)))
        }

        let rows = budgeted.map { c in
            let spentMinor = spent[c.uid] ?? 0
            return CategoryBudget(categoryUid: c.uid, name: c.name, budgetMinor: budgets[c.uid]!, spentMinor: spentMinor,
                                  projectedMinor: projected(spentMinor, paced[c.uid] ?? 0))
        }.sorted {
            let (a, b) = (Double($0.spentMinor) / Double($0.budgetMinor), Double($1.spentMinor) / Double($1.budgetMinor))
            return a != b ? a > b : $0.name < $1.name
        }
        let spentMinor = rows.reduce(0) { $0 + $1.spentMinor }
        let overall = BudgetTotals(
            budgetMinor: rows.reduce(0) { $0 + $1.budgetMinor },
            spentMinor: spentMinor,
            projectedMinor: projected(spentMinor, budgeted.reduce(0) { $0 + (paced[$1.uid] ?? 0) })
        )
        return BudgetSummary(categories: rows, overall: overall)
    }

    /// The same, with `data`'s categories and budgets.
    public static func status(_ data: FinanceData, month: YearMonth, today: LocalDay) -> BudgetSummary {
        status(Array(data.transactions.values), categories: Array(data.categories.values),
               budgets: data.budgets.mapValues(\.amountMinor), month: month, today: today)
    }

    /// Days in `month` to days gone, the same pace as `Spending.projectedMonthEndMinor`, while `today`
    /// is in `month`. Nil for a month that's over or hasn't started: nothing left to project.
    private static func pace(_ month: YearMonth, _ today: LocalDay) -> (days: Int, gone: Int)? {
        today.yearMonth == month ? (month.lengthOfMonth, today.day) : nil
    }
}
