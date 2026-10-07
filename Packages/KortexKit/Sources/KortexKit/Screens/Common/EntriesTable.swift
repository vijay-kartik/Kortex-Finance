import KortexFinance
import SwiftUI

/// What the entries table's right-click menu asks for, on the entries it was opened on.
enum EntryAction {
    case edit(String)
    /// Open the edit sheet with the entry switched to Transfer.
    case markTransfer(String)
    /// File under this category; nil leaves them uncategorised.
    case setCategory(String?)
    case delete
}

/// The sortable entries table on Expenses and Accounts: Date, Description, Category, Paid with,
/// Source, Amount. Rows select as in Finder: ↑ ↓ move, ⇧↑ ⇧↓ extend, ⌘A selects all, ⌘- and ⇧-click
/// too. One selected row fills the inspector. With `onAction`, right-clicking offers Edit, Category,
/// Remove Category and Delete for the selection (or the row clicked outside it), and double-clicking
/// a row edits it.
struct EntriesTable: View {
    let entries: [Entry]
    let data: FinanceData
    @Binding var selection: Set<String>
    var showsAccount = true
    var focusOnAppear = false
    var onAction: ((EntryAction, Set<String>) -> Void)?

    @State private var sortOrder = [KeyPathComparator(\Entry.occurredAtMillis, order: .reverse)]
    @FocusState private var focused: Bool

    var body: some View {
        Table(entries.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.occurredAtMillis) { tx in
                Text(tx.occurredOn.date, format: .dateTime.day().month(.abbreviated))
                    .font(.mono(12))
                    .foregroundStyle(Color.kMuted)
            }
            .width(min: 56, ideal: 64, max: 80)

            TableColumn("Description") { tx in
                Text(EntryFormat.title(tx, data)).font(.grotesk(13)).foregroundStyle(Color.kInk).lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Category") { tx in
                if tx.type == .expense || tx.type == .income {
                    CategoryLabel(category: EntryFormat.category(tx, data))
                } else {
                    Text(EntryFormat.kind(tx)).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
            }
            .width(min: 90, ideal: 110)

            TableColumn(showsAccount ? "Paid with" : "Other side") { tx in
                Text(showsAccount ? EntryFormat.account(tx.accountUid, data) : (tx.toAccountUid.map { EntryFormat.account($0, data) } ?? ""))
                    .font(.grotesk(12))
                    .foregroundStyle(Color.kMuted)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Source") { tx in SourceChip(source: tx.source) }
                .width(min: 64, ideal: 80, max: 100)

            TableColumn("Amount", value: \.amountMinor) { tx in
                Text(EntryFormat.amount(tx))
                    .font(.mono(13))
                    .foregroundStyle(EntryFormat.amountColor(tx))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { uids in
            if let onAction { EntryMenu(uids: uids, data: data, act: { onAction($0, uids) }) }
        } primaryAction: { uids in
            if let onAction, uids.count == 1, let uid = uids.first, EntryMenu.canEdit(data.transactions[uid]) { onAction(.edit(uid), uids) }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(Color.kPanel)
        .focused($focused)
        .onAppear { if focusOnAppear { focused = true } }
    }
}

/// The right-click menu for the entries it was opened on. Category lists the categories that fit:
/// expense ones for expenses, income ones for income, both (labelled) when the selection mixes them.
/// Transfers, card bill payments and opening balances have no category; opening balances can't be deleted here.
private struct EntryMenu: View {
    let uids: Set<String>
    let data: FinanceData
    let act: (EntryAction) -> Void

    /// Opening balances come with their account.
    static func canEdit(_ tx: Entry?) -> Bool { tx.map { $0.type != .opening } ?? false }

    var body: some View {
        let txs = uids.compactMap { data.transactions[$0] }
        let expenses = txs.filter { $0.type == .expense }
        let income = txs.filter { $0.type == .income }
        let deletable = txs.filter { $0.type != .opening }
        if txs.count == 1, Self.canEdit(txs.first) {
            Button("Edit…") { act(.edit(txs[0].uid)) }
            if txs[0].type == .expense || txs[0].type == .income {
                Button("Mark as Transfer…") { act(.markTransfer(txs[0].uid)) }
            }
            Divider()
        }
        if !expenses.isEmpty {
            categories(.expense, title: income.isEmpty ? "Category" : "Category for \(count(expenses.count, "Expense"))", current: expenses)
        }
        if !income.isEmpty {
            categories(.income, title: expenses.isEmpty ? "Category" : "Category for \(count(income.count, "Income Entry", "Income Entries"))", current: income)
        }
        if (expenses + income).contains(where: { $0.categoryUid != nil }) {
            Button("Remove Category") { act(.setCategory(nil)) }
        }
        if !deletable.isEmpty {
            Divider()
            Button(deletable.count == 1 ? "Delete Entry…" : "Delete \(deletable.count) Entries…", role: .destructive) { act(.delete) }
        }
    }

    /// A submenu of `kind`'s categories, ticking the one every entry in `current` is already in.
    private func categories(_ kind: CategoryKind, title: String, current: [Entry]) -> some View {
        let shared = Set(current.map(\.categoryUid)).count == 1 ? current.first?.categoryUid : nil
        let list = data.categories.values.filter { $0.kind == kind }
            .sorted { ($0.builtIn ? 0 : 1, $0.sortOrder, $0.name) < ($1.builtIn ? 0 : 1, $1.sortOrder, $1.name) }
        return Menu(title) {
            ForEach(list) { c in
                Toggle(c.name, isOn: Binding(get: { shared == c.uid }, set: { _ in act(.setCategory(c.uid)) }))
            }
        }
    }

    private func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        n == 1 ? "1 \(one)" : "\(n) \(many ?? one + "s")"
    }
}
