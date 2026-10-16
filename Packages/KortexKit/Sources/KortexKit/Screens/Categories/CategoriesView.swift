import KortexFinance
import SwiftUI

/// Categories (Figma: Mac · Categories). Built-in, your own and income categories with this month's
/// entries and spend; the selected one in the inspector with its trend and the merchants Kortex files
/// under it. Built-in categories can't be changed; yours can be renamed, recoloured or deleted. Expense
/// categories, built-in ones too, can have a monthly budget, shown as "₹5,400 of ₹8,000 this month".
struct CategoriesView: View {
    let finance: any FinanceStore
    @Bindable var model: AppModel

    @State private var filter: Filter = .all
    @State private var showsInspector = true

    enum Filter: String, CaseIterable { case all = "All", expense = "Expense", income = "Income" }

    /// What each built-in category covers, under its name (as kortex's CategoriesUi).
    static let builtInSubtitles = [
        "food": "Groceries, eating out, delivery",
        "travel": "Cabs, fuel, trains, flights",
        "utilities": "Electricity, internet, phone, gas",
        "salary": "Built in",
    ]

    var body: some View {
        let data = finance.data
        let today = LocalDay.today()
        let month = today.yearMonth
        let txs = Array(data.transactions.values)
        let counts = Spending.entriesPerCategory(txs)
        let (monthTotals, monthCounts) = Self.monthByCategory(txs, from: month.firstDay, to: today)
        let spentThisMonth = Spending.spentMinor(txs, from: month.firstDay, to: today)
        let incomeThisMonth = Spending.incomeMinor(txs, from: month.firstDay, to: today)
        let budgets = Dictionary(uniqueKeysWithValues: Budgets.status(data, month: month, today: today).categories.map { ($0.categoryUid, $0) })
        let all = data.categories.values.sorted { ($0.kind.rawValue, $0.builtIn ? 0 : 1, $0.sortOrder, $0.name) < ($1.kind.rawValue, $1.builtIn ? 0 : 1, $1.sortOrder, $1.name) }
        let groups: [(String, [SpendCategory])] = [
            ("EXPENSE · BUILT IN", all.filter { $0.kind == .expense && $0.builtIn }),
            ("EXPENSE · YOURS", all.filter { $0.kind == .expense && !$0.builtIn }),
            ("INCOME", all.filter { $0.kind == .income }),
        ].filter { title, _ in
            switch filter {
            case .all: true
            case .expense: title.hasPrefix("EXPENSE")
            case .income: title == "INCOME"
            }
        }

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("CATEGORY").sectionLabelStyle().frame(maxWidth: .infinity, alignment: .leading)
                Text("ENTRIES").sectionLabelStyle().frame(width: 70, alignment: .trailing)
                Text(Format.monthName(month).uppercased()).sectionLabelStyle().frame(width: 120, alignment: .trailing)
                Text("SHARE").sectionLabelStyle().padding(.leading, 12).frame(width: 170, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            Hairline()
            List(selection: $model.selectedCategoryUid) {
                ForEach(groups, id: \.0) { title, items in
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { c in
                                let total = monthTotals[c.uid] ?? 0
                                let base = c.kind == .income ? incomeThisMonth : spentThisMonth
                                row(c, entries: monthCounts[c.uid] ?? 0, allEntries: counts[c.uid] ?? 0, total: total,
                                    share: base > 0 ? Double(total) / Double(base) : 0, budget: budgets[c.uid])
                                    .tag(c.uid)
                                    .contextMenu {
                                        if Self.opens(c) {
                                            Button(Self.editTitle(c) + "…") { model.sheet = .category(c.uid, c.kind) }
                                        }
                                        if !c.builtIn {
                                            Button("Delete…", role: .destructive) { model.sheet = .deleteCategory(c.uid) }
                                        }
                                    }
                            }
                        } header: {
                            Text(title).sectionLabelStyle().padding(.top, 6)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            Hairline()
            Label("Built-in categories can’t be renamed or removed.", systemImage: "lock")
                .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .panelSurface(clipped: true)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.kVoid)
        .navigationTitle("Categories")
        .navigationSubtitle("\(data.categories.count) categories · \(Format.monthName(month))")
        .toolbar {
            ToolbarItem(placement: .principal) {
                KSegmented("Show", selection: $filter, options: Filter.allCases.map { ($0, $0.rawValue) })
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.sheet = .category(nil, filter == .income ? .income : .expense) } label: { Label("New category", systemImage: "plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
            }
        }
        .sidePanel(isPresented: showsInspector) {
            CategoryInspector(category: model.selectedCategoryUid.flatMap { data.categories[$0] }, data: data, today: today,
                              onEdit: { model.sheet = .category($0.uid, $0.kind) },
                              onDelete: { model.sheet = .deleteCategory($0.uid) })
        }
    }

    /// This month's spend (or income) and entry count per category.
    private static func monthByCategory(_ txs: [Entry], from: LocalDay, to: LocalDay) -> ([String: Int64], [String: Int]) {
        var totals: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        for tx in txs where (tx.type == .expense || tx.type == .income) && tx.occurredOn.isWithin(from, to) {
            guard let uid = tx.categoryUid else { continue }
            totals[uid, default: 0] += tx.amountMinor
            counts[uid, default: 0] += 1
        }
        return (totals, counts)
    }

    /// Yours open to be edited, and built-in expense categories so a budget can be set on them.
    static func opens(_ c: SpendCategory) -> Bool { !c.builtIn || c.kind == .expense }

    static func editTitle(_ c: SpendCategory) -> String {
        c.builtIn ? "Set budget" : c.kind == .expense ? "Rename, recolour or budget" : "Rename or recolour"
    }

    private func row(_ c: SpendCategory, entries: Int, allEntries: Int, total: Int64, share: Double, budget: CategoryBudget?) -> some View {
        let subtitle = c.builtIn ? (Self.builtInSubtitles[c.uid] ?? "Built in") : "Added by you · \(allEntries) entr\(allEntries == 1 ? "y" : "ies")"
        let color = Color.token(c.colorToken)
        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.grotesk(13, .medium)).foregroundStyle(Color.kInk)
                    if let budget {
                        BudgetLine(budget: budget, suffix: " this month")
                    } else {
                        Text(subtitle).font(.grotesk(11)).foregroundStyle(Color.kMuted)
                    }
                }
                if c.builtIn { Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Color.kMuted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entries)").font(.mono(12)).foregroundStyle(Color.kMuted).frame(width: 70, alignment: .trailing)
            Text(Money.format(total, signed: c.kind == .income && total > 0))
                .font(.mono(13)).foregroundStyle(c.kind == .income && total > 0 ? Color.kGrowth : Color.kInk)
                .frame(width: 120, alignment: .trailing)
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.kRaised)
                        if share > 0 { Capsule().fill(color).frame(width: max(4, geo.size.width * share)) }
                    }
                }
                .frame(height: 6)
                Text("\(Int((share * 100).rounded()))%").font(.mono(11)).foregroundStyle(Color.kMuted).frame(width: 36, alignment: .trailing)
            }
            .padding(.leading, 12)
            .frame(width: 170)
        }
        .padding(.vertical, 6)
    }
}

