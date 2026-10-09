import KortexFinance
import SwiftUI

/// Shows whichever sheet the window asked for.
struct SheetHost: View {
    let sheet: Sheet
    let finance: any FinanceStore
    let model: AppModel
    let close: () -> Void

    var body: some View {
        let data = finance.data
        switch sheet {
        case .newEntry(let type):
            EntrySheet(finance: finance, type: type, close: close)
        case .editEntry(let uid, let asTransfer):
            if let entry = data.transactions[uid] { EntrySheet(finance: finance, editing: entry, asTransfer: asTransfer, close: close) } else { gone }
        case .payBill(let statementUid):
            PayBillSheet(finance: finance, statementUid: statementUid, close: close)
        case .markPaid(let recurringUid, let dueOn):
            MarkPaidSheet(finance: finance, recurringUid: recurringUid, dueOn: dueOn, close: close)
        case .recurring(let uid):
            RecurringSheet(finance: finance, editing: uid.flatMap { data.recurring[$0] }, close: close)
        case .category(let uid, let kind):
            CategorySheet(finance: finance, editing: uid.flatMap { data.categories[$0] }, kind: kind, close: close)
        case .deleteCategory(let uid):
            if let category = data.categories[uid] { DeleteCategorySheet(finance: finance, category: category, close: close) } else { gone }
        case .account(let uid, let kind):
            AccountSheet(finance: finance, editing: uid.flatMap { data.accounts[$0] }, kind: kind, close: close)
        case .receipt(let url):
            ReceiptSheet(finance: finance, file: url, close: close, enterManually: { model.sheet = .newEntry(.expense) })
        case .statement(let url, let into):
            StatementImportSheet(finance: finance, file: url, into: into, close: close)
        }
    }

    /// The record went away while the sheet was opening, deleted on another device.
    private var gone: some View {
        SheetChrome(title: "No longer there", subtitle: FinanceError.notFound.message, primary: "OK", onCancel: close, onPrimary: close) {
            EmptyView()
        }
    }
}

/// The toolbar's Add: a click adds an expense; the arrow offers everything else.
struct AddMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            Button("Expense") { model.sheet = .newEntry(.expense) }
            Button("Income") { model.sheet = .newEntry(.income) }
            Button("Transfer between accounts") { model.sheet = .newEntry(.transfer) }
            Button("Expense from a receipt…") { model.chooseReceipt() }
            Divider()
            Button("Recurring payment…") { model.sheet = .recurring(nil) }
            Button("Account or card…") { model.sheet = .account(nil, .bank) }
            Button("From a statement…") { model.chooseStatement() }
            Button("Category…") { model.sheet = .category(nil, .expense) }
        } label: {
            Label("Add", systemImage: "plus")
        } primaryAction: {
            model.sheet = .newEntry(.expense)
        }
        .menuStyle(.borderedButton)
        .fixedSize()
        .help("Add an expense (⌘N)")
    }
}

/// File › New: adding from anywhere in the window.
public struct NewEntryCommands: Commands {
    private let model: AppModel
    private let enabled: Bool

    public init(model: AppModel, enabled: Bool) {
        self.model = model
        self.enabled = enabled
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                Button("New Expense") { model.sheet = .newEntry(.expense) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Income") { model.sheet = .newEntry(.income) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Transfer") { model.sheet = .newEntry(.transfer) }
                Divider()
                Button("Scan Receipt…") { model.chooseReceipt() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("New Recurring Payment…") { model.sheet = .recurring(nil) }
                Button("New Account or Card…") { model.sheet = .account(nil, .bank) }
                Button("Import Statement…") { model.chooseStatement() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            .disabled(!enabled)
        }
    }
}
