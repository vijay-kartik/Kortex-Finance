import KortexCloud
import KortexFinance
import SwiftUI

/// Add expense / income / transfer, and editing one (Figma: Mac · Add expense — sheet). The category
/// a merchant was filed under before is picked for you, as on the phone. Paste SMS and receipts
/// arrive separately; this is "or enter it yourself". An expense or income being edited can be made a
/// transfer: the other account's record of the same money, when Kortex has one, becomes its other side.
/// A card bill payment is edited here too (where it came from, the card, the bill it pays), and money
/// out and a card payment can each be made the other.
struct EntrySheet: View {
    let finance: FinanceSync
    let editing: Entry?
    let close: () -> Void

    @State private var type: TransactionType
    @State private var amount: String
    @State private var date: Date
    @State private var merchant: String
    @State private var accountUid: String
    @State private var toAccountUid: String
    @State private var categoryUid: String?
    @State private var categoryTouched: Bool
    @State private var note: String
    /// A card payment's bill.
    @State private var statementUid: String?
    @State private var error: String?
    /// The edit waiting on whether the payee's other entries change category with it.
    @State private var refiling: Refiling?

    struct Refiling {
        let draft: TransactionDraft
        let others: [Entry]
    }

    init(finance: FinanceSync, type: TransactionType = .expense, editing: Entry? = nil, asTransfer: Bool = false, close: @escaping () -> Void) {
        self.finance = finance
        self.editing = editing
        self.close = close
        let accounts = finance.data.accounts.values.filter { !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        _type = State(initialValue: editing?.type ?? type)
        _amount = State(initialValue: editing.map { Money.editable($0.amountMinor) } ?? "")
        _date = State(initialValue: editing.map { Date(timeIntervalSince1970: TimeInterval($0.occurredAtMillis) / 1000) } ?? Date())
        _merchant = State(initialValue: editing?.merchant ?? "")
        _accountUid = State(initialValue: editing?.accountUid ?? (type == .income ? accounts.first { $0.kind != .creditCard } : accounts.first)?.uid ?? "")
        _toAccountUid = State(initialValue: editing?.toAccountUid ?? "")
        _categoryUid = State(initialValue: editing?.categoryUid)
        _categoryTouched = State(initialValue: editing != nil)
        _note = State(initialValue: editing?.note ?? "")
        _statementUid = State(initialValue: editing?.statementUid)
        if asTransfer, let editing, let ends = Self.transferEnds(of: editing) {
            _type = State(initialValue: .transfer)
            _accountUid = State(initialValue: ends.from)
            _toAccountUid = State(initialValue: ends.to)
        }
    }

    /// An expense or income as a transfer: money out leaves its account for one you pick; money in
    /// arrives in its account from one you pick.
    static func transferEnds(of tx: Entry) -> (from: String, to: String)? {
        switch tx.type {
        case .expense: (tx.accountUid, "")
        case .income: ("", tx.accountUid)
        case .cardPayment: (tx.isCardCredit || tx.accountUid == FinanceIds.unknownAccount ? "" : tx.accountUid, "")
        default: nil
        }
    }

    /// An expense, income or card bill payment being edited can change type; a transfer, an opening
    /// balance or a card's refund keeps its own.
    private var canChangeType: Bool {
        editing.map { ($0.type == .expense || $0.type == .income || $0.type == .cardPayment) && !$0.isCardCredit } ?? true
    }

    /// Money out can be a card bill paid from it, and a card bill payment can be money out after all.
    private var canBeCardPayment: Bool { editing.map { ($0.type == .expense || $0.type == .cardPayment) && !$0.isCardCredit } ?? false }

    /// What the entry's accounts become when an edit changes its type: back to its own as it was, a
    /// transfer's or card payment's ends with its own account on them, else its own account. A
    /// transfer or card payment has no merchant: what it was called stays as its note.
    private func switchType(of e: Entry, to new: TransactionType, in data: FinanceData) {
        statementUid = new == e.type ? e.statementUid : nil
        if new == e.type {
            accountUid = e.accountUid
            toAccountUid = e.toAccountUid ?? ""
            return
        }
        let own = data.accounts[e.accountUid] != nil ? e.accountUid : ""
        switch new {
        case .transfer:
            let ends = Self.transferEnds(of: e) ?? (own, "")
            accountUid = ends.from
            toAccountUid = ends.to
        case .cardPayment:
            accountUid = own
            let cards = data.accounts.values.filter { $0.kind == .creditCard && !$0.archived }
            toAccountUid = cards.count == 1 ? cards.first!.uid : ""
        default:
            accountUid = own
            toAccountUid = ""
        }
        if new == .transfer || new == .cardPayment, note.cleanedForUI == nil, let name = e.merchant { note = name }
    }

    var body: some View {
        let data = finance.data
        let all = data.accounts.values.filter { !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        let fromAccounts = type == .expense ? all : all.filter { $0.kind != .creditCard }
        let categoryKind: CategoryKind = type == .income ? .income : .expense
        let categories = data.categories.values.filter { $0.kind == categoryKind }
            .sorted { ($0.builtIn ? 0 : 1, $0.sortOrder, $0.name) < ($1.builtIn ? 0 : 1, $1.sortOrder, $1.name) }
        let suggested = EntryRules.rememberedCategory(for: merchant, in: data)

        SheetChrome(
            title: editing == nil ? "Add \(EntryFormat.type(type).lowercased())"
                : "Edit \((editing!.isCardCredit ? "Refund / credit" : EntryFormat.type(type)).lowercased())",
            subtitle: editing == nil ? (type == .expense ? "Got a receipt? Drop it on the window, or use File › Scan Receipt… (⌘O)." : nil) : EntryFormat.when(editing!),
            primary: editing == nil ? "Save \(EntryFormat.type(type).lowercased())" : "Save changes",
            error: error,
            onCancel: close,
            onPrimary: save
        ) {
            if canChangeType {
                Picker("Type", selection: $type) {
                    Text("Expense").tag(TransactionType.expense)
                    Text("Income").tag(TransactionType.income)
                    Text("Transfer").tag(TransactionType.transfer)
                    if canBeCardPayment { Text("Card bill").tag(TransactionType.cardPayment) }
                }
                .pickerStyle(.segmented)
                .onChange(of: type) { _, new in
                    categoryUid = editing.flatMap { $0.type == new ? $0.categoryUid : nil }
                    categoryTouched = editing != nil
                    if let editing { switchType(of: editing, to: new, in: data) }
                    if new != .expense, data.accounts[accountUid]?.kind == .creditCard {
                        accountUid = all.first { $0.kind != .creditCard }?.uid ?? ""
                    }
                }
            }
            Section {
                AmountField(label: "Amount", text: $amount)
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            if type == .cardPayment {
                cardPaymentSection(data, all: all)
            } else if type == .transfer {
                Section {
                    AccountPicker(label: "From", selection: $accountUid, accounts: fromAccounts)
                    AccountPicker(label: "To", selection: $toAccountUid, accounts: fromAccounts.filter { $0.uid != accountUid })
                } footer: {
                    if let editing, editing.type != .transfer, let text = otherSideNote(editing, data) {
                        Text(text).font(.grotesk(11)).foregroundStyle(Color.kMuted)
                    }
                }
            } else {
                Section {
                    TextField(type == .income ? "From" : "Merchant / description", text: $merchant,
                              prompt: Text(type == .income ? "Acme Corp" : "Whole Foods Market"))
                        .onChange(of: merchant) { _, new in
                            if !categoryTouched { categoryUid = EntryRules.rememberedCategory(for: new, in: data) }
                        }
                    AccountPicker(label: type == .income ? "Received in" : "Paid with", selection: $accountUid, accounts: fromAccounts)
                }
                Section {
                    CategoryChips(selection: Binding(get: { categoryUid }, set: { categoryUid = $0; categoryTouched = true }),
                                  categories: categories, suggested: suggested)
                } header: {
                    if let suggested, let name = data.categories[suggested]?.name, merchant.cleanedForUI != nil {
                        Text("Kortex filed \(merchant.cleanedForUI!) under \(name) before")
                    } else {
                        Text("Category")
                    }
                }
            }
            Section {
                TextField("Note", text: $note, prompt: Text("Add a note"), axis: .vertical)
                    .lineLimit(1...3)
            }
        }
        .confirmationDialog(refiling.map { refileTitle($0, data) } ?? "",
                            isPresented: Binding(get: { refiling != nil }, set: { if !$0 { refiling = nil } })) {
            if let r = refiling {
                Button(r.others.count == 1 ? "Change both" : "Change all \(r.others.count + 1)") { commit(r.draft, refiling: r.others.map(\.uid)) }
                Button("Only this one") { commit(r.draft, refiling: []) }
            }
        } message: {
            Text(refiling.map { refileMessage($0, data) } ?? "")
        }
    }

    /// "Move 12 other Swiggy entries to Food?"
    private func refileTitle(_ r: Refiling, _ data: FinanceData) -> String {
        let payee = r.draft.merchant?.cleanedForUI ?? "this payee"
        let to = r.draft.categoryUid.flatMap { data.categories[$0]?.name }.map { "to \($0)" } ?? "to Uncategorised"
        return r.others.count == 1 ? "Move the other \(payee) entry \(to) too?" : "Move \(r.others.count) other \(payee) entries \(to) too?"
    }

    /// Where those entries are now: "9 are in Shopping and 3 are uncategorised."
    private func refileMessage(_ r: Refiling, _ data: FinanceData) -> String {
        let counts = Dictionary(grouping: r.others) { $0.categoryUid.flatMap { data.categories[$0]?.name } }.mapValues(\.count)
        let parts = counts.sorted { ($0.value, $0.key ?? "") > ($1.value, $1.key ?? "") }.map { name, n in
            let verb = n == 1 ? "is" : "are"
            return name.map { "\(n) \(verb) in \($0)" } ?? "\(n) \(verb) uncategorised"
        }
        let now = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        let future = r.draft.categoryUid.flatMap { data.categories[$0]?.name }
            .map { " New \(r.draft.merchant?.cleanedForUI ?? "") entries will be suggested \($0) either way." } ?? ""
        return "Right now \(now)." + future
    }

    /// Making money out or in a transfer: what happens on the other account. "Kortex has this money
    /// in to HDFC Savings too: "NEFT CR…", 5 Sep. Saving makes the two one transfer."
    private func otherSideNote(_ editing: Entry, _ data: FinanceData) -> String? {
        guard let draft = makeDraft(), let toUid = draft.toAccountUid, !toUid.isEmpty, !draft.accountUid.isEmpty else { return nil }
        let leaves = Balances.ledger(of: editing.accountUid, in: data.accounts) == Balances.ledger(of: draft.accountUid, in: data.accounts)
        let other = EntryFormat.account(leaves ? toUid : draft.accountUid, data)
        guard let side = EntryRules.transferOtherSide(of: editing.uid, draft, in: data) else {
            return "\(other) has no entry for this money, so the transfer \(leaves ? "adds it to" : "takes it from") \(other)'s balance."
        }
        let day = side.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
        return "Kortex has this money \(leaves ? "in to" : "out of") \(other) too: \"\(EntryFormat.title(side, data))\", \(day). "
            + "Saving makes the two one transfer, so neither counts as \(leaves ? "income" : "spending")."
    }

    /// Where a card payment came from, the card and the bill it pays. A card's refund came from no account.
    private func cardPaymentSection(_ data: FinanceData, all: [Account]) -> some View {
        let payFrom = all.filter { !$0.kind.isCard }
        let cards = all.filter { $0.kind == .creditCard }
        let bills = data.statements.values.filter { $0.cardUid == toAccountUid }.sorted { $0.statementOn > $1.statementOn }
        let credit = editing?.isCardCredit == true
        return Section {
            if credit {
                LabeledContent("From", value: "Refund / credit")
            } else {
                Picker("Paid from", selection: $accountUid) {
                    if accountUid.isEmpty { Text("Choose…").tag("") }
                    ForEach(payFrom) { a in Text(EntryFormat.account(a.uid, data)).tag(a.uid) }
                    Text("Unknown account").tag(FinanceIds.unknownAccount)
                }
            }
            AccountPicker(label: "Card", selection: $toAccountUid, accounts: cards)
                .onChange(of: toAccountUid) { _, card in
                    // Another card: its bill for the day, unless it's the card the payment had.
                    statementUid = editing.flatMap { $0.toAccountUid == card && $0.type == .cardPayment ? $0.statementUid : nil }
                        ?? (credit ? nil : EntryRules.billPaid(card, on: LocalDay(date: date), in: data)?.uid)
                }
            if !credit {
                Picker("Pays bill", selection: $statementUid) {
                    Text("No bill").tag(String?.none)
                    ForEach(bills) { b in
                        Text("\(b.statementOn.date.formatted(.dateTime.day().month(.abbreviated).year())) bill · \(Money.format(b.totalDueMinor)) due")
                            .tag(String?.some(b.uid))
                    }
                }
            }
        } footer: {
            Text(cardPaymentNote(data, credit: credit)).font(.grotesk(11)).foregroundStyle(Color.kMuted)
        }
    }

    /// What saving does: takes over the card's payment from an unknown account when there's one for this
    /// money, else says a bill payment isn't spending.
    private func cardPaymentNote(_ data: FinanceData, credit: Bool) -> String {
        if credit { return "A refund lowers what the card owes. The purchase it refunds still counts as spending." }
        if let editing, let draft = makeDraft(), let side = EntryRules.cardPaymentOtherSide(of: editing.uid, draft, in: data) {
            let day = side.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
            return "\(EntryFormat.account(side.toAccountUid, data)) has this payment from an unknown account on \(day). "
                + "Saving makes it this one, paid from \(EntryFormat.account(draft.accountUid, data)), so the card isn't paid twice."
        }
        return "A bill payment isn't spending: the purchases on the card already were."
    }

    /// The entry as the sheet has it, or nil without a valid amount.
    private func makeDraft() -> TransactionDraft? {
        guard let minor = Money.parseMinor(amount), minor > 0 else { return nil }
        let clock = FinanceClock.system
        let day = LocalDay(date: date)
        // Editing without touching the date keeps its time.
        let at = editing.flatMap { clock.dayOf($0.occurredAtMillis) == day ? $0.occurredAtMillis : nil } ?? clock.millisOn(day)
        let movesBetweenAccounts = type == .transfer || type == .cardPayment
        return TransactionDraft(
            type: type,
            amountMinor: minor,
            accountUid: accountUid,
            toAccountUid: movesBetweenAccounts ? toAccountUid : nil,
            categoryUid: movesBetweenAccounts ? nil : categoryUid,
            merchant: movesBetweenAccounts ? nil : merchant,
            note: note,
            occurredAtMillis: at,
            statementUid: type == .cardPayment ? statementUid : nil
        )
    }

    private func save() {
        guard let draft = makeDraft() else {
            error = FinanceError.invalidAmount.message
            return
        }
        // Money out or in made a transfer, or a card payment, takes the other end's record of it along.
        if let editing, (editing.type != .transfer && draft.type == .transfer) || draft.type == .cardPayment {
            if let failure = finance.apply(EntryRules.editMerging(editing.uid, draft, in: finance.data)) { error = failure.message } else { close() }
            return
        }
        // A new category for an entry offers the same for the payee's other entries.
        if let editing, draft.categoryUid != editing.categoryUid {
            let others = EntryRules.samePayee(as: editing.uid, draft, in: finance.data)
            if !others.isEmpty {
                refiling = Refiling(draft: draft, others: others)
                return
            }
        }
        commit(draft, refiling: [])
    }

    /// Saves the entry, and files `others` under its category too.
    private func commit(_ draft: TransactionDraft, refiling others: [String]) {
        refiling = nil
        let clock = FinanceClock.system
        let result = editing.map { EntryRules.edit($0.uid, draft, alsoRefiling: others, in: finance.data, clock: clock) }
            ?? EntryRules.add(draft, in: finance.data, clock: clock)
        if let failure = finance.apply(result) {
            error = failure.message
        } else {
            close()
        }
    }
}

extension String {
    /// Trimmed, nil when empty.
    var cleanedForUI: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
