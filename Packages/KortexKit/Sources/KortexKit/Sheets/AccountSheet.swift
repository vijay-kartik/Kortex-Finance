import KortexFinance
import LocalAuthentication
import SwiftUI

/// Add account / card and editing one (Figma: Add account — bank / credit card, Edit account).
/// The number field takes the full number or just the last 4, as on the phone: a full number is
/// sealed with the user's data key into finSecrets, and only shows after Touch ID or the password.
struct AccountSheet: View {
    let finance: any FinanceStore
    let editing: Account?
    let close: () -> Void

    @State private var draft: AccountDraft
    @State private var opening = ""
    @State private var limit: String
    @State private var error: String?
    /// As typed: the full number, or just the last 4. Empty on edit keeps what's saved.
    @State private var number = ""
    @State private var saving = false
    @State private var revealed: String?
    @State private var revealing = false

    init(finance: any FinanceStore, editing: Account?, kind: AccountKind = .bank, close: @escaping () -> Void) {
        self.finance = finance
        self.editing = editing
        self.close = close
        var start = editing.map(AccountDraft.init) ?? AccountDraft(kind: kind)
        if editing == nil && kind == .bank { start.bankType = .savings }
        _draft = State(initialValue: start)
        _limit = State(initialValue: editing?.creditLimitMinor.map(Money.editable) ?? "")
        _opening = State(initialValue: editing.map { Money.editable(AccountRules.openingMinor(of: $0.uid, in: finance.data)) } ?? "")
    }

