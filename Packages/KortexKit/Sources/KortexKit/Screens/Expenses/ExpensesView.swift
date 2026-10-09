import KortexFinance
import SwiftUI

/// Expenses (Figma: Mac · Expenses — monthly). Daily / Monthly / Yearly in the toolbar with ‹ › to
/// step periods, the period's summary, then every entry in a table with the selected one in the inspector.
struct ExpensesView: View {
    let finance: any FinanceStore
    @Bindable var model: AppModel
    let go: (Destination) -> Void

    @State private var filter: Filter = .all
    @State private var showsInspector = true
    /// Entries waiting on Delete's confirmation.
    @State private var deleting: [Entry] = []

    enum Filter: String, CaseIterable { case all = "All", expenses = "Expenses", income = "Income" }

    // Nothing here reads the table selection: that would re-run this whole body, summary and all, on
    // every click and arrow key. Only ExpensesInspector reads it; the table gets it as a binding.
    var body: some View {
        let data = finance.data
        let today = LocalDay.today()
        let period = model.expensesPeriod
        let range = period.range
        let inPeriod = data.transactions.values.filter { $0.type != .opening && $0.occurredOn.isWithin(range.from, range.to) }
        let shown = inPeriod.filter {
            switch filter {
            case .all: true
            case .expenses: $0.type == .expense
            case .income: $0.type == .income
            }
        }

        VStack(alignment: .leading, spacing: 16) {
            ExpensesSummary(data: data, period: period, today: today, go: go)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Entries").font(.grotesk(15, .medium)).foregroundStyle(Color.kInk)
                    Spacer()
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Hairline()
                if shown.isEmpty {
                    Text(inPeriod.isEmpty ? "Nothing added in this period." : "No \(filter.rawValue.lowercased()) in this period.")
                        .font(.grotesk(13)).foregroundStyle(Color.kMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EntriesTable(entries: shown, data: data, selection: $model.selectedEntryUids, focusOnAppear: true) { action, uids in
                        perform(action, on: uids)
                    }
                }
                Hairline()
                footer(shown)
            }
            .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kEdge))
            // An explicit minimum: the table's own one is large enough that, under the taller
            // monthly summary, the page outgrew the window and its top was cut off.
            .frame(minHeight: 160, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.kVoid)
        .navigationTitle("Expenses")
        .navigationSubtitle(inPeriod.count == 1 ? "1 entry" : "\(inPeriod.count) entries")
        .toolbar { toolbar(today: today) }
        .sidePanel(isPresented: showsInspector) {
            ExpensesInspector(model: model, data: data, onDelete: { deleting = [$0] })
        }
        .onDeleteCommand { perform(.delete, on: model.selectedEntryUids) }
        .modifier(DeleteEntriesConfirmation(deleting: $deleting, finance: finance, model: model))
    }

    private func perform(_ action: EntryAction, on uids: Set<String>) {
        EntryActions.perform(action, on: uids, finance: finance, model: model, deleting: $deleting)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(today: LocalDay) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 12) {
                Picker("Period", selection: $model.expensesPeriod.mode) {
                    ForEach(ExpensesMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                ControlGroup {
                    Button { model.expensesPeriod = model.expensesPeriod.previous() } label: { Image(systemName: "chevron.left") }
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Previous period (⌘[)")
                    Button { model.expensesPeriod = model.expensesPeriod.next(today: today) } label: { Image(systemName: "chevron.right") }
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(!model.expensesPeriod.canGoNext(today: today))
                        .help("Next period (⌘])")
                }
                Text(periodTitle(model.expensesPeriod, today: today))
                    .font(.grotesk(13, .medium))
                    .foregroundStyle(Color.kInk)
                    .frame(minWidth: 150, alignment: .leading)
            }
        }
        ToolbarItem(placement: .primaryAction) { AddMenu(model: model) }
        ToolbarItem(placement: .primaryAction) {
            Button { showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .help(showsInspector ? "Hide details" : "Show details")
        }
    }

    private func periodTitle(_ p: ExpensesPeriod, today: LocalDay) -> String {
        switch p.mode {
        case .daily:
            let name = p.day == today ? "Today" : p.day == today.adding(days: -1) ? "Yesterday" : p.day.date.formatted(.dateTime.weekday(.abbreviated))
            return "\(name), \(p.day.date.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .monthly: return p.month.date.formatted(.dateTime.month(.wide).year())
        case .yearly: return String(p.year)
        }
    }

    private func footer(_ shown: [Entry]) -> some View {
        let out = shown.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let inn = shown.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountMinor }
        return HStack(spacing: 16) {
            Text(shown.count == 1 ? "1 entry" : "\(shown.count) entries").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            Spacer()
            Text("Out \(Money.format(out))").font(.mono(12)).foregroundStyle(Color.kMuted)
            Text("In \(Money.format(inn))").font(.mono(12)).foregroundStyle(Color.kGrowth)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// The selected entry, or a summary of several. Its own view so that only it re-runs when the
/// table selection changes.
private struct ExpensesInspector: View {
    let model: AppModel
    let data: FinanceData
    let onDelete: (Entry) -> Void

    var body: some View {
        let selected = model.selectedEntryUids.compactMap { data.transactions[$0] }
        if selected.count > 1 {
            SelectionSummary(entries: selected)
        } else {
            EntryInspector(entry: selected.first, data: data,
                           onEdit: { model.sheet = .editEntry($0.uid) }, onDelete: onDelete)
        }
    }
}

/// The period's summary above the table: the day, month or year's totals, and in a month what stood out.
/// Its own view so these passes over every entry run when the data or period changes, not the selection.
private struct ExpensesSummary: View {
    let data: FinanceData
    let period: ExpensesPeriod
    let today: LocalDay
    let go: (Destination) -> Void

    var body: some View {
        let txs = Array(data.transactions.values)
        switch period.mode {
        case .daily: daily(txs: txs, day: period.day, today: today)
        case .monthly: monthly(data: data, txs: txs, month: period.month, today: today)
        case .yearly: yearly(data: data, txs: txs, year: period.year, today: today)
        }
    }

    private func daily(txs: [Entry], day: LocalDay, today: LocalDay) -> some View {
        let spent = Spending.spentMinor(txs, from: day, to: day)
        let week = (0..<7).reversed().map { back -> (LocalDay, Int64) in
            let d = day.adding(days: -back)
            return (d, Spending.spentMinor(txs, from: d, to: d))
        }
        let weekTotal = week.reduce(0) { $0 + $1.1 }
        let peak = max(week.map(\.1).max() ?? 0, 1)
        return row {
            KPITile(label: day == today ? "SPENT TODAY" : "SPENT THIS DAY", value: Money.format(spent),
                    sub: "\(Spending.expenses(txs, from: day, to: day).count) expenses")
            KCard(padding: 18, spacing: 8) {
                HStack {
                    Text("LAST 7 DAYS").sectionLabelStyle().lineLimit(1)
                    Spacer()
                    Text(Money.format(weekTotal)).font(.mono(12)).foregroundStyle(Color.kInk)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(week, id: \.0) { d, amount in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.kSynapse.opacity(d == day ? 1 : 0.45))
                                .frame(height: max(2, 44 * CGFloat(amount) / CGFloat(peak)))
                            Text(d.date.formatted(.dateTime.weekday(.narrow))).font(.mono(10)).foregroundStyle(Color.kMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(d.date.formatted(.dateTime.weekday(.wide).day().month())): \(Money.format(amount))")
                    }
                }
                .frame(height: 62, alignment: .bottom)
            }
        }
    }

    private func monthly(data: FinanceData, txs: [Entry], month: YearMonth, today: LocalDay) -> some View {
        let current = month == today.yearMonth
        let to = current ? today : month.lastDay
        let summary = Spending.period(txs, from: month.firstDay, to: to)
        let standouts = ExpensesInsights.standouts(
            data, month: month, to: to, today: today,
            money: { Money.format($0, wholeUnits: !$1) },
            monthName: Format.monthName,
            dayName: { $0.date.formatted(.dateTime.day().month(.abbreviated)) }
        )
        return VStack(alignment: .leading, spacing: 16) {
            row {
                KPITile(label: "TOTAL SPENT", value: Money.format(summary.spentMinor), sub: current ? "so far this month" : Format.monthName(month))
                KPITile(label: "TOTAL INCOME", value: Money.format(summary.incomeMinor), sub: " ")
                KPITile(label: "SAVINGS THIS MONTH", value: Money.format(summary.savingsMinor),
                        sub: summary.savingsRate.map { "\(Int(($0 * 100).rounded()))% of income" } ?? "No income yet",
                        subColor: summary.savingsMinor >= 0 ? .kGrowth : .kAlarm)
                // Not a Button: a button can offer its label unlimited height, and KCard fills
                // whatever height it's offered, which pushed this whole page off the window.
                KCard(padding: 18, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.doc.horizontal").foregroundStyle(Color.kSynapse)
                        Text("\(Format.monthName(month)) report").font(.grotesk(14, .medium)).foregroundStyle(Color.kInk).lineLimit(1)
                    }
                    Text("Income vs expenses, savings rate").font(.grotesk(12)).foregroundStyle(Color.kMuted).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("Open").font(.grotesk(12, .medium)).foregroundStyle(Color.kSynapse)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { go(.reports) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open \(Format.monthName(month)) report")
            }
            if !standouts.isEmpty {
                Text("WHAT STOOD OUT").sectionLabelStyle()
                // A grid, not an HStack: the HStack measured these wrapping sentences at near-zero
                // width while sizing itself, made them enormously tall, and pushed the page off the window.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: standouts.count), spacing: 16) {
                    ForEach(standouts, id: \.self) { s in
                        standoutText(s)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                            .padding(14)
                            .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kEdge))
                    }
                }
            }
        }
    }

    private func yearly(data: FinanceData, txs: [Entry], year: Int, today: LocalDay) -> some View {
        let from = LocalDay(year: year, month: 1, day: 1)!
        let to = year == today.year ? today : LocalDay(year: year, month: 12, day: 31)!
        let summary = Spending.period(txs, from: from, to: to)
        let shares = Spending.whereItWent(txs, categories: data.categories, from: from, to: to)
        return row {
            KPITile(label: "SPENT IN \(year)", value: Money.format(summary.spentMinor), sub: year == today.year ? "so far this year" : " ")
            KPITile(label: "SAVED", value: Money.format(summary.savingsMinor),
                    sub: summary.savingsRate.map { String(format: "%.1f%% of income", $0 * 100) } ?? "No income",
                    subColor: summary.savingsMinor >= 0 ? .kGrowth : .kAlarm)
            WhereItWentCard(shares: shares, openReport: { go(.reports) })
                .frame(minWidth: 360)
        }
    }

    private func standoutText(_ s: Standout) -> Text {
        let color: Color = switch s.tone {
        case .good: .kGrowth
        case .warn: .kAmber
        case .neutral: .kInk
        }
        return (Text(s.before) + Text(s.highlight).foregroundColor(color) + Text(s.after))
            .font(.grotesk(13))
            .foregroundColor(.kInk)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) { content() }.fixedSize(horizontal: false, vertical: true)
    }
}
