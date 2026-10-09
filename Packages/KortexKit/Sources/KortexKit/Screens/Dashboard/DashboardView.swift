import Charts
import KortexFinance
import SwiftUI

/// Dashboard (Figma: Kortex - Finances (Mac OS) › Mac · Dashboard). Four KPIs, cash flow beside
/// pending payments, then pace, where it went and recent entries. Read-only until adding lands.
struct DashboardView: View {
    let finance: any FinanceStore
    let appModel: AppModel
    let go: (Destination) -> Void

    var body: some View {
        let data = finance.data
        let model = DashboardModel(data: data, today: .today())
        Group {
            if !model.hasAccounts {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        kpis(model)
                        equalHeightRow {
                            CashFlowCard(flows: model.flows)
                            PendingCard(model: model, data: data, seeAll: { go(.pending) })
                                .frame(width: 400)
                        }
                        equalHeightRow {
                            if let pace = model.pace { PaceCard(pace: pace, month: model.month) }
                            WhereItWentCard(shares: model.shares, openReport: { go(.reports) })
                            RecentCard(entries: model.recent, data: data, showAll: { go(.expenses) })
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Color.kVoid)
        .navigationTitle("Dashboard")
        .navigationSubtitle(Format.longDay(model.today))
        .toolbar { ToolbarItem(placement: .primaryAction) { AddMenu(model: appModel) } }
    }

    private func kpis(_ m: DashboardModel) -> some View {
        let mtd = m.monthToDate
        let lastMonth = Format.monthName(m.month.adding(months: -1))
        let spentLine: (String, Color) = switch mtd.deltaMinor {
        case ..<0: ("\(Money.format(-mtd.deltaMinor, wholeUnits: true)) less than \(lastMonth) by day \(mtd.day)", .kGrowth)
        case 1...: ("\(Money.format(mtd.deltaMinor, wholeUnits: true)) more than \(lastMonth) by day \(mtd.day)", .kAmber)
        default: ("Same as \(lastMonth) by day \(mtd.day)", .kMuted)
        }
        let keptLine: (String, Color) = switch m.keptChange {
        case .some(let c) where c > 0: ("\(Format.points(c)) more than \(lastMonth)", .kGrowth)
        case .some(let c) where c < 0: ("\(Format.points(-c)) less than \(lastMonth)", .kAmber)
        case .some: ("Same as \(lastMonth)", .kMuted)
        case .none: (m.keptPercent == nil ? "No income yet this month" : "of this month’s income", .kMuted)
        }
        return equalHeightRow {
            KPITile(label: "TOTAL BALANCE", value: Money.format(m.totalBalanceMinor),
                    sub: m.accountCount == 1 ? "1 account" : "\(m.accountCount) accounts")
            KPITile(label: "PENDING", value: Money.format(m.pending.totalMinor, wholeUnits: true),
                    sub: m.pending.count == 0 ? "Nothing due in 30 days" : "\(m.pending.count) due · next 30 days",
                    subColor: m.pending.count == 0 ? .kMuted : .kAmber)
            KPITile(label: "SPENT IN \(Format.monthName(m.month).uppercased())", value: Money.format(m.currentFlow.outMinor),
                    sub: spentLine.0, subColor: spentLine.1)
            KPITile(label: "KEPT THIS MONTH", value: m.keptPercent.map { "\($0)%" } ?? "—", sub: keptLine.0, subColor: keptLine.1)
        }
    }

    private func equalHeightRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) { content() }.fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: finance.status == .loading ? "arrow.triangle.2.circlepath" : "wallet.bifold")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.kSynapse)
            Text(finance.status == .loading ? "Syncing your finances…" : "No accounts yet")
                .font(.grotesk(20, .medium))
                .foregroundStyle(Color.kInk)
            Text(finance.status == .loading ? "This takes a moment the first time." : "Add one here or on your phone; it shows up on both.")
                .font(.grotesk(13))
                .foregroundStyle(Color.kMuted)
            if finance.status != .loading {
                Button("Add account…") { appModel.sheet = .account(nil, .bank) }
                    .buttonStyle(.borderedProminent).tint(.kSynapse).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DashboardView(finance: PreviewFinanceStore.sample(), appModel: AppModel(), go: { _ in })
        .frame(width: 1200, height: 900)
}

struct KPITile: View {
    let label: String
    let value: String
    let sub: String
    var subColor: Color = .kMuted

    var body: some View {
        KCard(padding: 18, spacing: 6) {
            Text(label).sectionLabelStyle().lineLimit(1)
            Text(value).font(.grotesk(26, .medium)).foregroundStyle(Color.kInk).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.grotesk(12)).foregroundStyle(subColor).lineLimit(2)
        }
    }
}

// MARK: Cash flow

struct CashFlowCard: View {
    let flows: [MonthFlow]
    @State private var range = 6

