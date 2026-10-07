import AppKit
import KortexFinance
import SwiftUI

/// The right-hand panel for a selected entry (Figma: Mac · Expenses › Inspector). Read-only for now;
/// Edit and Delete arrive with writing.
struct EntryInspector: View {
    let entry: Entry?
    let data: FinanceData
    var onEdit: ((Entry) -> Void)?
    var onDelete: ((Entry) -> Void)?

    var body: some View {
        Group {
            if let entry {
                ScrollView { details(entry).padding(20) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right").font(.system(size: 22, weight: .light)).foregroundStyle(Color.kMuted)
                    Text("Select an entry to see its details").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.kSidebar)
    }

    private func details(_ tx: Entry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(EntryFormat.kind(tx).uppercased()).sectionLabelStyle()
                Spacer()
                // Opening balances come with their account.
                if let onEdit, tx.type != .opening {
                    Button { onEdit(tx) } label: { Image(systemName: "pencil") }.help("Edit (⌘E)").keyboardShortcut("e", modifiers: .command)
                }
                if let onDelete, tx.type != .opening {
                    Button { onDelete(tx) } label: { Image(systemName: "trash") }.help("Delete (⌫)")
                }
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 4) {
                Text(EntryFormat.title(tx, data)).font(.grotesk(20, .medium)).foregroundStyle(Color.kInk)
                Text(EntryFormat.when(tx)).font(.grotesk(12)).foregroundStyle(Color.kMuted)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("AMOUNT").sectionLabelStyle()
                Text(Money.format(tx.amountMinor, currency: tx.currency))
                    .font(.grotesk(34, .medium))
                    .foregroundStyle(tx.type == .income ? Color.kGrowth : Color.kSynapse)
                    .textSelection(.enabled)
            }
            fields(tx)
            if let receipt = tx.receipt { receiptBox(receipt) }
            if let ref = tx.sourceRef {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REFERENCE").sectionLabelStyle()
                    Text(ref).font(.mono(12)).foregroundStyle(Color.kInk).textSelection(.enabled)
                }
            }
        }
    }

    private func fields(_ tx: Entry) -> some View {
        var rows: [(String, String)] = []
        switch tx.type {
        case .transfer, .cardPayment:
            rows.append(("From", EntryFormat.account(tx.accountUid, data)))
            rows.append(("To", EntryFormat.account(tx.toAccountUid, data)))
        case .income:
            rows.append(("Received in", EntryFormat.account(tx.accountUid, data)))
        default:
            rows.append(("Paid with", EntryFormat.account(tx.accountUid, data)))
        }
        if tx.type == .expense || tx.type == .income {
            rows.append(("Category", EntryFormat.category(tx, data)?.name ?? "Uncategorised"))
        }
        if tx.type == .cardPayment, !tx.isCardCredit {
            rows.append(("Bill", tx.statementUid.flatMap { data.statements[$0] }
                .map { "\($0.statementOn.date.formatted(.dateTime.day().month(.abbreviated))) bill" } ?? "None"))
        }
        if let uid = tx.recurringUid {
            rows.append(("Recurring", data.recurring[uid]?.name ?? "Deleted payment"))
        }
        if let merchant = tx.merchant, let note = tx.note, merchant != note {
            rows.append(("Note", note))
        }
        rows.append(("Added from", EntryFormat.sourceName(tx.source)))
        return VStack(spacing: 0) {
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

    private func receiptBox(_ r: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECEIPT · \(r.itemCount) ITEM\(r.itemCount == 1 ? "" : "S")").sectionLabelStyle()
            ForEach(Array(r.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.quantity > 1 ? "\(item.name) × \(item.quantity)" : item.name).font(.grotesk(12)).foregroundStyle(Color.kInk)
                    Spacer()
                    Text(Money.format(item.amountMinor)).font(.mono(12)).foregroundStyle(Color.kInk)
                }
            }
            if let tax = r.taxMinor {
                HStack {
                    Text("Tax").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                    Spacer()
                    Text(Money.format(tax)).font(.mono(12)).foregroundStyle(Color.kMuted)
                }
            }
            if let path = r.photoDevicePath {
                if FileManager.default.fileExists(atPath: path) {
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: { Label("Open receipt image", systemImage: "doc.text.image") }
                        .buttonStyle(.link)
                } else {
                    Text("The image stays on the device that scanned it.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
            }
        }
        .padding(14)
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.kEdge))
    }
}

/// The inspector when several entries are selected: how many, and what they add up to.
struct SelectionSummary: View {
    let entries: [Entry]

    var body: some View {
        let out = entries.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let inn = entries.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let uncategorised = entries.filter { ($0.type == .expense || $0.type == .income) && $0.categoryUid == nil }.count
        VStack(alignment: .leading, spacing: 16) {
            Text("\(entries.count) ENTRIES SELECTED").sectionLabelStyle()
            VStack(alignment: .leading, spacing: 4) {
                Text("SPENT").sectionLabelStyle()
                Text(Money.format(out)).font(.grotesk(34, .medium)).foregroundStyle(Color.kSynapse)
            }
            if inn > 0 { LabeledContent("Income", value: Money.format(inn)).font(.grotesk(13)) }
            if uncategorised > 0 { LabeledContent("Uncategorised", value: "\(uncategorised)").font(.grotesk(13)) }
            Text("Right-click the selection to change its category or delete it. ⇧↑ ⇧↓ extend it, ⌘A selects all.")
                .font(.grotesk(12)).foregroundStyle(Color.kMuted)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.kSidebar)
    }
}
