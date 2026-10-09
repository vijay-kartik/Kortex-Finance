import KortexFinance
import SwiftUI

/// Recurring payments (Figma: Mac · Recurring). What recurring costs each month, every subscription
/// and fixed expense in a table, and the selected one in the inspector with its payment history.
struct RecurringView: View {
    let finance: any FinanceStore
    @Bindable var model: AppModel

    @State private var filter: Filter = .all
    @State private var showsInspector = true
    @State private var deleting: Recurring?

    enum Filter: Hashable { case all, subscriptions, fixed }

    var body: some View {
        let data = finance.data
        let today = LocalDay.today()
        let all = data.recurring.values.sorted { ($0.nextDueOn, $0.name) < ($1.nextDueOn, $1.name) }
        let shown = all.filter {
            switch filter {
            case .all: true
            case .subscriptions: $0.kind == .subscription
            case .fixed: $0.kind == .fixed
            }
        }
        let horizon = today.yearMonth.lastDay
        let thisMonth = shown.filter { !$0.paused && $0.nextDueOn <= horizon }
        let later = shown.filter { !$0.paused && $0.nextDueOn > horizon }
        let paused = shown.filter(\.paused)
        let totals = RecurringSchedule.totals(all)

        VStack(spacing: 16) {
            summary(totals, all: all, data: data)
            VStack(spacing: 0) {
                header
                Hairline()
                if all.isEmpty {
                    Text(finance.status == .loading ? "Syncing…" : "No recurring payments yet. Add subscriptions and fixed expenses on your phone.")
                        .font(.grotesk(13)).foregroundStyle(Color.kMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $model.selectedRecurringUid) {
                        group("DUE THIS MONTH", thisMonth, data: data, today: today)
                        group("LATER", later, data: data, today: today)
                        group("PAUSED", paused, data: data, today: today)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                Hairline()
                Text("Card bills come from each card’s statement, so they aren’t listed here.")
                    .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kEdge))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.kVoid)
        .navigationTitle("Recurring payments")
        .navigationSubtitle("Subscriptions and fixed expenses")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    Text("All \(all.count)").tag(Filter.all)
                    Text("Subs \(all.filter { $0.kind == .subscription }.count)").tag(Filter.subscriptions)
                    Text("Fixed \(all.filter { $0.kind == .fixed }.count)").tag(Filter.fixed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.sheet = .recurring(nil) } label: { Label("Add", systemImage: "plus") }
                    .help("Add a recurring payment")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
            }
        }
        .sidePanel(isPresented: showsInspector) {
            RecurringInspector(recurring: model.selectedRecurringUid.flatMap { data.recurring[$0] }, data: data,
                               onEdit: { model.sheet = .recurring($0.uid) },
                               onPause: { finance.apply(RecurringRules.setPaused($0.uid, !$0.paused, in: finance.data)) },
                               onDelete: { deleting = $0 })
        }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete recurring payment", role: .destructive) {
                if let r = deleting { finance.apply(RecurringRules.delete(r.uid, in: finance.data)); model.selectedRecurringUid = nil }
                deleting = nil
            }
        } message: {
            Text("Payments already recorded stay in your expenses.")
        }
    }

    private func summary(_ t: RecurringTotals, all: [Recurring], data: FinanceData) -> some View {
        let next = all.filter { !$0.paused }.min { $0.nextDueOn < $1.nextDueOn }
        return KCard(spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECURRING EACH MONTH").sectionLabelStyle()
                    Text(Money.format(t.perMonthMinor, wholeUnits: true)).font(.grotesk(32, .medium)).foregroundStyle(Color.kInk)
                        .lineLimit(1).fixedSize()
                }
                figure("Over a year", Money.format(t.perYearMinor, wholeUnits: true))
                figure("Next due", next.map { "\($0.name) · \($0.nextDueOn.date.formatted(.dateTime.day().month(.abbreviated)))" } ?? "—")
                    .layoutPriority(-1)
                Spacer()
            }
            SplitBar(first: t.subscriptionsPerMonthMinor, rest: t.fixedPerMonthMinor)
            HStack(spacing: 24) {
                LegendRow(.kSynapse, "Subscriptions · \(t.subscriptionCount)", t.subscriptionsPerMonthMinor)
                LegendRow(Color.kSynapse.opacity(0.5), "Fixed expenses · \(t.fixedCount)", t.fixedPerMonthMinor)
                Spacer()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.grotesk(12)).foregroundStyle(Color.kMuted)
            Text(value).font(.mono(16)).foregroundStyle(Color.kInk).lineLimit(1).truncationMode(.middle).help(value)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 28, height: 1)
            Text("NAME").sectionLabelStyle().frame(maxWidth: .infinity, alignment: .leading)
            Text("REPEATS").sectionLabelStyle().frame(width: 110, alignment: .leading)
            Text("PAID FROM").sectionLabelStyle().frame(width: 150, alignment: .leading)
            Text("NEXT DUE").sectionLabelStyle().frame(width: 110, alignment: .trailing)
            Text("AMOUNT").sectionLabelStyle().frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [Recurring], data: FinanceData, today: LocalDay) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { r in
                    row(r, data: data, today: today).tag(r.uid)
                        .contextMenu {
                            if !r.paused {
                                Button("Mark \(Format.dueDay(r.nextDueOn)) as paid") { finance.apply(RecurringRules.markPaid(r.uid, dueOn: r.nextDueOn, in: finance.data)) }
                                Button("Skip \(Format.dueDay(r.nextDueOn))") { finance.apply(RecurringRules.skip(r.uid, dueOn: r.nextDueOn, in: finance.data)) }
                                Divider()
                            }
                            Button("Edit…") { model.sheet = .recurring(r.uid) }
                            Button(r.paused ? "Resume" : "Pause") { finance.apply(RecurringRules.setPaused(r.uid, !r.paused, in: finance.data)) }
                            Button("Delete…", role: .destructive) { deleting = r }
                        }
                }
            } header: {
                Text(title).sectionLabelStyle().padding(.top, 6)
            }
        }
    }

    private func row(_ r: Recurring, data: FinanceData, today: LocalDay) -> some View {
        let urgency = Pending.urgency(r.nextDueOn, today: today)
        return HStack(spacing: 12) {
            Image(systemName: r.kind == .subscription ? "play.rectangle" : "house")
                .font(.system(size: 12)).foregroundStyle(Color.kInk)
                .frame(width: 28, height: 28)
                .background(Color.kVoid, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.kEdge))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.grotesk(13, .medium)).foregroundStyle(Color.kInk).lineLimit(1).truncationMode(.tail).help(r.name)
                Text(EntryFormat.categoryName(r.categoryUid, data) ?? (r.kind == .subscription ? "Subscription" : "Fixed"))
                    .font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(RecurringSchedule.repeatsLabel(r)).font(.grotesk(12)).foregroundStyle(Color.kMuted).frame(width: 110, alignment: .leading)
            Text(EntryFormat.account(r.accountUid, data)).font(.grotesk(12)).foregroundStyle(Color.kMuted).lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(r.paused ? "Paused" : Format.dueDay(r.nextDueOn)).font(.grotesk(12))
                .foregroundStyle(r.paused ? Color.kMuted : urgency == .overdue ? Color.kAlarm : urgency == .soon ? Color.kAmber : Color.kMuted)
                .frame(width: 110, alignment: .trailing)
            Text(Money.format(r.amountMinor, currency: r.currency, wholeUnits: true)).font(.mono(13)).foregroundStyle(Color.kInk)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .opacity(r.paused ? 0.6 : 1)
    }
}