/// "₹5,400 of ₹8,000 this month" over a bar, as the phone's BudgetLine: the spent amount and the bar
/// turn Amber from 80% and Alarm over budget, when the bar fills.
struct BudgetLine: View {
    let budget: CategoryBudget
    var suffix = ""

    private var level: Color {
        if budget.spentMinor > budget.budgetMinor { return .kAlarm }
        return budget.spentMinor * 100 >= budget.budgetMinor * 80 ? .kAmber : .kSynapse
    }

    var body: some View {
        let fraction = min(max(Double(budget.spentMinor) / Double(budget.budgetMinor), 0), 1)
        VStack(alignment: .leading, spacing: 4) {
            (Text(Money.format(budget.spentMinor, wholeUnits: true)).foregroundColor(level == .kSynapse ? .kMuted : level)
                + Text(" of \(Money.format(budget.budgetMinor, wholeUnits: true))\(suffix)"))
                .font(.grotesk(11)).foregroundStyle(Color.kMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.kRaised)
                    if fraction > 0 { Capsule().fill(level).frame(width: max(4, geo.size.width * fraction)) }
                }
            }
            .frame(width: 180, height: 4)
        }
    }
}

/// The selected category: six months of spend in it and the merchants filed under it.
struct CategoryInspector: View {
    let category: SpendCategory?
    let data: FinanceData
    let today: LocalDay
    var onEdit: ((SpendCategory) -> Void)?
    var onDelete: ((SpendCategory) -> Void)?

