/// Everything the Mac Dashboard shows, built from synced data for one day. The same figures as
/// kortex's ui/dashboard/DashboardContract.kt (`DashboardUi.build`), plus the recent entries the
/// wider Mac layout has room for.
public struct DashboardModel: Sendable {
    public struct Pace: Sendable {
        /// Cumulative spend by the end of each day so far this month.
        public let thisMonth: [Int64]
        /// Cumulative spend for every day of last month.
        public let lastMonth: [Int64]
        public let daysInMonth: Int
        public let projectedMinor: Int64
    }

    public let today: LocalDay
    public let month: YearMonth
    public let hasAccounts: Bool
    public let totalBalanceMinor: Int64
    public let accountCount: Int
    public let pending: PendingSummary
    /// Twelve months ending this one, oldest first; Cash flow shows the last 3, 6 or 12.
    public let flows: [MonthFlow]
    public let monthToDate: MonthToDate
    /// This month's kept percent and the change in points from last month (nil without income).
    public let keptPercent: Int?
    public let keptChange: Int?
    public let pace: Pace?
    public let shares: [CategoryShare]
    public let recent: [Transaction]

    public var currentFlow: MonthFlow { flows[flows.count - 1] }
    public var leftAfterPendingMinor: Int64 { totalBalanceMinor - pending.totalMinor }

    public init(data: FinanceData, today: LocalDay) {
        let txs = Array(data.transactions.values)
        let month = today.yearMonth
        let lastMonth = month.adding(months: -1)
        let flows = Spending.monthlyFlows(txs, endMonth: month, months: 12)
        let current = flows[flows.count - 1]
        let previous = flows[flows.count - 2]

        self.today = today
        self.month = month
        hasAccounts = !data.accounts.isEmpty
        totalBalanceMinor = data.totalBalanceMinor
        accountCount = data.accounts.values.filter { $0.kind.countsInTotal && !$0.archived }.count
        pending = Pending.summary(today: today, statements: Array(data.statements.values), recurring: Array(data.recurring.values), transactions: txs)
        self.flows = flows
        monthToDate = Spending.monthToDate(txs, today: today)
        keptPercent = current.keptPercent
        keptChange = current.keptPercent.flatMap { kept in previous.keptPercent.map { kept - $0 } }

        let thisCumulative = Spending.cumulativeByDay(txs, month: month, throughDay: today.day)
        let lastCumulative = Spending.cumulativeByDay(txs, month: lastMonth)
        pace = (thisCumulative.last ?? 0) > 0 || (lastCumulative.last ?? 0) > 0
            ? Pace(thisMonth: thisCumulative, lastMonth: lastCumulative, daysInMonth: month.lengthOfMonth,
                   projectedMinor: Spending.projectedMonthEndMinor(txs, today: today))
            : nil
        shares = Spending.whereItWent(txs, categories: data.categories, from: month.firstDay, to: today)
        recent = Array(data.transactionsNewestFirst.lazy.filter { $0.type != .opening }.prefix(5))
    }
}