    var body: some View {
        let shown = Array(flows.suffix(range))
        let current = flows[flows.count - 1]
        let peak = max(shown.map { max($0.inMinor, $0.outMinor) }.max() ?? 0, 1)
        KCard(spacing: 14) {
            CardHeader(title: "Cash flow") {
                legend("In", .kGrowth)
                legend("Out", .kSynapse)
                Spacer()
                Picker("Range", selection: $range) {
                    Text("3M").tag(3)
                    Text("6M").tag(6)
                    Text("1Y").tag(12)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(shown, id: \.month) { flow in
                    let isCurrent = flow.month == current.month
                    VStack(spacing: 10) {
                        HStack(alignment: .bottom, spacing: range == 12 ? 3 : 6) {
                            bar(flow.inMinor, peak, .kGrowth, isCurrent)
                            bar(flow.outMinor, peak, .kSynapse, isCurrent)
                        }
                        .frame(height: 150, alignment: .bottom)
                        Text(Format.monthShort(flow.month))
                            .font(.mono(11))
                            .foregroundStyle(isCurrent ? Color.kInk : Color.kMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(Format.monthName(flow.month)): in \(Money.format(flow.inMinor)), out \(Money.format(flow.outMinor))")
                }
            }
            Hairline()
            HStack(spacing: 20) {
                Text("\(Format.monthName(current.month)) so far").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                Spacer()
                Text("In \(Money.format(current.inMinor))").font(.mono(12)).foregroundStyle(Color.kMuted)
                Text("Out \(Money.format(current.outMinor))").font(.mono(12)).foregroundStyle(Color.kMuted)
                Text(Money.format(current.netMinor, signed: true))
                    .font(.mono(14))
                    .foregroundStyle(current.netMinor >= 0 ? Color.kGrowth : Color.kAlarm)
            }
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).font(.grotesk(12)).foregroundStyle(Color.kMuted)
        }
    }

    private func bar(_ value: Int64, _ peak: Int64, _ color: Color, _ current: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(current ? 1 : 0.45))
            .frame(width: range == 12 ? 10 : 18, height: max(2, 150 * CGFloat(value) / CGFloat(peak)))
    }
}

// MARK: Pending

struct PendingCard: View {
    let model: DashboardModel
    let data: FinanceData
    let seeAll: () -> Void

    var body: some View {
        let pending = model.pending
        KCard(spacing: 10) {
            CardHeader(title: "Pending payments") { CardLink(title: "See all", action: seeAll) }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Money.format(pending.totalMinor, wholeUnits: true)).font(.grotesk(28, .medium)).foregroundStyle(Color.kInk)
                Text("due in the next 30 days").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            SplitBar(first: pending.cardBillsMinor, rest: pending.recurringMinor)
            if pending.items.isEmpty {
                Text("Nothing due. Card bills and recurring payments show up here.")
                    .font(.grotesk(12)).foregroundStyle(Color.kMuted).padding(.vertical, 8)
            }
            ForEach(pending.items.prefix(3)) { item in
                VStack(spacing: 0) {
                    Hairline()
                    row(item).padding(.vertical, 8)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("Left after pending").font(.grotesk(13, .medium)).foregroundStyle(Color.kInk)
                Spacer()
                Text(Money.format(model.leftAfterPendingMinor)).font(.mono(14)).foregroundStyle(Color.kInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.kRaised, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ item: PendingItem) -> some View {
        let urgency = Pending.urgency(item.dueOn, today: model.today)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(item)).font(.grotesk(13, .medium)).foregroundStyle(Color.kInk).lineLimit(1).help(title(item))
                Text(subtitle(item)).font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(item.amountMinor, wholeUnits: true)).font(.mono(13)).foregroundStyle(Color.kInk)
                Text(urgency == .overdue ? "Overdue · \(Format.dueDay(item.dueOn))" : Format.dueDay(item.dueOn))
                    .font(.grotesk(11))
                    .foregroundStyle(urgency == .overdue ? Color.kAlarm : urgency == .soon ? Color.kAmber : Color.kMuted)
            }
        }
    }

    private func title(_ item: PendingItem) -> String {
        guard item.kind == .cardBill, let card = data.accounts[item.title] else { return item.title }
        return card.last4.map { "\(card.name) ••\($0)" } ?? card.name
    }

