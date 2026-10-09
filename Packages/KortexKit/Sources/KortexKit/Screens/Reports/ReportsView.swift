import AppKit
import KortexFinance
import SwiftUI
import UniformTypeIdentifiers

/// Reports (Figma: Mac · Monthly report). A month's or a year's income against spending, the savings
/// rate, where it went against the period before, the largest entries and spend over time.
/// Export PDF… saves the same layout through the Save panel.
struct ReportsView: View {
    let finance: any FinanceStore
    @Bindable var model: AppModel

    var body: some View {
        let today = LocalDay.today()
        let report = Report(data: finance.data, period: reportPeriod, today: today)
        ScrollView {
            ReportContent(report: report).padding(24)
        }
        .background(Color.kVoid)
        .navigationTitle(report.title)
        .navigationSubtitle(reportPeriod.mode == .yearly ? "Yearly report" : "Monthly report")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    Picker("Period", selection: Binding(
                        get: { model.reportPeriod.mode == .yearly ? ExpensesMode.yearly : .monthly },
                        set: { model.reportPeriod.mode = $0 }
                    )) {
                        Text("Month").tag(ExpensesMode.monthly)
                        Text("Year").tag(ExpensesMode.yearly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    ControlGroup {
                        Button { model.reportPeriod = reportPeriod.previous() } label: { Image(systemName: "chevron.left") }
                            .keyboardShortcut("[", modifiers: .command)
                        Button { model.reportPeriod = reportPeriod.next(today: today) } label: { Image(systemName: "chevron.right") }
                            .keyboardShortcut("]", modifiers: .command)
                            .disabled(!reportPeriod.canGoNext(today: today))
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { export(report) } label: { Label("Export PDF…", systemImage: "square.and.arrow.up") }
                    .labelStyle(.titleAndIcon)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    /// Reports shows months or years only.
    private var reportPeriod: ExpensesPeriod {
        var p = model.reportPeriod
        if p.mode == .daily { p.mode = .monthly }
        return p
    }

    @MainActor private func export(_ report: Report) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Kortex \(report.title).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content:
            ReportContent(report: report)
                .padding(32)
                .frame(width: 1100)
                .background(Color.kVoid)
                .environment(\.colorScheme, .dark)
        )
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
    }
}

/// Every figure on the report for one month or year, as kortex's MonthlyReportUi plus the Mac extras.
struct Report {
    let title: String
    let isYear: Bool
    let summary: PeriodSummary
    let shares: [CategoryShare]
    /// The same categories' spend in the period before, by category uid ("" for Other).
    let previousByCategory: [String: Int64]
    let previousName: String
    let largest: [Entry]
    /// Spend per day (month) or per month (year), with labels.
    let buckets: [(label: String, minor: Int64)]
    let data: FinanceData

    init(data: FinanceData, period: ExpensesPeriod, today: LocalDay) {
        let txs = Array(data.transactions.values)
        self.data = data
        isYear = period.mode == .yearly
        let from: LocalDay, to: LocalDay, prevFrom: LocalDay, prevTo: LocalDay
        if isYear {
            from = LocalDay(year: period.year, month: 1, day: 1)!
            to = period.year == today.year ? today : LocalDay(year: period.year, month: 12, day: 31)!
            prevFrom = LocalDay(year: period.year - 1, month: 1, day: 1)!
            prevTo = LocalDay(year: period.year - 1, month: 12, day: 31)!
            title = String(period.year)
            previousName = String(period.year - 1)
            let monthsShown = period.year == today.year ? today.month : 12
            buckets = (1...monthsShown).map { m in
                let ym = YearMonth(year: period.year, month: m)
                return (Format.monthShort(ym), Spending.spentMinor(txs, from: ym.firstDay, to: ym.lastDay))
            }
        } else {
            let month = period.month
            from = month.firstDay
            to = month == today.yearMonth ? today : month.lastDay
            prevFrom = month.adding(months: -1).firstDay
            prevTo = month.adding(months: -1).lastDay
            title = month.date.formatted(.dateTime.month(.wide).year())
            previousName = Format.monthName(month.adding(months: -1))
            buckets = (1...to.day).map { d in ("\(d)", Spending.spentMinor(txs, from: month.day(d), to: month.day(d))) }
        }
        summary = Spending.period(txs, from: from, to: to)
        shares = Spending.whereItWent(txs, categories: data.categories, from: from, to: to)
        var prev: [String: Int64] = [:]
        let shownUids = Set(shares.compactMap { $0.category?.uid })
        for tx in Spending.expenses(txs, from: prevFrom, to: prevTo) {
            let key = tx.categoryUid.flatMap { shownUids.contains($0) ? $0 : nil } ?? ""
            prev[key, default: 0] += tx.amountMinor
        }
        previousByCategory = prev
        largest = Array(Spending.expenses(txs, from: from, to: to).sorted { $0.amountMinor > $1.amountMinor }.prefix(5))
    }

    var savingsPercent: Int? { summary.savingsRate.map { Int(($0 * 100).rounded()) } }

    var savingsHeadline: String {
        guard let p = savingsPercent else { return "No income recorded" }
        switch p {
        case 30...: return "Healthy savings rate"
        case 10...: return "Steady savings rate"
        case 0...: return "Low savings rate"
        default: return "Spent more than you earned"
        }
    }

    var savingsLine: String {
        guard savingsPercent != nil else { return "Add income to see how much of it you kept." }
        return summary.savingsMinor >= 0
            ? "You saved \(Money.format(summary.savingsMinor)) of your income \(isYear ? "this year" : "this month")."
            : "You spent \(Money.format(-summary.savingsMinor)) more than came in."
    }
}

struct ReportContent: View {
    let report: Report

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                incomeVsExpenses
                savingsRate.frame(width: 400)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                whereItWent
                largest.frame(width: 400)
            }
            .fixedSize(horizontal: false, vertical: true)
            spendOverTime
        }
    }

    private var incomeVsExpenses: some View {
        let s = report.summary
        let peak = max(s.incomeMinor, s.spentMinor, 1)
        return KCard(spacing: 14) {
            CardHeader("Income vs Expenses")
            bar("Total income", s.incomeMinor, peak, .kGrowth)
            bar("Total expenses", s.spentMinor, peak, .kAlarm)
        }
    }

    private func bar(_ label: String, _ minor: Int64, _ peak: Int64, _ color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label).font(.grotesk(13)).foregroundStyle(Color.kMuted)
                Spacer()
                Text(Money.format(minor)).font(.mono(14)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.kRaised)
                    if minor > 0 { Capsule().fill(color).frame(width: max(8, geo.size.width * CGFloat(minor) / CGFloat(peak))) }
                }
            }
            .frame(height: 10)
        }
    }

    private var savingsRate: some View {
        let percent = report.savingsPercent
        let fraction = CGFloat(max(min(Double(percent ?? 0) / 100, 1), 0))
        let color: Color = (percent ?? 0) >= 10 ? .kGrowth : (percent ?? 0) >= 0 ? .kAmber : .kAlarm
        return KCard(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.kRaised, lineWidth: 9)
                    Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(percent.map { "\(max($0, 0))%" } ?? "—").font(.mono(14)).foregroundStyle(Color.kInk)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Savings rate").font(.grotesk(16, .medium)).foregroundStyle(Color.kInk)
                    Text(report.savingsHeadline).font(.grotesk(13)).foregroundStyle(color)
                    Text(report.savingsLine).font(.grotesk(12)).foregroundStyle(Color.kMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var whereItWent: some View {
        KCard(spacing: 10) {
            CardHeader(title: "Where it went") {
                Text("vs \(report.previousName)").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            if report.shares.isEmpty {
                Text("No spending in this period.").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            } else {
                ShareBar(shares: report.shares, height: 10)
                HStack(spacing: 12) {
                    Text("CATEGORY").sectionLabelStyle().frame(maxWidth: .infinity, alignment: .leading)
                    Text("SHARE").sectionLabelStyle().frame(width: 56, alignment: .trailing)
                    Text(report.isYear ? "THIS YEAR" : "THIS MONTH").sectionLabelStyle().frame(width: 110, alignment: .trailing)
                    Text(report.previousName.uppercased()).sectionLabelStyle().frame(width: 110, alignment: .trailing)
                    Text("CHANGE").sectionLabelStyle().frame(width: 64, alignment: .trailing)
                }
                .padding(.top, 6)
                ForEach(Array(report.shares.enumerated()), id: \.offset) { _, s in
                    let previous = report.previousByCategory[s.category?.uid ?? ""] ?? 0
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Circle().fill(Color.category(s.category)).frame(width: 8, height: 8)
                                Text(s.category?.name ?? "Other").font(.grotesk(13)).foregroundStyle(Color.kInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(s.percent)%").font(.mono(12)).foregroundStyle(Color.kMuted).frame(width: 56, alignment: .trailing)
                            Text(Money.format(s.amountMinor)).font(.mono(13)).foregroundStyle(Color.kInk).frame(width: 110, alignment: .trailing)
                            Text(Money.format(previous)).font(.mono(13)).foregroundStyle(Color.kMuted).frame(width: 110, alignment: .trailing)
                            change(s.amountMinor, previous).frame(width: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private func change(_ now: Int64, _ before: Int64) -> some View {
        guard before > 0 else { return Text("new").font(.mono(12)).foregroundStyle(Color.kMuted) }
        let pct = Int((Double(now - before) * 100 / Double(before)).rounded())
        let text = pct == 0 ? "0%" : pct > 0 ? "+\(pct)%" : "−\(-pct)%"
        return Text(text).font(.mono(12)).foregroundStyle(pct > 0 ? Color.kAlarm : pct < 0 ? Color.kGrowth : Color.kMuted)
    }

    private var largest: some View {
        KCard(spacing: 0) {
            CardHeader("Largest entries").padding(.bottom, 8)
            if report.largest.isEmpty { Text("Nothing spent yet.").font(.grotesk(12)).foregroundStyle(Color.kMuted) }
            ForEach(report.largest) { tx in
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(EntryFormat.title(tx, report.data)).font(.grotesk(13)).foregroundStyle(Color.kInk)
                            Text([tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated)), EntryFormat.categoryName(tx.categoryUid, report.data)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.grotesk(11)).foregroundStyle(Color.kMuted)
                        }
                        Spacer()
                        Text(Money.format(tx.amountMinor, currency: tx.currency)).font(.mono(13)).foregroundStyle(Color.kInk)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var spendOverTime: some View {
        let peak = max(report.buckets.map(\.minor).max() ?? 0, 1)
        let total = report.buckets.reduce(Int64(0)) { $0 + $1.minor }
        let average = report.buckets.isEmpty ? 0 : total / Int64(report.buckets.count)
        return KCard(spacing: 10) {
            CardHeader(title: report.isYear ? "Spending by month" : "Spending by day") {
                Text("\(report.isYear ? "Monthly" : "Daily") average \(Money.format(average))").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            HStack(alignment: .bottom, spacing: report.isYear ? 10 : 4) {
                // Bars keep a sensible width early in a month, when there are only a few days.
                ForEach(Array(report.buckets.enumerated()), id: \.offset) { i, b in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.kSynapse.opacity(b.minor >= peak * 2 / 3 ? 1 : 0.5))
                            .frame(maxWidth: report.isYear ? 40 : 22)
                            .frame(height: max(2, 110 * CGFloat(b.minor) / CGFloat(peak)))
                        Text(report.isYear || i % 7 == 0 ? b.label : " ").font(.mono(10)).foregroundStyle(Color.kMuted).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(b.label): \(Money.format(b.minor))")
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }
}