    var body: some View {
        let banks = finance.data.accounts.values.filter { $0.kind == .bank && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        SheetChrome(
            title: editing == nil ? "Add account" : "Edit \(editing!.name)",
            primary: saving ? "Saving…" : editing == nil ? "Add" : "Save changes",
            error: error,
            onCancel: close,
            onPrimary: save
        ) {
            if editing == nil {
                Picker("Kind", selection: $draft.kind) {
                    Text("Bank").tag(AccountKind.bank)
                    Text("Credit card").tag(AccountKind.creditCard)
                    Text("Debit card").tag(AccountKind.debitCard)
                    Text("Wallet").tag(AccountKind.wallet)
                    Text("Cash").tag(AccountKind.cash)
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextField("Name", text: $draft.name, prompt: Text(draft.kind.isCard ? "KORTEX" : "Checking Account"))
                if draft.kind != .cash {
                    TextField("Bank", text: optional(\.institution), prompt: Text("HDFC Bank"))
                    numberField
                }
                if draft.kind == .bank {
                    Picker("Type", selection: $draft.bankType) {
                        Text("Savings").tag(BankType?.some(.savings))
                        Text("Current").tag(BankType?.some(.current))
                    }
                    TextField("IFSC", text: optional(\.ifsc), prompt: Text("HDFC0001234"))
                }
            }
            if draft.kind.isCard {
                Section {
                    TextField("Card holder", text: optional(\.holder), prompt: Text("Aarav Mehta"))
                    TextField("Network", text: optional(\.network), prompt: Text("Visa, Mastercard, RuPay"))
                    TextField("Expires", text: optional(\.expiry), prompt: Text("MM/YY"))
                    if draft.kind == .debitCard && editing == nil {
                        Picker("Spends come out of", selection: $draft.linkedAccountUid) {
                            Text("Its own balance").tag(String?.none)
                            ForEach(banks) { Text($0.name).tag(String?.some($0.uid)) }
                        }
                    }
                }
            }
            if draft.kind == .creditCard {
                Section {
                    AmountField(label: "Credit limit", text: $limit)
                    Picker("Statement day", selection: $draft.statementDay) {
                        Text("Not set").tag(Int?.none)
                        ForEach(1...31, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    Picker("Payment due day", selection: $draft.dueDay) {
                        Text("Not set").tag(Int?.none)
                        ForEach(1...31, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                } footer: {
                    Text("With both days set, Kortex works out each bill on your phone.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
            }
            if !(draft.kind == .debitCard && draft.linkedAccountUid != nil) {
                Section {
                    AmountField(label: draft.kind == .creditCard ? (editing == nil ? "Outstanding today" : "Owed at the start") : "Opening balance",
                                text: $opening)
                } footer: {
                    Text(openingFooter).font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
            }
        }
    }

    @ViewBuilder private var numberField: some View {
        TextField("Number", text: $number, prompt: Text(editing?.last4.map { "•••• \($0)" } ?? "Full number, or just the last 4"))
            .font(.mono(13))
        if let editing, editing.hasSecret {
            LabeledContent("Full number") {
                HStack(spacing: 8) {
                    if let revealed {
                        Text(AccountNumbers.grouped(revealed)).font(.mono(13)).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(revealed, forType: .string)
                        }
                        Button("Hide") { self.revealed = nil }
                    } else {
                        Text("Kept encrypted").foregroundStyle(Color.kMuted)
                        Button(revealing ? "Opening…" : "Show") { reveal(editing) }.disabled(revealing)
                    }
                }
            }
        }
    }

    /// Touch ID or the Mac's password, then the number from finSecrets, opened here.
    private func reveal(_ account: Account) {
        revealing = true
        error = nil
        Task {
            defer { revealing = false }
            do {
                guard try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show the full number of \(account.name)") else { return }
                revealed = try await finance.revealNumber(of: account.uid)
                if revealed == nil { error = "No full number is kept for \(account.name)." }
            } catch let la as LAError where [.userCancel, .systemCancel, .appCancel].contains(la.code) {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// A text field bound to an optional string on the draft; empty means nil.
    private func optional(_ path: WritableKeyPath<AccountDraft, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: path] ?? "" }, set: { draft[keyPath: path] = $0.isEmpty ? nil : $0 })
    }

    private func save() {
        guard !saving else { return }
        var d = draft
        let digits = number.filter(\.isNumber)
        if !number.trimmingCharacters(in: .whitespaces).isEmpty {
            // Just the last 4, or the full number: anything in between is a typo.
            switch number.filter({ !$0.isWhitespace && $0 != "-" }).count {
            case 4 where digits.count == 4: d.last4 = digits
            case 8...19: d.fullNumber = number; d.last4 = nil
            default: error = "Enter the full number, or just the last 4 digits."; return
            }
        }
        if !opening.isEmpty {
            guard let minor = Money.parseMinor(opening) else { error = FinanceError.invalidAmount.message; return }
            d.openingMinor = minor
        }
        if d.kind == .creditCard {
            if limit.isEmpty { d.creditLimitMinor = nil } else {
                guard let minor = Money.parseMinor(limit) else { error = FinanceError.invalidAmount.message; return }
                d.creditLimitMinor = minor
            }
        }
        guard d.fullNumber != nil else { return commit(d, key: nil) }
        // Validate before asking for the key, so a typo doesn't wait on the network.
        if case .failure(let failure) = AccountNumbers.clean(d.fullNumber) { error = failure.message; return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                commit(d, key: try await finance.dataKey())
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// On edit: the day the balance starts from, and that changing it moves the balance by the difference.
    private var openingFooter: String {
        guard let editing else { return "Saved as the first entry: balances only ever change through entries." }
        let day = AccountRules.openingDay(of: editing.uid, in: finance.data).date.formatted(.dateTime.day().month(.abbreviated).year())
        return "What it \(editing.kind == .creditCard ? "owed" : "held") on \(day), before its first entry. "
            + "Changing it moves the balance today by the same amount."
    }

    private func commit(_ d: AccountDraft, key: DataKey?) {
        let result = editing.map { AccountRules.update($0.uid, d, opening: d.openingMinor, in: finance.data, key: key) }
            ?? AccountRules.add(d, in: finance.data, key: key)
        if let failure = finance.apply(result) { error = failure.message } else { close() }
    }
}
