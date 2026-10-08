import KortexCloud
import KortexFinance
import SwiftUI

/// Pending payments (Figma: Mac · Pending payments). What's due in the next 30 days on the left with a
/// calendar of due days; the payments themselves, soonest first, on the right. Hovering a row shows
/// Skip and Mark paid (Pay bill… for a card); right-click has the rest.
struct PendingView: View {
    let finance: FinanceSync
    let model: AppModel
    let go: (Destination) -> Void

    @State private var filter: Filter = .all
    @State private var calendarMonth = LocalDay.today().yearMonth

    enum Filter: Hashable { case all, cards, subscriptions, fixed }

    var body: some View {
        let data = finance.data
        let today = LocalDay.today()
        let txs = Array(data.transactions.values)
        let summary = Pending.summary(today: today, statements: Array(data.statements.values), recurring: Array(data.recurring.values), transactions: txs)
        let items = summary.items.filter { item in
            switch filter {
            case .all: true
            case .cards: item.kind == .cardBill
            case .subscriptions: item.kind == .subscription
            case .fixed: item.kind == .fixed
            }
        }
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                summaryCard(summary, data: data)
                calendar(data: data, txs: txs, today: today)
                Spacer(minLength: 0)
            }
            .frame(width: 360)
            list(items, data: data, today: today)
        }
        .padding(24)
        .background(Color.kVoid)
        .navigationTitle("Pending payments")
        .navigationSubtitle("Next 30 days")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    Text("All \(summary.count)").tag(Filter.all)
                    Text("Cards \(summary.items.filter { $0.kind == .cardBill }.count)").tag(Filter.cards)
                    Text("Subs \(summary.items.filter { $0.kind == .subscription }.count)").tag(Filter.subscriptions)
                    Text("Fixed \(summary.items.filter { $0.kind == .fixed }.count)").tag(Filter.fixed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { go(.recurring) } label: { Label("Manage recurring", systemImage: "arrow.2.squarepath") }
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func summaryCard(_ s: PendingSummary, data: FinanceData) -> some View {
        KCard(spacing: 12) {
            Text("DUE IN NEXT 30 DAYS").sectionLabelStyle()
            Text(Money.format(s.totalMinor, wholeUnits: true)).font(.grotesk(32, .medium)).foregroundStyle(Color.kInk)
            SplitBar(first: s.cardBillsMinor, rest: s.recurringMinor)
            LegendRow(Color.kSynapse, "Card bills · \(s.cardBillCount)", s.cardBillsMinor, spread: true)
            LegendRow(Color.kSynapse.opacity(0.5), "Subscriptions & fixed · \(s.recurringCount)", s.recurringMinor, spread: true)
            Hairline()
            HStack {
                Text("Total balance").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                Spacer()
                Text(Money.format(data.totalBalanceMinor)).font(.mono(13)).foregroundStyle(Color.kMuted)
            }
            HStack {
                Text("Left after pending").font(.grotesk(14, .medium)).foregroundStyle(Color.kInk)
                Spacer()
                Text(Money.format(data.totalBalanceMinor - s.totalMinor)).font(.mono(15)).foregroundStyle(Color.kInk)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Calendar

    private func calendar(data: FinanceData, txs: [Entry], today: LocalDay) -> some View {
        let month = calendarMonth
        let due = Pending.dueDays(in: month, statements: Array(data.statements.values), recurring: Array(data.recurring.values), transactions: txs)
        let leading = month.firstDay.isoWeekday - 1
        let cells: [LocalDay?] = Array(repeating: nil, count: leading) + (1...month.lengthOfMonth).map { month.day($0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return KCard(spacing: 10) {
            HStack {
                Text(month.date.formatted(.dateTime.month(.wide).year())).font(.grotesk(14, .medium)).foregroundStyle(Color.kInk)
                Spacer()
                Button { calendarMonth = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .disabled(month <= today.yearMonth)
                Button { calendarMonth = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.mono(10)).foregroundStyle(Color.kMuted)
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        dayCell(day, kinds: due[day] ?? [], today: today)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
            HStack(spacing: 12) {
                Circle().fill(Color.kAmber).frame(width: 6, height: 6)
                Text("Due within 7 days").font(.grotesk(11)).foregroundStyle(Color.kMuted)
                Circle().fill(Color.kSynapse).frame(width: 6, height: 6)
                Text("Later").font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dayCell(_ day: LocalDay, kinds: [PendingKind], today: LocalDay) -> some View {
        let urgency = Pending.urgency(day, today: today)
        let tint: Color? = kinds.isEmpty ? nil : urgency == .later ? .kSynapse : .kAmber
        return VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.grotesk(12, tint == nil ? .regular : .medium))
                .foregroundStyle(tint == .kAmber ? Color.kAmber : tint == nil ? (day == today ? Color.kInk : Color.kMuted) : Color.kInk)
            if let tint { Circle().fill(tint).frame(width: 4, height: 4) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background {
            if let tint {
                RoundedRectangle(cornerRadius: 8).fill(tint == .kAmber ? Color.kAmber.opacity(0.12) : Color.kSynapseDim)
            } else if day == today {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.kEdge)
            }
        }
        .help(kinds.isEmpty ? "" : "\(kinds.count) payment\(kinds.count == 1 ? "" : "s") due")
    }

    // MARK: List

    private func list(_ items: [PendingItem], data: FinanceData, today: LocalDay) -> some View {
        let overdue = items.filter { $0.dueOn < today }
        let soon = items.filter { $0.dueOn >= today && today.days(to: $0.dueOn) <= Pending.soonDays }
        let later = items.filter { today.days(to: $0.dueOn) > Pending.soonDays }
        let laterMonths = Set(later.map { $0.dueOn.yearMonth })
        let laterTitle = laterMonths.count == 1 ? "LATER IN \(Format.monthName(laterMonths.first!).uppercased())" : "LATER"
        let notDue = data.recurring.values.filter { r in !r.paused && !items.contains { $0.sourceUid == r.uid } }.count
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 28, height: 1)
                Text("PAYMENT").sectionLabelStyle().frame(maxWidth: .infinity, alignment: .leading)
                Text("PAYS FROM").sectionLabelStyle().frame(width: 150, alignment: .leading)
                Text("DUE").sectionLabelStyle().frame(width: 120, alignment: .trailing)
                Text("AMOUNT").sectionLabelStyle().frame(width: 100, alignment: .trailing)
                Color.clear.frame(width: 170, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        Text("Nothing due in the next 30 days.").font(.grotesk(13)).foregroundStyle(Color.kMuted).padding(.vertical, 40)
                    }
                    section("OVERDUE", overdue, data: data, today: today)
                    section("NEXT 7 DAYS", soon, data: data, today: today)
                    section(laterTitle, later, data: data, today: today)
                }
            }
            Hairline()
            HStack(spacing: 8) {
                Image(systemName: "arrow.2.squarepath").foregroundStyle(Color.kMuted)
                Text("\(data.recurring.count) recurring payment\(data.recurring.count == 1 ? "" : "s") · \(notDue) not due in 30 days")
                    .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                Spacer()
                Button("Manage") { go(.recurring) }.buttonStyle(.plain).font(.grotesk(12, .medium)).foregroundStyle(Color.kSynapse)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kEdge))
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [PendingItem], data: FinanceData, today: LocalDay) -> some View {
        if !items.isEmpty {
            HStack { Text(title).sectionLabelStyle(); Spacer() }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ForEach(items) { item in
                row(item, data: data, today: today)
                    .modifier(PendingActions(item: item, finance: finance, model: model, go: go))
                Hairline()
            }
        }
    }

    private func row(_ item: PendingItem, data: FinanceData, today: LocalDay) -> some View {
        let urgency = Pending.urgency(item.dueOn, today: today)
        let recurring = data.recurring[item.sourceUid]
        let card = item.kind == .cardBill ? data.accounts[item.title] : nil
        let title = card.map { c in c.last4.map { "\(c.name) ••\($0)" } ?? c.name } ?? item.title
        let subtitle: String = switch item.kind {
        case .cardBill: item.minDueMinor.map { "Card bill · min \(Money.format($0, wholeUnits: true))" } ?? "Card bill"
        case .subscription: "Subscription · \(recurring.map(RecurringSchedule.frequencyLabel) ?? "")"
        case .fixed: "Fixed · \(recurring.map(RecurringSchedule.frequencyLabel) ?? "")"
        }
        // A card bill is paid from whichever account you choose when paying it.
        let paysFrom = item.kind == .cardBill ? "—" : EntryFormat.account(recurring?.accountUid, data)
        let dueText = urgency == .overdue ? "Overdue · \(Format.dueDay(item.dueOn))" : Format.dueDay(item.dueOn)
        return HStack(spacing: 12) {
            Image(systemName: item.kind == .cardBill ? "creditcard" : item.kind == .subscription ? "play.rectangle" : "house")
                .font(.system(size: 12))
                .foregroundStyle(Color.kInk)
                .frame(width: 28, height: 28)
                .background(Color.kVoid, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.kEdge))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.grotesk(13, .medium)).foregroundStyle(Color.kInk).lineLimit(1).help(title)
                Text(subtitle).font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(paysFrom).font(.grotesk(12)).foregroundStyle(Color.kMuted).lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(dueText).font(.grotesk(12))
                .foregroundStyle(urgency == .overdue ? Color.kAlarm : urgency == .soon ? Color.kAmber : Color.kMuted)
                .frame(width: 120, alignment: .trailing)
            Text(Money.format(item.amountMinor, wholeUnits: true)).font(.mono(13)).foregroundStyle(Color.kInk)
                .frame(width: 100, alignment: .trailing)
            Color.clear.frame(width: 170, height: 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

/// A pending row's actions: Skip / Mark paid (or Pay bill…) on hover, everything on right-click.
struct PendingActions: ViewModifier {
    let item: PendingItem
    let finance: FinanceSync
    let model: AppModel
    let go: (Destination) -> Void
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? Color.kRaised : Color.clear)
            .overlay(alignment: .trailing) {
                if hovering {
                    HStack(spacing: 6) {
                        if item.kind == .cardBill {
                            Button("Pay bill…") { model.sheet = .payBill(statementUid: item.sourceUid) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Skip") { skip() }
                            Button { markPaid() } label: { Label("Mark paid", systemImage: "checkmark") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .controlSize(.small)
                    .tint(.kSynapse)
                    .padding(.trailing, 16)
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                if item.kind == .cardBill {
                    Button("Pay bill…") { model.sheet = .payBill(statementUid: item.sourceUid) }
                } else {
                    Button("Mark as paid") { markPaid() }
                    Button("Mark as paid…") { model.sheet = .markPaid(recurringUid: item.sourceUid, dueOn: item.dueOn) }
                    Button("Skip this time") { skip() }
                    Divider()
                    Button("Edit recurring payment…") { model.sheet = .recurring(item.sourceUid) }
                    Button("Show in Recurring") { model.selectedRecurringUid = item.sourceUid; go(.recurring) }
                }
            }
    }

    private func markPaid() { finance.apply(RecurringRules.markPaid(item.sourceUid, dueOn: item.dueOn, in: finance.data)) }
    private func skip() { finance.apply(RecurringRules.skip(item.sourceUid, dueOn: item.dueOn, in: finance.data)) }
}