/// The selected recurring payment, laid out like the Add recurring form, plus what's been paid.
struct RecurringInspector: View {
    let recurring: Recurring?
    let data: FinanceData
    var onEdit: ((Recurring) -> Void)?
    var onPause: ((Recurring) -> Void)?
    var onDelete: ((Recurring) -> Void)?

    var body: some View {
        Group {
            if let r = recurring {
                ScrollView { details(r).padding(20) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.2.squarepath").font(.system(size: 22, weight: .light)).foregroundStyle(Color.kMuted)
                    Text("Select a payment to see its details").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.kSidebar)
    }

    private func details(_ r: Recurring) -> some View {
        let payments = data.transactions.values.filter { $0.recurringUid == r.uid }.sorted { $0.occurredOn > $1.occurredOn }
        let rows: [(String, String)] = [
            ("Type", r.kind == .subscription ? "Subscription" : "Fixed expense"),
            ("Repeats", RecurringSchedule.repeatsLabel(r)),
            ("Next due", r.paused ? "Paused" : r.nextDueOn.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())),
            ("Paid from", EntryFormat.account(r.accountUid, data)),
            ("Category", EntryFormat.categoryName(r.categoryUid, data) ?? "Uncategorised"),
            ("Remind me", RecurringSchedule.reminderLabel(r.remindDaysBefore)),
            ("Mark paid automatically", r.autoMarkPaid ? "On" : "Off"),
        ]
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("RECURRING PAYMENT").sectionLabelStyle()
                Spacer()
                if let onEdit { Button { onEdit(r) } label: { Image(systemName: "pencil") }.help("Edit") }
                if let onPause { Button { onPause(r) } label: { Image(systemName: r.paused ? "play" : "pause") }.help(r.paused ? "Resume" : "Pause") }
                if let onDelete { Button { onDelete(r) } label: { Image(systemName: "trash") }.help("Delete") }
            }
            .buttonStyle(.borderless)
            Text(r.name).font(.grotesk(20, .medium)).foregroundStyle(Color.kInk).lineLimit(3).textSelection(.enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("AMOUNT").sectionLabelStyle()
                Text(Money.format(r.amountMinor, currency: r.currency)).font(.grotesk(30, .medium)).foregroundStyle(Color.kSynapse)
                Text("\(Money.format(RecurringSchedule.perMonthMinor(r), currency: r.currency)) a month")
                    .font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            FieldList(rows: rows)
            VStack(alignment: .leading, spacing: 8) {
                Text("PAYMENTS MADE").sectionLabelStyle()
                if payments.isEmpty {
                    Text("None recorded yet.").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
                ForEach(payments.prefix(12)) { tx in
                    HStack {
                        Text((tx.dueOn ?? tx.occurredOn).date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.grotesk(12)).foregroundStyle(Color.kInk)
                        Spacer()
                        Text(Money.format(tx.amountMinor, currency: tx.currency)).font(.mono(12)).foregroundStyle(Color.kInk)
                    }
                }
            }
        }
    }
}

/// Label–value rows in a bordered box, as in the Figma inspectors.
struct FieldList: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Hairline() }
                HStack(alignment: .top) {
                    Text(row.0).font(.grotesk(13)).foregroundStyle(Color.kMuted)
                    Spacer(minLength: 12)
                    Text(row.1).font(.grotesk(13)).foregroundStyle(Color.kInk).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.kEdge))
    }
}
