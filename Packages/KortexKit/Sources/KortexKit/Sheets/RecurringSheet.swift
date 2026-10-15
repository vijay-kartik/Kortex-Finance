import KortexFinance
import SwiftUI

/// Add recurring payment and editing one (Figma: Recurring 02). Nothing is paid by saving.
struct RecurringSheet: View {
    let finance: any FinanceStore
    let editing: Recurring?
    let close: () -> Void

    @State private var draft: RecurringDraft
    @State private var amount: String
    @State private var dueDate: Date
    @State private var error: String?

    init(finance: any FinanceStore, editing: Recurring?, close: @escaping () -> Void) {
        self.finance = finance
        self.editing = editing
        self.close = close
        let firstAccount = finance.data.accounts.values.filter { !$0.archived }.min { $0.createdAtMillis < $1.createdAtMillis }
        let start = editing.map(RecurringDraft.init) ?? RecurringDraft(
            name: "", kind: .subscription, amountMinor: 0, frequency: .monthly,
            nextDueOn: LocalDay.today(), accountUid: firstAccount?.uid ?? "", remindDaysBefore: 2
        )
        _draft = State(initialValue: start)
        _amount = State(initialValue: editing.map { Money.editable($0.amountMinor) } ?? "")
        _dueDate = State(initialValue: start.nextDueOn.date)
    }

    var body: some View {
        let data = finance.data
        let accounts = data.accounts.values.filter { !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        let categories = data.categories.values.filter { $0.kind == .expense }
            .sorted { ($0.builtIn ? 0 : 1, $0.sortOrder) < ($1.builtIn ? 0 : 1, $1.sortOrder) }
        SheetChrome(
            title: editing == nil ? "Add recurring payment" : "Edit \(editing!.name)",
            primary: editing == nil ? "Save recurring payment" : "Save changes",
            error: error,
            onCancel: close,
            onPrimary: save
        ) {
            SheetSection {
                KSegmented("Type", selection: $draft.kind, options: [(RecurringKind.subscription, "Subscription"), (.fixed, "Fixed expense")])
            } footer: {
                Text(draft.kind == .subscription ? "Something you can cancel, like Netflix or Spotify." : "Rent, EMIs, utilities.")
            }
            KFieldRow(trailingWidth: nil) {
                KTextField("Name", text: $draft.name, prompt: "Netflix")
            } trailing: {
                AmountField(label: "Amount", text: $amount)
            }
            SheetSection {
                KFieldRow(trailingWidth: nil) {
                    KMenuField("Repeats", selection: $draft.frequency, value: frequencyName) {
                        Text("Every week").tag(Frequency.weekly)
                        Text("Every month").tag(Frequency.monthly)
                        Text("Every year").tag(Frequency.yearly)
                    }
                } trailing: {
                    KField("Interval") {
                        Stepper("Every \(draft.interval) \(unit)\(draft.interval == 1 ? "" : "s")", value: $draft.interval, in: 1...12)
                            .font(.grotesk(15))
                            .foregroundStyle(Color.kInk)
                    }
                }
                KFieldRow(trailingWidth: nil) {
                    KDateField("Next due", selection: $dueDate)
                } trailing: {
                    AccountPicker(label: "Paid from", selection: $draft.accountUid, accounts: accounts)
                }
                KFieldRow(trailingWidth: nil) {
                    KMenuField("Category", selection: $draft.categoryUid,
                               value: draft.categoryUid.map { uid in categories.first { $0.uid == uid }?.name ?? "Deleted category" } ?? "Uncategorised") {
                        Text("Uncategorised").tag(String?.none)
                        ForEach(categories) { Text($0.name).tag(String?.some($0.uid)) }
                    }
                } trailing: {
                    KMenuField("Remind me", selection: $draft.remindDaysBefore, value: RecurringSchedule.reminderLabel(draft.remindDaysBefore)) {
                        ForEach([-1, 0, 1, 2, 3, 7], id: \.self) { Text(RecurringSchedule.reminderLabel($0)).tag($0) }
                    }
                }
            }
            SheetSection {
                Toggle("Mark it paid automatically on the due date (for auto-debits)", isOn: $draft.autoMarkPaid)
                if editing != nil { Toggle("Paused", isOn: $draft.paused) }
            }
            .font(.grotesk(13))
            .foregroundStyle(Color.kInk)
        }
    }

    private var frequencyName: String {
        switch draft.frequency { case .weekly: "Every week"; case .monthly: "Every month"; case .yearly: "Every year" }
    }

    private var unit: String {
        switch draft.frequency { case .weekly: "week"; case .monthly: "month"; case .yearly: "year" }
    }

    private func save() {
        guard let minor = Money.parseMinor(amount), minor > 0 else { error = FinanceError.invalidAmount.message; return }
        var d = draft
        d.amountMinor = minor
        d.nextDueOn = LocalDay(date: dueDate)
        if let failure = finance.apply(RecurringRules.save(editing?.uid, d, in: finance.data)) { error = failure.message } else { close() }
    }
}
