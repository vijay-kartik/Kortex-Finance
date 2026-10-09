import KortexFinance
import SwiftUI

/// Pay card bill (Figma: Recurring 04): full, minimum or any amount, from one of your accounts.
/// It moves money between your accounts; the purchases were already counted as spending.
struct PayBillSheet: View {
    let finance: any FinanceStore
    let statementUid: String
    let close: () -> Void

    enum Choice: Hashable { case full, minimum, other }

    @State private var choice: Choice = .full
    @State private var other = ""
    @State private var fromUid: String
    @State private var date = Date()
    @State private var error: String?

    init(finance: any FinanceStore, statementUid: String, close: @escaping () -> Void) {
        self.finance = finance
        self.statementUid = statementUid
        self.close = close
        let banks = finance.data.accounts.values.filter { !$0.archived && $0.kind != .creditCard && !$0.kind.isCard }
            .sorted { $0.createdAtMillis < $1.createdAtMillis }
        _fromUid = State(initialValue: banks.first?.uid ?? "")
    }

    var body: some View {
        let data = finance.data
        let txs = Array(data.transactions.values)
        let statement = data.statements[statementUid]
        let unpaid = statement.map { Statements.unpaidMinor($0, txs) } ?? 0
        let minimum = statement.map { max($0.minDueMinor - Statements.paidMinor($0, txs), 0) } ?? 0
        let card = statement.flatMap { data.accounts[$0.cardUid] }
        let from = data.accounts.values.filter { !$0.archived && !$0.kind.isCard }.sorted { $0.createdAtMillis < $1.createdAtMillis }

        SheetChrome(
            title: "Pay card bill",
            subtitle: card.map { c in "\(c.last4.map { "\(c.name) ••\($0)" } ?? c.name) · due \(statement.map { Format.dueDay($0.dueOn) } ?? "")" },
            primary: "Record payment",
            error: error,
            onCancel: close,
            onPrimary: { save(unpaid: unpaid, minimum: minimum) }
        ) {
            Section {
                Picker("Amount", selection: $choice) {
                    Text("Full bill · \(Money.format(unpaid))").tag(Choice.full)
                    if minimum > 0 && minimum < unpaid { Text("Minimum · \(Money.format(minimum))").tag(Choice.minimum) }
                    Text("Other amount").tag(Choice.other)
                }
                .pickerStyle(.radioGroup)
                if choice == .other { AmountField(label: "Amount", text: $other) }
            }
            Section {
                AccountPicker(label: "Paid from", selection: $fromUid, accounts: from)
                DatePicker("Paid on", selection: $date, in: ...Date(), displayedComponents: .date)
            } footer: {
                Text("A bill payment isn't spending: the purchases on the card already were.")
                    .font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
        }
    }

    private func save(unpaid: Int64, minimum: Int64) {
        let amount: Int64? = switch choice {
        case .full: unpaid
        case .minimum: minimum
        case .other: Money.parseMinor(other)
        }
        guard let amount, amount > 0 else { error = FinanceError.invalidAmount.message; return }
        let result = EntryRules.payBill(statementUid: statementUid, amountMinor: amount, from: fromUid, paidOn: LocalDay(date: date), in: finance.data)
        if let failure = finance.apply(result) { error = failure.message } else { close() }
    }
}

/// Mark as paid with a different amount, account or day (Figma: Recurring 03).
struct MarkPaidSheet: View {
    let finance: any FinanceStore
    let recurringUid: String
    let dueOn: LocalDay
    let close: () -> Void

    @State private var amount: String
    @State private var fromUid: String
    @State private var date = Date()
    @State private var error: String?

    init(finance: any FinanceStore, recurringUid: String, dueOn: LocalDay, close: @escaping () -> Void) {
        self.finance = finance
        self.recurringUid = recurringUid
        self.dueOn = dueOn
        self.close = close
        let r = finance.data.recurring[recurringUid]
        _amount = State(initialValue: r.map { Money.editable($0.amountMinor) } ?? "")
        _fromUid = State(initialValue: r?.accountUid ?? "")
    }

    var body: some View {
        let data = finance.data
        let r = data.recurring[recurringUid]
        let accounts = data.accounts.values.filter { !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        SheetChrome(
            title: "Mark \(r?.name ?? "payment") as paid",
            subtitle: "Due \(Format.dueDay(dueOn))",
            primary: "Mark as paid",
            error: error,
            onCancel: close,
            onPrimary: save
        ) {
            Section {
                AmountField(label: "Amount", text: $amount)
                AccountPicker(label: "Paid with", selection: $fromUid, accounts: accounts)
                DatePicker("Paid on", selection: $date, in: ...Date(), displayedComponents: .date)
            } footer: {
                Text("Records the expense and moves the next due date on.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
        }
    }

    private func save() {
        guard let minor = Money.parseMinor(amount), minor > 0 else { error = FinanceError.invalidAmount.message; return }
        let result = RecurringRules.markPaid(recurringUid, dueOn: dueOn,
                                             payment: PaymentDraft(amountMinor: minor, accountUid: fromUid, paidOn: LocalDay(date: date)),
                                             in: finance.data)
        if let failure = finance.apply(result) { error = failure.message } else { close() }
    }
}
