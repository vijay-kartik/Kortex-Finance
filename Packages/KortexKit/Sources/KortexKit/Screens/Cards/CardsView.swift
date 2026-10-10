import KortexFinance
import SwiftUI

/// Cards (Figma: Mac · Credit cards). The card, its limit and bill side by side, then its details and
/// statement history, then every entry on it. With more than one card, a picker in the toolbar
/// switches between them.
struct CardsView: View {
    let finance: any FinanceStore
    @Bindable var model: AppModel
    @State private var deleting: Account?
    /// Entries waiting on Delete's confirmation.
    @State private var deletingEntries: [Entry] = []

    var body: some View {
        let data = finance.data
        let cards = data.cards
        let selected = model.selectedCardUid.flatMap { data.accounts[$0] }.flatMap { $0.kind.isCard ? $0 : nil } ?? cards.first
        Group {
            if let card = selected {
                ScrollView {
                    CardDetail(card: card, data: data, selectedEntries: $model.selectedEntryUids,
                               onEntryAction: { EntryActions.perform($0, on: $1, finance: finance, model: model, deleting: $deletingEntries) },
                               onPayBill: { model.sheet = .payBill(statementUid: $0) },
                               onImport: { model.chooseStatement(into: card.uid) },
                               onEdit: { model.sheet = .account(card.uid, card.kind) },
                               onDelete: { deleting = card })
                        .padding(24)
                }
            } else {
                Text(finance.status == .loading ? "Syncing…" : "No cards yet. Add one in Kortex on your phone.")
                    .font(.grotesk(13)).foregroundStyle(Color.kMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.kVoid)
        .navigationTitle(cards.count == 1 || cards.isEmpty ? "Cards" : "Cards")
        .navigationSubtitle(cards.count == 1 ? "1 card" : "\(cards.count) cards")
        .modifier(DeleteAccountConfirmation(deleting: $deleting, finance: finance) { model.selectedCardUid = nil })
        .modifier(DeleteEntriesConfirmation(deleting: $deletingEntries, finance: finance, model: model))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.sheet = .account(nil, .creditCard) } label: { Label("Add card", systemImage: "plus") }
            }
            if cards.count > 1 {
                ToolbarItem(placement: .principal) {
                    Picker("Card", selection: Binding(get: { selected?.uid ?? "" }, set: { model.selectedCardUid = $0 })) {
                        ForEach(cards) { card in Text(card.last4.map { "\(card.name) ••\($0)" } ?? card.name).tag(card.uid) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

struct CardDetail: View {
    let card: Account
    let data: FinanceData
    @Binding var selectedEntries: Set<String>
    var onEntryAction: ((EntryAction, Set<String>) -> Void)?
    var onPayBill: ((String) -> Void)?
    /// Import statement…: add a statement's purchases and payments, leaving out those already here.
    var onImport: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        let txs = Array(data.transactions.values)
        let today = LocalDay.today()
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CardFace(card: card).frame(width: 420, height: 250)
                if card.kind == .creditCard {
                    creditOverview(txs: txs, today: today)
                } else {
                    debitOverview(txs: txs, today: today)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                details.frame(width: 420)
                if card.kind == .creditCard { statements(txs: txs, today: today) } else { recent(txs: txs) }
            }
            .fixedSize(horizontal: false, vertical: true)
            entries(txs: txs)
        }
    }

    /// Every entry on the card, in the same table as Expenses, with its right-click menu. A credit card's
    /// are what moves what it owes: purchases, bill payments, refunds. A debit card's are those made
    /// with it (its money moves on its bank, whose page has the rest).
    private func entries(txs: [Entry]) -> some View {
        let list = card.kind == .creditCard
            ? txs.filter { Balances.touches($0, card, accounts: data.accounts) }
            : txs.filter { $0.accountUid == card.uid || $0.toAccountUid == card.uid }
        // A table sizes to what it's given; in this scrolling page it's given a height for its rows.
        let height = min(max(CGFloat(list.count) * 28 + 34, 120), 520)
        return VStack(spacing: 0) {
            PanelHeader(title: "Entries on this card") {
                Text(list.count == 1 ? "1 entry" : "\(list.count) entries").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            if list.isEmpty {
                Text("Nothing on this card yet.").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                EntriesTable(entries: list, data: data, selection: $selectedEntries, onAction: onEntryAction)
                    .frame(height: height)
            }
        }
        .panelSurface(clipped: true)
    }

    // MARK: Credit

    private func creditOverview(txs: [Entry], today: LocalDay) -> some View {
        let position = Balances.cardPosition(card, transactions: txs, accounts: data.accounts)
        let statement = Statements.latest(for: card.uid, in: Array(data.statements.values))
        let unpaid = statement.map { Statements.unpaidMinor($0, txs) } ?? 0
        let spentSince = statement.map { Statements.spentSinceMinor(card, $0, txs, accounts: data.accounts) }
        let daysToDue = statement.map { today.days(to: $0.dueOn) }
        return KCard(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Credit limit overview").font(.grotesk(16, .medium)).foregroundStyle(Color.kInk)
                    Text(card.creditLimitMinor.map { "Total credit limit: \(Money.format($0))" } ?? "No limit set")
                        .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
                Spacer()
                if unpaid > 0, let days = daysToDue {
                    let overdue = days < 0
                    Label(overdue ? "Overdue by \(-days) day\(days == -1 ? "" : "s")" : days == 0 ? "Due today" : "Due in \(days) day\(days == 1 ? "" : "s")",
                          systemImage: "bell")
                        .font(.grotesk(12))
                        .foregroundStyle(overdue ? Color.kAlarm : Color.kAmber)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((overdue ? Color.kAlarm : Color.kAmber).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(alignment: .top, spacing: 32) {
                if let statement {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unpaid > 0 ? "Statement due · by \(Format.dueDay(statement.dueOn))" : "Statement paid")
                            .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        Text(Money.format(unpaid)).font(.grotesk(32, .medium)).foregroundStyle(Color.kInk)
                        if unpaid > 0 {
                            Text("Minimum \(Money.format(max(statement.minDueMinor - Statements.paidMinor(statement, txs), 0)))")
                                .font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        }
                    }
                }
                if let statement, let spentSince {
                    figure("Spent since \(statement.statementOn.date.formatted(.dateTime.day().month(.abbreviated))) statement", Money.format(spentSince))
                } else {
                    figure("Outstanding", Money.format(position.outstandingMinor))
                }
                if let available = position.availableMinor {
                    figure("Available limit", Money.format(available))
                }
            }
            if let utilisation = position.utilisation {
                HStack(spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.kRaised)
                            Capsule().fill(utilisation > 0.9 ? Color.kAlarm : Color.kSynapse)
                                .frame(width: max(6, geo.size.width * min(CGFloat(utilisation), 1)))
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.1f%% utilised", utilisation * 100)).font(.grotesk(12)).foregroundStyle(Color.kInk)
                }
            }
            if statement != nil, let spentSince, spentSince > 0 {
                Text("Outstanding \(Money.format(position.outstandingMinor)): the bill plus \(Money.format(spentSince)) spent since.")
                    .font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            if let statement, unpaid > 0, let onPayBill {
                Button { onPayBill(statement.uid) } label: { Text("Pay bill…").padding(.horizontal, 10) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.kSynapse)
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.grotesk(12)).foregroundStyle(Color.kMuted)
            Text(value).font(.mono(18)).foregroundStyle(Color.kInk)
        }
    }

    private func statements(txs: [Entry], today: LocalDay) -> some View {
        let list = data.statements.values.filter { $0.cardUid == card.uid }.sorted { $0.statementOn > $1.statementOn }
        return KCard(spacing: 0) {
            CardHeader(title: "Statements") {
                Text("From SMS and the statement date").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            .padding(.bottom, 10)
            if list.isEmpty {
                Text(card.statementDay == nil ? "Set a statement day on your phone to track bills." : "No statements yet.")
                    .font(.grotesk(12)).foregroundStyle(Color.kMuted)
            } else {
                HStack(spacing: 12) {
                    Text("STATEMENT").sectionLabelStyle().frame(maxWidth: .infinity, alignment: .leading)
                    Text("AMOUNT").sectionLabelStyle().frame(width: 110, alignment: .trailing)
                    Text("DUE").sectionLabelStyle().frame(width: 80, alignment: .trailing)
                    Text("STATUS").sectionLabelStyle().frame(width: 120, alignment: .trailing)
                }
                .padding(.bottom, 8)
                ForEach(list) { s in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            Text(s.statementOn.date.formatted(.dateTime.month(.wide).year()))
                                .font(.grotesk(13)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Money.format(s.totalDueMinor)).font(.mono(13)).foregroundStyle(Color.kInk).frame(width: 110, alignment: .trailing)
                            Text(s.dueOn.date.formatted(.dateTime.day().month(.abbreviated))).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                                .frame(width: 80, alignment: .trailing)
                            statusChip(s, txs: txs, today: today).frame(width: 120, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func statusChip(_ s: CardStatement, txs: [Entry], today: LocalDay) -> some View {
        let (text, color): (String, Color) = switch Statements.status(s, txs, today: today) {
        case .paid: (Statements.paidOn(s, txs).map { "Paid \($0.date.formatted(.dateTime.day().month(.abbreviated)))" } ?? "Paid", .kGrowth)
        case .partlyPaid: ("Part paid", .kAmber)
        case .overdue: ("Overdue", .kAlarm)
        case .due: ("Unpaid", .kAmber)
        }
        return Text(text)
            .font(.grotesk(11))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Debit

    private func debitOverview(txs: [Entry], today: LocalDay) -> some View {
        let month = today.yearMonth
        let spent = txs.filter { $0.type == .expense && $0.accountUid == card.uid && $0.occurredOn.isWithin(month.firstDay, today) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        return KCard(spacing: 14) {
            Text("Debit card").font(.grotesk(16, .medium)).foregroundStyle(Color.kInk)
            figure("Spent with this card in \(Format.monthName(month))", Money.format(spent))
            if let linked = card.linkedAccountUid.flatMap({ data.accounts[$0] }) {
                figure("Spends come out of \(linked.name)", Money.format(data.balanceMinor(of: linked)))
            } else {
                Text("Not linked to a bank account, so it keeps its own balance.").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
        }
    }

    private func recent(txs: [Entry]) -> some View {
        let list = txs.filter { $0.accountUid == card.uid && $0.type == .expense }.sorted { $0.occurredOn > $1.occurredOn }.prefix(8)
        return KCard(spacing: 0) {
            CardHeader("Spent with this card").padding(.bottom, 10)
            if list.isEmpty { Text("Nothing yet.").font(.grotesk(12)).foregroundStyle(Color.kMuted) }
            ForEach(Array(list)) { tx in
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        Text(EntryFormat.title(tx, data)).font(.grotesk(13)).foregroundStyle(Color.kInk)
                        Spacer()
                        Text(tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        Text(EntryFormat.amount(tx)).font(.mono(13)).foregroundStyle(Color.kInk).frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                }
            }
        }
    }

    // MARK: Details

    private var details: some View {
        var rows: [(String, String)] = [("Card holder", card.holder ?? "—"), ("Card number", card.last4.map { "•••• \($0)" } ?? "—")]
        if let bank = card.institution { rows.append(("Bank", bank)) }
        if let network = card.network { rows.append(("Network", network)) }
        if let expiry = card.expiry { rows.append(("Expires", expiry)) }
        if card.kind == .creditCard {
            if let day = card.statementDay { rows.append(("Statement date", "\(ordinal(day)) of every month")) }
            if let day = card.dueDay { rows.append(("Payment due", "\(ordinal(day)) of the next month")) }
            if let limit = card.creditLimitMinor { rows.append(("Credit limit", Money.format(limit))) }
        } else if let linked = card.linkedAccountUid {
            rows.append(("Linked account", EntryFormat.account(linked, data)))
        }
        return KCard(spacing: 0) {
            CardHeader(title: "Card details") {
                if let onImport, card.kind == .creditCard {
                    Button { onImport() } label: { Label("Import statement…", systemImage: "doc.text.magnifyingglass") }
                        .controlSize(.small)
                        .help("Add entries and the bill from this card's statement. Ones already in Kortex are found and left out.")
                }
                if let onEdit { Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }.controlSize(.small) }
                if let onDelete {
                    Menu {
                        Button("Delete card…", role: .destructive) { onDelete() }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            .padding(.bottom, 10)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        Text(row.0).font(.grotesk(13)).foregroundStyle(Color.kMuted)
                        Spacer()
                        Text(row.1).font(.grotesk(13)).foregroundStyle(Color.kInk).textSelection(.enabled)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
        return "\(n)\(suffix)"
    }
}

/// The card itself: a periwinkle gradient with its name, last four digits, holder and expiry.
struct CardFace: View {
    let card: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(card.name.uppercased()).font(.grotesk(16, .medium)).foregroundStyle(Color.kInk).lineLimit(1)
                Spacer()
                Text(card.network ?? "").font(.grotesk(13, .medium)).foregroundStyle(Color.kInk.opacity(0.8))
                Image(systemName: "creditcard").foregroundStyle(Color.kInk)
            }
            Spacer()
            HStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { _ in Text("••••").font(.mono(20)).foregroundStyle(Color.kInk) }
                Text(card.last4 ?? "····").font(.mono(26)).foregroundStyle(Color.kInk)
            }
            Spacer().frame(height: 20)
            HStack(alignment: .top, spacing: 36) {
                labelled("CARD HOLDER", card.holder ?? "—")
                labelled("EXPIRES", card.expiry ?? "—")
                labelled(card.kind == .creditCard ? "BANK" : "DEBIT", card.institution ?? "—")
            }
        }
        .padding(24)
        .background(
            LinearGradient(colors: [Color(hex: 0x2A3063), Color(hex: 0x171B33)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.kSynapse.opacity(0.45)))
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabelStyle(.kSynapse)
            Text(value).font(.grotesk(14, .medium)).foregroundStyle(Color.kInk).lineLimit(1)
        }
    }
}
