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
            Section {
                Picker("Type", selection: $draft.kind) {
                    Text("Subscription").tag(RecurringKind.subscription)
                    Text("Fixed expense").tag(RecurringKind.fixed)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(draft.kind == .subscription ? "Something you can cancel, like Netflix or Spotify." : "Rent, EMIs, utilities.")
                    .font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
            Section {
                TextField("Name", text: $draft.name, prompt: Text("Netflix"))
                AmountField(label: "Amount", text: $amount)
            }
            Section {
                Picker("Repeats", selection: $draft.frequency) {
                    Text("Every week").tag(Frequency.weekly)
                    Text("Every month").tag(Frequency.monthly)
                    Text("Every year").tag(Frequency.yearly)
                }
                Stepper("Every \(draft.interval) \(unit)\(draft.interval == 1 ? "" : "s")", value: $draft.interval, in: 1...12)
                DatePicker("Next due", selection: $dueDate, displayedComponents: .date)
                AccountPicker(label: "Paid from", selection: $draft.accountUid, accounts: accounts)
                Picker("Category", selection: $draft.categoryUid) {
                    Text("Uncategorised").tag(String?.none)
                    ForEach(categories) { Text($0.name).tag(String?.some($0.uid)) }
                }
                Picker("Remind me", selection: $draft.remindDaysBefore) {
                    ForEach([-1, 0, 1, 2, 3, 7], id: \.self) { Text(RecurringSchedule.reminderLabel($0)).tag($0) }
                }
                Toggle("Mark it paid automatically on the due date (for auto-debits)", isOn: $draft.autoMarkPaid)
                if editing != nil { Toggle("Paused", isOn: $draft.paused) }
            }
        }
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