    private func subtitle(_ item: PendingItem) -> String {
        switch item.kind {
        case .cardBill:
            return item.minDueMinor.map { "Card bill · min \(Money.format($0, wholeUnits: true))" } ?? "Card bill"
        case .subscription, .fixed:
            let kind = item.kind == .subscription ? "Subscription" : "Fixed"
            let frequency = data.recurring[item.sourceUid].map { r -> String in
                switch r.frequency {
                case .weekly: r.interval == 1 ? "weekly" : "every \(r.interval) weeks"
                case .monthly: r.interval == 1 ? "monthly" : "every \(r.interval) months"
                case .yearly: r.interval == 1 ? "yearly" : "every \(r.interval) years"
                }
            }
            return [kind, frequency].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

// MARK: Pace

struct PaceCard: View {
    let pace: DashboardModel.Pace
    let month: YearMonth

    private struct Point: Identifiable {
        let series: String
        let day: Int
        let minor: Int64
        var id: String { "\(series)-\(day)" }
    }

    var body: some View {
        let thisName = month.date.formatted(.dateTime.month(.abbreviated))
        let lastName = month.adding(months: -1).date.formatted(.dateTime.month(.abbreviated))
        let points = pace.lastMonth.enumerated().map { Point(series: lastName, day: $0.offset + 1, minor: $0.element) }
            + pace.thisMonth.enumerated().map { Point(series: thisName, day: $0.offset + 1, minor: $0.element) }
        KCard(spacing: 10) {
            CardHeader(title: "Pace vs \(Format.monthName(month.adding(months: -1)))") {
                legendLine(thisName, dashed: false)
                legendLine(lastName, dashed: true)
            }
            Chart(points) { p in
                LineMark(x: .value("Day", p.day), y: .value("Spent", Double(p.minor) / 100), series: .value("Month", p.series))
                    .foregroundStyle(p.series == thisName ? Color.kSynapse : Color.kMuted.opacity(0.7))
                    .lineStyle(p.series == thisName ? StrokeStyle(lineWidth: 2, lineJoin: .round) : StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
            .chartXScale(domain: 1...pace.daysInMonth)
            .chartXAxis {
                AxisMarks(values: [1, 8, 15, 22, 29].filter { $0 <= pace.daysInMonth }) { value in
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)").font(.mono(10)).foregroundStyle(Color.kMuted) }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.kEdge)
                }
            }
            .frame(height: 120)
            HStack {
                Text("At this pace, month ends near").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                Spacer()
                Text(Money.format(pace.projectedMinor, wholeUnits: true)).font(.mono(13)).foregroundStyle(Color.kInk)
            }
        }
    }

    private func legendLine(_ title: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(dashed ? Color.kMuted.opacity(0.6) : Color.kSynapse)
                .frame(width: 14, height: 2)
            Text(title).font(.grotesk(12)).foregroundStyle(Color.kMuted)
        }
    }
}

// MARK: Where it went

struct WhereItWentCard: View {
    let shares: [CategoryShare]
    let openReport: () -> Void

    var body: some View {
        KCard(spacing: 10) {
            CardHeader(title: "Where it went") { CardLink(title: "Report", action: openReport) }
            if shares.isEmpty {
                Text("No spending yet this month.").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            } else {
                ShareBar(shares: shares, height: 8)
                ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                    HStack(spacing: 10) {
                        Circle().fill(Color.category(share.category)).frame(width: 8, height: 8)
                        Text(share.category?.name ?? "Other").font(.grotesk(13)).foregroundStyle(Color.kInk)
                        Spacer()
                        Text("\(share.percent)%").font(.mono(12)).foregroundStyle(Color.kMuted)
                        Text(Money.format(share.amountMinor)).font(.mono(12)).foregroundStyle(Color.kInk)
                            .frame(width: 96, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: Recent

struct RecentCard: View {
    let entries: [KortexFinance.Transaction]
    let data: FinanceData
    let showAll: () -> Void

    var body: some View {
        KCard(spacing: 2) {
            CardHeader(title: "Recent") { CardLink(title: "All expenses", action: showAll) }
                .padding(.bottom, 6)
            if entries.isEmpty {
                Text("Nothing added yet.").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            ForEach(entries) { tx in
                let incoming = tx.type == .income
                HStack(spacing: 10) {
                    Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(incoming ? Color.kGrowth : Color.kMuted)
                        .frame(width: 28, height: 28)
                        .background(incoming ? Color.kGrowth.opacity(0.12) : Color.kRaised, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(tx)).font(.grotesk(13)).foregroundStyle(Color.kInk).lineLimit(1)
                        Text(subtitle(tx)).font(.grotesk(11)).foregroundStyle(Color.kMuted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(Money.format(incoming ? tx.amountMinor : -tx.amountMinor, currency: tx.currency, signed: incoming))
                        .font(.mono(13))
                        .foregroundStyle(incoming ? Color.kGrowth : Color.kInk)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func title(_ tx: KortexFinance.Transaction) -> String {
        if let merchant = tx.merchant { return merchant }
        if tx.isCardCredit { return tx.note ?? "Refund / credit" }
        switch tx.type {
        case .transfer: return "Transfer"
        case .cardPayment: return "Card bill payment"
        case .income: return "Income"
        default: return tx.categoryUid.flatMap { data.categories[$0]?.name } ?? "Expense"
        }
    }

    private func subtitle(_ tx: KortexFinance.Transaction) -> String {
        let category = tx.categoryUid.flatMap { data.categories[$0]?.name }
        let account = data.accounts[tx.accountUid].map { a in a.last4.map { "\(a.name) ••\($0)" } ?? a.name }
        return [category, account].compactMap { $0 }.joined(separator: " · ")
    }
}
