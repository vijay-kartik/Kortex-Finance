import KortexCloud
import KortexFinance
import SwiftUI

/// What the entries table's right-click menu, ⌫ and double-click do, on every screen that shows one:
/// Expenses, an account, a card. Delete waits on `deleting`'s confirmation (`DeleteEntriesConfirmation`).
@MainActor
enum EntryActions {
    static func perform(_ action: EntryAction, on uids: Set<String>, finance: FinanceSync, model: AppModel, deleting: Binding<[Entry]>) {
        switch action {
        case .edit(let uid):
            model.sheet = .editEntry(uid)
        case .markTransfer(let uid):
            model.sheet = .editEntry(uid, asTransfer: true)
        case .setCategory(let categoryUid):
            finance.apply(EntryRules.setCategory(uids, to: categoryUid, in: finance.data))
        case .delete:
            deleting.wrappedValue = uids.compactMap { finance.data.transactions[$0] }.filter { $0.type != .opening }
                .sorted { $0.occurredAtMillis > $1.occurredAtMillis }
        }
    }
}

/// Asks before deleting the entries in `deleting`, once for all of them, and takes them out of the selection.
struct DeleteEntriesConfirmation: ViewModifier {
    @Binding var deleting: [Entry]
    let finance: FinanceSync
    let model: AppModel

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
            Button(deleting.count == 1 ? "Delete Entry" : "Delete \(deleting.count) Entries", role: .destructive) {
                finance.apply(EntryRules.delete(deleting.map(\.uid), in: finance.data))
                model.selectedEntryUids.subtract(deleting.map(\.uid))
                deleting = []
            }
        } message: {
            Text(message)
        }
    }

    private var title: String {
        deleting.count == 1 ? "Delete \(EntryFormat.title(deleting[0], finance.data))?" : "Delete \(deleting.count) entries?"
    }

    private var message: String {
        if deleting.count == 1, let tx = deleting.first {
            return "\(EntryFormat.amount(tx)) on \(tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))). It's removed on your phone too."
        }
        let total = deleting.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let spent = total > 0 ? " Together they spent \(Money.format(total))." : ""
        return "They're removed on your phone too.\(spent)"
    }
}
