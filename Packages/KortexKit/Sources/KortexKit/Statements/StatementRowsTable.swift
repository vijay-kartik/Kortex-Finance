import KortexFinance
import SwiftUI

/// Which rows the review table shows.
enum RowFilter: Hashable, CaseIterable {
    case all, toAdd, inKortex, toCheck

    func admits(_ row: ImportRow) -> Bool {
        switch self {
        case .all: true
        case .toAdd: row.include
        case .inKortex: row.match != nil
        case .toCheck: row.needsALook
        }
    }
}

extension ImportRow {
    /// Flagged against the printed balance, or possibly already in Kortex.
    var needsALook: Bool { issue != nil || match?.sure == false }
}

/// The review table for a statement import: every cell editable, rows to check highlighted.
struct StatementRowsTable: View {
    @Binding var draft: StatementImport
    let data: FinanceData
    let filter: RowFilter

    var body: some View {
        let isCard = draft.account.kind == .creditCard
        let rows = draft.rows.filter(filter.admits)
        let payFrom = data.accounts.values.filter { !$0.archived && !$0.kind.isCard }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        let cards = data.accounts.values.filter { !$0.archived && $0.kind == .creditCard }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        let mine = StatementImportRules.transferAccounts(into: draft.existingAccountUid, in: data)
        let payments = data.recurring.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Table(rows) {
            // Into an account you have, beside each tick: whether the row is already in Kortex.
            TableColumn("") { row in
                HStack(spacing: 8) {
                    Toggle("", isOn: bind(row, \.include)).labelsHidden().toggleStyle(.checkbox)
                    if draft.intoExisting { MatchChip(row: row, data: data) }
                }
            }
            .width(draft.intoExisting ? 124 : 22)

            TableColumn("Date") { row in
                DatePicker("", selection: dateBinding(row), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).font(.mono(11))
            }
            .width(min: 92, ideal: 100)

            TableColumn("Details") { row in
                HStack(spacing: 6) {
                    if let issue = row.issue {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.kAmber).help(issue)
                    }
                    TextField("", text: bind(row, \.description)).textFieldStyle(.plain).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Merchant") { row in
                TextField("—", text: bind(row, \.merchant)).textFieldStyle(.plain).font(.grotesk(12))
            }
            .width(min: 90, ideal: 130)

            TableColumn("Type") { row in
                Picker("", selection: kindBinding(row)) {
                    if isCard {
                        Text("Purchase").tag(ImportRow.Kind.expense)
                        Text("Bill payment").tag(ImportRow.Kind.cardPayment)
                        Text("Refund / credit").tag(ImportRow.Kind.cardCredit)
                    } else {
                        Text("Money out").tag(ImportRow.Kind.expense)
                        Text("Money in").tag(ImportRow.Kind.income)
                        if !mine.isEmpty || row.kind.isTransfer {
                            Text("Transfer out").tag(ImportRow.Kind.transferOut)
                            Text("Transfer in").tag(ImportRow.Kind.transferIn)
                        }
                        if !cards.isEmpty || row.kind == .cardPayment { Text("Card bill payment").tag(ImportRow.Kind.cardPayment) }
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
            .width(min: 96, ideal: 110)

            TableColumn(isCard ? "Category / paid from" : "Category / other account") { row in
                if row.kind.isTransfer {
                    Picker("", selection: otherAccountBinding(row, \.transferAccountUid)) {
                        Text("Choose account…").tag(String?.none)
                        ForEach(mine) { a in Text(EntryFormat.account(a.uid, data)).tag(String?.some(a.uid)) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                } else if row.kind == .cardPayment && !isCard {
                    Picker("", selection: otherAccountBinding(row, \.cardUid)) {
                        Text("Choose card…").tag(String?.none)
                        ForEach(cards) { c in Text(c.last4.map { "\(c.name) ••\($0)" } ?? c.name).tag(String?.some(c.uid)) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                } else if row.kind == .cardCredit {
                    Text("Lowers what the card owes").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        .help("A refund, reversal or cashback. The purchase it refunds still counts as spending.")
                } else if row.kind == .cardPayment {
                    Picker("", selection: otherAccountBinding(row, \.fromAccountUid)) {
                        Text("Unknown account").tag(String?.none)
                        ForEach(payFrom) { a in Text(a.name).tag(String?.some(a.uid)) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                } else {
                    let kind: CategoryKind = row.kind == .income ? .income : .expense
                    Picker("", selection: bind(row, \.categoryUid)) {
                        Text("Uncategorised").tag(String?.none)
                        ForEach(data.categories.values.filter { $0.kind == kind }.sorted { $0.name < $1.name }) { c in
                            Text(c.name).tag(String?.some(c.uid))
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                }
            }
            .width(min: 120, ideal: 150)

            TableColumn("Repeats") { row in
                if row.kind == .expense {
                    Picker("", selection: repeatsBinding(row)) {
                        Text("One-off").tag(ImportRepeats.no)
                        Divider()
                        Text("New subscription").tag(ImportRepeats.new(.subscription))
                        Text("New fixed payment").tag(ImportRepeats.new(.fixed))
                        if !payments.isEmpty {
                            Divider()
                            ForEach(payments) { r in Text("Pays \(r.name)").tag(ImportRepeats.pays(recurringUid: r.uid)) }
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                    .help("Recurring payments start or are paid when the account is added. Marking one row marks the merchant's other rows too.")
                }
            }
            .width(min: 110, ideal: 140)

            TableColumn("Amount") { row in
                TextField("", value: amountBinding(row), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).font(.mono(12))
                    .foregroundStyle(row.kind == .income ? Color.kGrowth : Color.kInk)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Balance") { row in
                Text(row.printedBalanceMinor.map { Money.format($0) } ?? "")
                    .font(.mono(11)).foregroundStyle(Color.kMuted).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // Bindings into `draft.rows` by row id, so the filtered view edits the real rows.

    private func index(_ row: ImportRow) -> Int? { draft.rows.firstIndex { $0.id == row.id } }

    private func bind<T>(_ row: ImportRow, _ path: WritableKeyPath<ImportRow, T>) -> Binding<T> {
        Binding(get: { index(row).map { draft.rows[$0][keyPath: path] } ?? row[keyPath: path] },
                set: { if let i = index(row) { draft.rows[i][keyPath: path] = $0 } })
    }

    private func dateBinding(_ row: ImportRow) -> Binding<Date> {
        Binding(get: { (index(row).map { draft.rows[$0].date } ?? row.date).date },
                set: { if let i = index(row) { draft.rows[i].date = LocalDay(date: $0) } })
    }

    /// Changing the type or amount is the reviewer settling the row: its warning goes.
    private func kindBinding(_ row: ImportRow) -> Binding<ImportRow.Kind> {
        Binding(get: { index(row).map { draft.rows[$0].kind } ?? row.kind },
                set: { if let i = index(row) {
                    draft.rows[i].kind = $0
                    draft.rows[i].issue = nil
                    if $0 == .cardPayment {
                        draft.rows[i].categoryUid = nil
                        // Your only card is the one a bank's bill payment paid.
                        let cards = data.accounts.values.filter { !$0.archived && $0.kind == .creditCard }
                        if draft.account.kind != .creditCard, draft.rows[i].cardUid == nil, cards.count == 1 { draft.rows[i].cardUid = cards.first?.uid }
                    }
                    if $0.isTransfer {
                        draft.rows[i].categoryUid = nil
                        draft.rows[i].otherSideMissing = false
                        // Your only other account is the one a transfer you chose is with.
                        let mine = StatementImportRules.transferAccounts(into: draft.existingAccountUid, in: data)
                        if draft.rows[i].transferAccountUid == nil, mine.count == 1 { draft.rows[i].transferAccountUid = mine.first?.uid }
                    }
                    if $0 == .cardCredit {
                        draft.rows[i].categoryUid = nil
                        draft.rows[i].fromAccountUid = nil
                    }
                    if $0 != .expense { draft.rows[i].repeats = .no }
                } })
    }

    /// A bill payment's other account. Choosing another one keeps the entry it was found to be as it is.
    private func otherAccountBinding(_ row: ImportRow, _ path: WritableKeyPath<ImportRow, String?>) -> Binding<String?> {
        Binding(get: { index(row).map { draft.rows[$0][keyPath: path] } ?? row[keyPath: path] },
                set: { if let i = index(row), draft.rows[i][keyPath: path] != $0 {
                    draft.rows[i][keyPath: path] = $0
                    if draft.rows[i].replaces != nil {
                        draft.rows[i].replaces = nil
                        draft.rows[i].issue = nil
                    }
                } })
    }

    private func repeatsBinding(_ row: ImportRow) -> Binding<ImportRepeats> {
        Binding(get: { index(row).map { draft.rows[$0].repeats } ?? row.repeats },
                set: { draft.setRepeats($0, forRow: row.id) })
    }

    private func amountBinding(_ row: ImportRow) -> Binding<Double> {
        Binding(get: { Double(index(row).map { draft.rows[$0].amountMinor } ?? row.amountMinor) / 100 },
                set: { if let i = index(row) {
                    draft.rows[i].amountMinor = Int64(($0 * 100).rounded())
                    draft.rows[i].issue = nil
                } })
    }
}

/// Whether a row is already in Kortex, when importing into an account you have. The tooltip names the entry.
private struct MatchChip: View {
    let row: ImportRow
    let data: FinanceData

    var body: some View {
        let (text, color): (String, Color) = switch row.match {
        case nil: ("New", .kGrowth)
        case .some(let m) where m.sure: ("Already there", .kMuted)
        case .some: ("Maybe there", .kAmber)
        }
        Text(text)
            .font(.grotesk(11, .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .help(help)
    }

    private var help: String {
        guard let m = row.match else { return "Not in Kortex yet: it will be added." }
        guard let tx = data.transactions[m.transactionUid] else { return m.reason }
        let entry = [EntryFormat.title(tx, data), Money.format(tx.amountMinor),
                     tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated)), EntryFormat.sourceName(tx.source)].joined(separator: " · ")
        let verdict = m.sure ? "Already in Kortex" : "Possibly already in Kortex"
        return "\(verdict) (\(m.reason.lowercased())): \(entry).\n" + (row.include
            ? "Ticked, so it will be added again as a second entry."
            : "Left out. Tick it to add it anyway.")
    }
}
