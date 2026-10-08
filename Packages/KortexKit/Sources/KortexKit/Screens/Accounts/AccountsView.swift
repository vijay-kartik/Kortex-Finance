import Charts
import KortexCloud
import KortexFinance
import SwiftUI

/// Accounts (Figma: Mac · Accounts). The account cards on the left, the selected one's balance trend,
/// this month's in and out, and its entries on the right. Cards live on their own screen.
struct AccountsView: View {
    let finance: FinanceSync
    @Bindable var model: AppModel
    @State private var deleting: Account?
    /// Entries waiting on Delete's confirmation.
    @State private var deletingEntries: [Entry] = []

    var body: some View {
        let data = finance.data
        let accounts = data.moneyAccounts
        let selected = model.selectedAccountUid.flatMap { data.accounts[$0] }.flatMap { $0.kind.isCard ? nil : $0 } ?? accounts.first
        HStack(spacing: 0) {
            list(accounts, selected: selected, data: data)
                .frame(width: 360)
            Rectangle().fill(Color.kEdge).frame(width: 1)
            if let selected {
                AccountDetail(account: selected, data: data, selectedEntry: $model.selectedEntryUids,
                              onEntryAction: { EntryActions.perform($0, on: $1, finance: finance, model: model, deleting: $deletingEntries) },
                              onImport: { model.chooseStatement(into: $0.uid) },
                              onEdit: { model.sheet = .account($0.uid, $0.kind) }, onDelete: { deleting = $0 })
            } else {
                Text(finance.status == .loading ? "Syncing…" : "No accounts yet. Add one in Kortex on your phone.")
                    .font(.grotesk(13)).foregroundStyle(Color.kMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.kVoid)
        .navigationTitle("Accounts")
        .navigationSubtitle(accounts.count == 1 ? "1 account" : "\(accounts.count) accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add account…") { model.sheet = .account(nil, .bank) }
                    Button("From a statement…") { model.chooseStatement() }
                } label: {
                    Label("Add account", systemImage: "plus")
                } primaryAction: {
                    model.sheet = .account(nil, .bank)
                }
                .help("Add an account, or read one in from a statement")
            }
        }
        .modifier(DeleteAccountConfirmation(deleting: $deleting, finance: finance) {
            model.selectedAccountUid = nil
        })
        .modifier(DeleteEntriesConfirmation(deleting: $deletingEntries, finance: finance, model: model))
    }

    private func list(_ accounts: [Account], selected: Account?, data: FinanceData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                KCard(spacing: 6) {
                    Text("TOTAL BALANCE").sectionLabelStyle()
                    Text(Money.format(data.totalBalanceMinor)).font(.grotesk(30, .medium)).foregroundStyle(Color.kInk)
                    Text("Updated from your entries, SMS and receipts").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
                Text("Your accounts").font(.grotesk(15, .medium)).foregroundStyle(Color.kInk).padding(.top, 8).padding(.horizontal, 4)
                ForEach(accounts) { account in
                    Button { model.selectedAccountUid = account.uid } label: {
                        AccountCard(account: account, data: data, selected: account.uid == selected?.uid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }
}

struct AccountCard: View {
    let account: Account
    let data: FinanceData
    let selected: Bool

    var body: some View {
        let today = LocalDay.today()
        let series = Balances.dailySeries(of: account, transactions: data.ledgerEntries(of: account), accounts: data.accounts,
                                          from: today.adding(days: -29), to: today)
        let trendUp = (series.last?.minor ?? 0) >= (series.first?.minor ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AccountIcon(kind: account.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.grotesk(14, .medium)).foregroundStyle(Color.kInk).lineLimit(1)
                    Text(AccountText.subtitle(account)).font(.grotesk(12)).foregroundStyle(Color.kMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Money.format(data.balanceMinor(of: account))).font(.mono(14)).foregroundStyle(Color.kInk)
            }
            HStack {
                Text(AccountText.lastActivity(account, data)).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                Spacer()
                Sparkline(values: series.map(\.minor), color: trendUp ? .kGrowth : .kAlarm)
                    .frame(width: 64, height: 20)
            }
        }
        .padding(16)
        .background(selected ? Color.kSynapseDim : Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.kSynapse : Color.kEdge))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AccountDetail: View {
    let account: Account
    let data: FinanceData
    @Binding var selectedEntry: Set<String>
    var onEntryAction: ((EntryAction, Set<String>) -> Void)?
    /// Import statement…: add a statement's entries, leaving out those already here.
    var onImport: ((Account) -> Void)?
    var onEdit: ((Account) -> Void)?
    var onDelete: ((Account) -> Void)?
    @State private var range = 30

    var body: some View {
        let today = LocalDay.today()
        let entries = data.ledgerEntries(of: account)
        let month = today.yearMonth
        let flow = Balances.flow(of: account, transactions: entries, accounts: data.accounts, from: month.firstDay, to: today)
        let lastFlow = Balances.flow(of: account, transactions: entries, accounts: data.accounts,
                                     from: month.adding(months: -1).firstDay, to: month.adding(months: -1).lastDay)
        let series = Balances.dailySeries(of: account, transactions: entries, accounts: data.accounts, from: today.adding(days: -(range - 1)), to: today)
        let balance = data.balanceMinor(of: account)
        let change = balance - (series.first?.minor ?? balance)
        let monthName = Format.monthName(month).uppercased()

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AccountIcon(kind: account.kind, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.grotesk(20, .medium)).foregroundStyle(Color.kInk)
                    Text(AccountText.detailLine(account)).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
                Spacer()
                if let onImport, account.kind == .bank {
                    Button { onImport(account) } label: { Label("Import statement…", systemImage: "doc.text.magnifyingglass") }
                        .help("Add entries from this account's statement. Ones already in Kortex are found and left out.")
                }
                if let onEdit { Button { onEdit(account) } label: { Label("Edit", systemImage: "pencil") } }
                if let onDelete {
                    Menu {
                        Button("Delete account…", role: .destructive) { onDelete(account) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            KCard(spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BALANCE").sectionLabelStyle()
                        Text(Money.format(balance)).font(.grotesk(30, .medium)).foregroundStyle(Color.kInk)
                    }
                    Text("\(Money.format(change, signed: true)) in \(range == 365 ? "a year" : "\(range) days")")
                        .font(.grotesk(12))
                        .foregroundStyle(change >= 0 ? Color.kGrowth : Color.kAlarm)
                    Spacer()
                    Picker("Range", selection: $range) {
                        Text("30D").tag(30)
                        Text("90D").tag(90)
                        Text("1Y").tag(365)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                BalanceChart(series: series)
                    .frame(height: 160)
            }
            HStack(alignment: .top, spacing: 16) {
                KPITile(label: "IN · \(monthName)", value: Money.format(flow.inMinor),
                        sub: flow.inCount == 1 ? "1 entry" : "\(flow.inCount) entries")
                KPITile(label: "OUT · \(monthName)", value: Money.format(flow.outMinor),
                        sub: flow.outCount == 1 ? "1 entry" : "\(flow.outCount) entries")
                KPITile(label: "NET", value: Money.format(flow.netMinor, signed: true),
                        sub: "vs \(Money.format(lastFlow.netMinor, signed: true)) in \(Format.monthName(month.adding(months: -1)))",
                        subColor: .kMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                HStack {
                    Text("Entries in this account").font(.grotesk(15, .medium)).foregroundStyle(Color.kInk)
                    Spacer()
                    Text(entries.count == 1 ? "1 entry" : "\(entries.count) entries").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Hairline()
                EntriesTable(entries: entries, data: data, selection: $selectedEntry, onAction: onEntryAction)
            }
            .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kEdge))
            .frame(minHeight: 220)
        }
        .padding(24)
    }
}

/// The balance trend: a line with a soft synapse fill, its last point marked.
struct BalanceChart: View {
    let series: [(day: LocalDay, minor: Int64)]

    private struct Point: Identifiable {
        let date: Date
        let rupees: Double
        var id: Date { date }
    }

    var body: some View {
        let points = series.map { Point(date: $0.day.date, rupees: Double($0.minor) / 100) }
        let low = points.map(\.rupees).min() ?? 0
        let high = points.map(\.rupees).max() ?? 0
        let pad = max((high - low) * 0.15, 1)
        Chart(points) { p in
            AreaMark(x: .value("Day", p.date), yStart: .value("Base", low - pad), yEnd: .value("Balance", p.rupees))
                .foregroundStyle(LinearGradient(colors: [Color.kSynapse.opacity(0.28), Color.kSynapse.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", p.date), y: .value("Balance", p.rupees))
                .foregroundStyle(Color.kSynapse)
                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            if p.id == points.last?.id {
                PointMark(x: .value("Day", p.date), y: .value("Balance", p.rupees)).foregroundStyle(Color.kSynapse)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.mono(10)).foregroundStyle(Color.kMuted)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.kEdge) }
        }
    }
}

struct Sparkline: View {
    let values: [Int64]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let low = Double(values.min() ?? 0), high = Double(values.max() ?? 0)
            let span = max(high - low, 1)
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = values.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(values.count - 1) : 0
                    let y = geo.size.height * (1 - CGFloat((Double(v) - low) / span))
                    i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct AccountIcon: View {
    let kind: AccountKind
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: AccountText.symbol(kind))
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(Color.kInk)
            .frame(width: size, height: size)
            .background(Color.kVoid, in: RoundedRectangle(cornerRadius: size / 4))
            .overlay(RoundedRectangle(cornerRadius: size / 4).strokeBorder(Color.kEdge))
    }
}

enum AccountText {
    static func symbol(_ kind: AccountKind) -> String {
        switch kind {
        case .bank: "building.columns"
        case .cash: "banknote"
        case .wallet: "wallet.bifold"
        case .creditCard, .debitCard: "creditcard"
        }
    }

    static func kind(_ a: Account) -> String {
        switch a.kind {
        case .bank: a.bankType == .current ? "Current account" : "Savings account"
        case .cash: "Cash"
        case .wallet: "Wallet"
        case .creditCard: "Credit card"
        case .debitCard: "Debit card"
        }
    }

    /// "HDFC Bank ••4471", or the kind when there's no bank.
    static func subtitle(_ a: Account) -> String {
        let bank = [a.institution, a.last4.map { "••\($0)" }].compactMap { $0 }.joined(separator: " ")
        return bank.isEmpty ? kind(a) : bank
    }

    static func detailLine(_ a: Account) -> String {
        [subtitle(a) == kind(a) ? nil : subtitle(a), kind(a), a.ifsc.map { "IFSC \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    static func lastActivity(_ a: Account, _ data: FinanceData) -> String {
        guard let day = data.lastEntryOn(of: a) else { return "No entries yet" }
        let today = LocalDay.today()
        if day == today { return "Last entry today" }
        if day == today.adding(days: -1) { return "Last entry yesterday" }
        return "Last entry \(day.date.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// Delete account (Figma: Delete account): its entries stay in history.
struct DeleteAccountConfirmation: ViewModifier {
    @Binding var deleting: Account?
    let finance: FinanceSync
    let onDeleted: () -> Void

    func body(content: Content) -> some View {
        let found = deleting.map { AccountRules.leftovers(of: [$0.uid], in: finance.data) }
        let n = found?.entries.count ?? 0
        return content.confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if found?.isEmpty == false {
                Button(n == 0 ? "Delete Account and Its Entries" : n == 1 ? "Delete Account and Its Entry" : "Delete Account and Its \(n) Entries",
                       role: .destructive) { delete(withEntries: true) }
                Button("Delete Account, Keep Entries") { delete(withEntries: false) }
            } else {
                Button("Delete", role: .destructive) { delete(withEntries: false) }
            }
        } message: {
            Text(message(found))
        }
    }

    private func delete(withEntries: Bool) {
        if let a = deleting { finance.apply(AccountRules.delete(a.uid, withEntries: withEntries, in: finance.data)); onDeleted() }
        deleting = nil
    }

    private func message(_ found: AccountRules.Leftovers?) -> String {
        guard let found, !found.isEmpty else { return "This removes it on your phone too." }
        var text = "Delete its entries too, or keep them in your history, shown as from a deleted account."
        let kept = found.relabeled.count
        if kept > 0 {
            text += " Deleting them keeps \(kept == 1 ? "1 transfer or payment" : "\(kept) transfers and payments") with accounts you "
                + "still have, shown as from an unknown account, so those balances don't change."
        }
        return text + " This applies on your phone too."
    }
}