    var body: some View {
        Group {
            if let c = category {
                ScrollView { details(c).padding(20) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tag").font(.system(size: 22, weight: .light)).foregroundStyle(Color.kMuted)
                    Text("Select a category to see its details").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.kSidebar)
    }

    private func details(_ c: SpendCategory) -> some View {
        let txs = data.transactions.values.filter { $0.categoryUid == c.uid && ($0.type == .expense || $0.type == .income) }
        let months = (0..<6).reversed().map { today.yearMonth.adding(months: -$0) }
        let perMonth = months.map { m in txs.filter { $0.occurredOn.yearMonth == m }.reduce(Int64(0)) { $0 + $1.amountMinor } }
        let peak = max(perMonth.max() ?? 0, 1)
        let merchants = data.merchants.values.filter { $0.categoryUid == c.uid }.sorted { $0.displayName < $1.displayName }
        let color = Color.token(c.colorToken)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(c.kind == .income ? "INCOME CATEGORY" : "EXPENSE CATEGORY").sectionLabelStyle()
                Spacer()
                if CategoriesView.opens(c), let onEdit {
                    Button { onEdit(c) } label: { Image(systemName: "pencil") }.help(CategoriesView.editTitle(c))
                }
                if !c.builtIn, let onDelete { Button { onDelete(c) } label: { Image(systemName: "trash") }.help("Delete") }
            }
            .buttonStyle(.borderless)
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 14, height: 14)
                Text(c.name).font(.grotesk(22, .medium)).foregroundStyle(Color.kInk)
            }
            Text(c.builtIn ? (CategoriesView.builtInSubtitles[c.uid] ?? "Built in") : "Added by you")
                .font(.grotesk(12)).foregroundStyle(Color.kMuted)
            if let budget = Budgets.status(data, month: today.yearMonth, today: today).categories.first(where: { $0.categoryUid == c.uid }) {
                KCard(padding: 14, spacing: 10) {
                    Text("BUDGET · \(Format.monthName(today.yearMonth).uppercased())").sectionLabelStyle()
                    BudgetLine(budget: budget)
                    HStack {
                        Text(budget.leftMinor >= 0 ? "\(Money.format(budget.leftMinor, wholeUnits: true)) left"
                                                   : "\(Money.format(-budget.leftMinor, wholeUnits: true)) over")
                        Spacer()
                        Text("Month ends near \(Money.format(budget.projectedMinor, wholeUnits: true))")
                    }
                    .font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            KCard(padding: 14, spacing: 10) {
                Text("LAST 6 MONTHS").sectionLabelStyle()
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(zip(months, perMonth)), id: \.0) { m, amount in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(m == today.yearMonth ? 1 : 0.45))
                                .frame(height: max(2, 60 * CGFloat(amount) / CGFloat(peak)))
                            Text(Format.monthShort(m)).font(.mono(9)).foregroundStyle(Color.kMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(Format.monthName(m)): \(Money.format(amount))")
                    }
                }
                .frame(height: 80, alignment: .bottom)
            }
            .fixedSize(horizontal: false, vertical: true)
            FieldList(rows: [
                ("Entries", "\(txs.count)"),
                ("All time", Money.format(txs.reduce(0) { $0 + $1.amountMinor })),
                ("Colour", c.colorToken),
            ])
            VStack(alignment: .leading, spacing: 8) {
                Text("MERCHANTS FILED HERE").sectionLabelStyle()
                if merchants.isEmpty {
                    Text("None yet. When you correct a merchant's category on your phone, Kortex remembers it.")
                        .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
                ForEach(merchants) { m in
                    Text(m.displayName).font(.grotesk(13)).foregroundStyle(Color.kInk)
                }
            }
        }
    }
}
