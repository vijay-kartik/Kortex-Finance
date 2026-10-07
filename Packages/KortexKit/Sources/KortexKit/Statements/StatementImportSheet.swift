import KortexAI
import KortexCloud
import KortexFinance
import SwiftUI

/// Import a statement (Mac only), into a new account or one you have. The statement is read by AI and
/// every row is checked against its printed balance. Into an account you have, rows already in Kortex
/// are found and left out. Nothing is added until the review is saved.
struct StatementImportSheet: View {
    let finance: FinanceSync
    let file: URL
    /// The account the statement was imported from (its Import statement…), if any.
    let into: String?
    let close: () -> Void

    enum Stage {
        case reading(StatementReader.Progress)
        case failed(String)
        case pickAccount([ExtractedAccount])
        case review
    }

    @AppStorage("aiModel") private var modelID = AIModel.default.rawValue
    @State private var stage: Stage = .reading(.rendering)
    @State private var statement: ExtractedStatement?
    @State private var draft: StatementImport?
    @State private var filter: RowFilter = .all
    @State private var error: String?
    @State private var added: Set<String> = []
    /// The extracted account under review.
    @State private var current: ExtractedAccount?
    /// The account it goes into was found by its last 4 digits rather than picked.
    @State private var foundByNumber = false

    private var model: AIModel { AIModel(rawValue: modelID) ?? .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            Group {
                switch stage {
                case .reading(let progress): reading(progress)
                case .failed(let message): failed(message)
                case .pickAccount(let accounts): pickAccount(accounts)
                case .review: review
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1180, height: 780)
        .background(Color.kSheet)
        .task { await read() }
    }

    private var title: String {
        if let uid = draft?.existingAccountUid ?? (draft == nil ? into : nil), let account = finance.data.accounts[uid] {
            return "Import statement into \(account.name)"
        }
        return draft == nil && into == nil ? "Import statement" : "Add account from statement"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 18)).foregroundStyle(Color.kSynapse)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.grotesk(18, .medium)).foregroundStyle(Color.kInk)
                Text("\(file.lastPathComponent) · read with \(model.title.replacingOccurrences(of: " (recommended)", with: ""))")
                    .font(.grotesk(11)).foregroundStyle(Color.kMuted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: Reading

    private func reading(_ progress: StatementReader.Progress) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            switch progress {
            case .rendering:
                Text("Preparing the pages…").font(.grotesk(14)).foregroundStyle(Color.kInk)
            case .reading(let done, let of):
                Text(of > 1 ? "Reading the statement · part \(min(done + 1, of)) of \(of)…" : "Reading the statement…")
                    .font(.grotesk(14)).foregroundStyle(Color.kInk)
            }
            Text("The pages go to \(model.rawValue) through Vercel AI Gateway. Kortex asks for only the last 4 digits of account and card numbers.")
                .font(.grotesk(12)).foregroundStyle(Color.kMuted).multilineTextAlignment(.center).frame(maxWidth: 520)
            Button("Cancel", action: close).keyboardShortcut(.cancelAction).padding(.top, 8)
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundStyle(Color.kAmber)
            Text("Couldn't read this statement").font(.grotesk(16, .medium)).foregroundStyle(Color.kInk)
            Text(message).font(.grotesk(13)).foregroundStyle(Color.kMuted).multilineTextAlignment(.center).frame(maxWidth: 560)
            HStack {
                if !AIKeyStore.hasKey { SettingsLink { Text("Open Settings…") } }
                Button("Try again") { Task { await read() } }
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 6)
        }
    }

    // MARK: Picking an account

    private func pickAccount(_ accounts: [ExtractedAccount]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This statement covers \(accounts.count) accounts. Which one should Kortex import?")
                .font(.grotesk(15)).foregroundStyle(Color.kInk)
            ForEach(accounts) { a in
                let supported = a.kind == .bank || a.kind == .credit_card
                Button {
                    begin(a)
                } label: {
                    HStack(spacing: 14) {
                        AccountIcon(kind: a.kind == .credit_card ? .creditCard : .bank)
                        VStack(alignment: .leading, spacing: 3) {
                            Text([a.institution, a.productName].compactMap { $0 }.joined(separator: " · ")).font(.grotesk(14, .medium)).foregroundStyle(Color.kInk)
                            Text(subtitle(a)).font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        }
                        Spacer()
                        if added.contains(a.id) {
                            Label("Added", systemImage: "checkmark").font(.grotesk(12)).foregroundStyle(Color.kGrowth)
                        } else if !supported {
                            Text("Loans aren't supported yet").font(.grotesk(12)).foregroundStyle(Color.kMuted)
                        } else {
                            Image(systemName: "chevron.right").foregroundStyle(Color.kMuted)
                        }
                    }
                    .padding(14)
                    .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.kEdge))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!supported || added.contains(a.id))
            }
            Spacer()
            HStack { Spacer(); Button(added.isEmpty ? "Cancel" : "Done", action: close).keyboardShortcut(.cancelAction) }
        }
        .padding(24)
    }

    private func subtitle(_ a: ExtractedAccount) -> String {
        let kind = switch a.kind { case .bank: "Bank account"; case .credit_card: "Credit card"; case .loan: "Loan"; case .other: "Account" }
        let number = a.numberLast4.map { d in "••" + String(d.filter(\.isASCIIDigitForUI).suffix(4)) }
        let count = a.transactions.count == 1 ? "1 transaction" : "\(a.transactions.count) transactions"
        let known = target(for: a).flatMap { finance.data.accounts[$0] }.map { "goes into \($0.name)" }
        return [kind, number, count, known].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Review

    @ViewBuilder private var review: some View {
        if let current = draft {
            HStack(alignment: .top, spacing: 0) {
                ScrollView { accountPane(current).padding(20) }
                    .frame(width: 340)
                    .background(Color.kSidebar)
                Rectangle().fill(Color.kEdge).frame(width: 1)
                VStack(spacing: 0) {
                    rowsToolbar(current)
                    Hairline()
                    StatementRowsTable(draft: Binding(get: { draft! }, set: { draft = $0 }), data: finance.data, filter: filter)
                    Hairline()
                    footer(current)
                }
            }
        }
    }

    private func accountPane(_ current: StatementImport) -> some View {
        let isCard = current.account.kind == .creditCard
        return VStack(alignment: .leading, spacing: 16) {
            destination(current)
            if let uid = current.existingAccountUid, let account = finance.data.accounts[uid] {
                existingAccount(account)
                kortexCheck(current, account: account)
            } else {
                VStack(spacing: 10) {
                    field("Name", text: binding(\.account.name))
                    field("Bank", text: optionalBinding(\.account.institution))
                    field("Last 4 digits", text: optionalBinding(\.account.last4))
                    if isCard {
                        field("Card holder", text: optionalBinding(\.account.holder))
                    } else {
                        field("IFSC", text: optionalBinding(\.account.ifsc))
                    }
                }
                .textFieldStyle(.roundedBorder)
                reconciliation(current)
            }
            if let bill = current.bill {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BILL ON THIS STATEMENT").sectionLabelStyle()
                    LabeledContent("Total due", value: Money.format(bill.totalMinor))
                    LabeledContent("Minimum", value: Money.format(bill.minMinor))
                    LabeledContent("Due on", value: Format.dueDay(bill.dueOn))
                    Text(StatementImportRules.billExists(current, in: finance.data)
                         ? "Kortex already has this bill, so it's left as it is."
                         : "Added as this card's bill, so it shows in Pending payments.")
                        .font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
                .font(.grotesk(12))
                .padding(12)
                .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 10))
            }
            recurring(current)
        }
    }

    /// Where the entries go: a new account, or one you have. Changing it reads the rows afresh.
    @ViewBuilder private func destination(_ s: StatementImport) -> some View {
        let isCard = s.account.kind == .creditCard
        let choices = current.map { StatementImportRules.accounts(for: $0, in: finance.data) } ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD TO").sectionLabelStyle()
            Picker("Add to", selection: Binding(get: { s.existingAccountUid }, set: { retarget($0) })) {
                Text(isCard ? "A new credit card" : "A new bank account").tag(String?.none)
                if !choices.isEmpty {
                    Divider()
                    ForEach(choices) { a in Text(a.last4.map { "\(a.name) ••\($0)" } ?? a.name).tag(String?.some(a.uid)) }
                }
            }
            .labelsHidden()
            Group {
                if s.intoExisting && foundByNumber {
                    Text("Found by its last 4 digits. Entries already in Kortex are matched and left out.")
                } else if s.intoExisting {
                    Text("Entries already in Kortex are matched and left out.")
                } else if !choices.isEmpty {
                    Text("Already have this \(isCard ? "card" : "account")? Pick it to add only what's missing.")
                }
            }
            .font(.grotesk(11)).foregroundStyle(Color.kMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func existingAccount(_ account: Account) -> some View {
        HStack(spacing: 12) {
            AccountIcon(kind: account.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.grotesk(14, .medium)).foregroundStyle(Color.kInk)
                Text(AccountText.detailLine(account)).font(.grotesk(11)).foregroundStyle(Color.kMuted).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(account.kind == .creditCard ? "OWED" : "BALANCE").sectionLabelStyle()
                Text(Money.format(finance.data.balanceMinor(of: account))).font(.mono(12)).foregroundStyle(Color.kInk)
            }
        }
        .padding(12)
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Into an account you have: what's already there, and whether Kortex's balance will agree with
    /// the statement's on both ends once the rows are added.
    private func kortexCheck(_ s: StatementImport, account: Account) -> some View {
        let isCard = account.kind == .creditCard
        let matched = s.rows.filter { $0.match != nil }.count
        let toAdd = s.rows.filter(\.include).count
        let r = s.reconciliation(in: finance.data)
        let day = { (d: LocalDay) in d.date.formatted(.dateTime.day().month(.abbreviated)) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("CHECK AGAINST KORTEX").sectionLabelStyle()
            Text("\(s.rows.count) rows · \(matched) already in Kortex · \(toAdd) to add").foregroundStyle(Color.kMuted)
            if let r {
                Hairline()
                LabeledContent(isCard ? "Owed on \(day(s.openingOn)), statement" : "Opening, statement", value: Money.format(s.openingMinor))
                LabeledContent("In Kortex", value: Money.format(r.kortexOpeningMinor))
                Hairline()
                if let closing = s.closingMinor {
                    LabeledContent(isCard ? "Owed on \(day(s.closingOn)), statement" : "Closing, statement", value: Money.format(closing))
                }
                LabeledContent("In Kortex after adding", value: Money.format(r.kortexClosingMinor))
                if let closing = s.closingMinor {
                    let off = closing - r.kortexClosingMinor
                    if off == 0 {
                        Label("Kortex will match the statement", systemImage: "checkmark.circle.fill").foregroundStyle(Color.kGrowth)
                    } else if closing - s.openingMinor == r.kortexMovementMinor {
                        Label("Off by \(Money.format(abs(off))), all from before this statement: the entries for its dates add up.",
                              systemImage: "info.circle.fill")
                            .foregroundStyle(Color.kSky)
                    } else {
                        Label("Off by \(Money.format(abs(off))) over this statement. Check the rows to check, and the entries below.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.kAmber)
                    }
                }
                if !r.notOnStatement.isEmpty { notOnStatement(r.notOnStatement) }
            }
        }
        .font(.grotesk(12))
        .padding(12)
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Entries Kortex has in the statement's dates that no row matched.
    private func notOnStatement(_ entries: [Entry]) -> some View {
        let shown = entries.prefix(8)
        return VStack(alignment: .leading, spacing: 5) {
            Hairline().padding(.vertical, 4)
            Text("IN KORTEX, NOT ON THE STATEMENT · \(entries.count)").sectionLabelStyle()
            ForEach(shown) { tx in
                HStack(spacing: 8) {
                    Text(tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))).font(.mono(10)).foregroundStyle(Color.kMuted)
                        .frame(width: 44, alignment: .leading)
                    Text(EntryFormat.title(tx, finance.data)).lineLimit(1).foregroundStyle(Color.kInk)
                    Spacer()
                    Text(EntryFormat.amount(tx)).font(.mono(11)).foregroundStyle(EntryFormat.amountColor(tx))
                }
                .help("\(EntryFormat.sourceName(tx.source)) · \(EntryFormat.when(tx))")
            }
            if entries.count > shown.count {
                Text("and \(entries.count - shown.count) more").foregroundStyle(Color.kMuted)
            }
            Text("These stay as they are. If one is a duplicate or belongs to another account, fix it after importing.")
                .font(.grotesk(11)).foregroundStyle(Color.kMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the Repeats column will do on saving.
    @ViewBuilder private func recurring(_ s: StatementImport) -> some View {
        let starts = StatementImportRules.newRecurring(s)
        let paying = s.rows.filter { $0.include && $0.kind == .expense }.compactMap { row -> String? in
            if case .pays(let uid) = row.repeats { uid } else { nil }
        }
        let pays = Dictionary(grouping: paying) { $0 }
        if !starts.isEmpty || !pays.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECURRING").sectionLabelStyle()
                ForEach(starts) { r in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New: \(r.name)").foregroundStyle(Color.kInk).lineLimit(1)
                            Text("\(Money.format(r.amountMinor)) · next due \(Format.dueDay(r.nextDueOn))").font(.grotesk(11)).foregroundStyle(Color.kMuted)
                        }
                        Spacer()
                        Picker("Repeats", selection: Binding(get: { r.frequency }, set: { draft?.frequencies[r.uid] = $0 })) {
                            ForEach(StatementImportRules.newFrequencies, id: \.self) { f in
                                Text(f == .yearly ? "Yearly" : "Monthly").tag(f)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                    }
                }
                ForEach(pays.keys.sorted(), id: \.self) { uid in
                    let n = pays[uid]?.count ?? 0
                    LabeledContent("Pays \(finance.data.recurring[uid]?.name ?? "a recurring payment")", value: n == 1 ? "1 entry" : "\(n) entries")
                }
                Text("Change any row in the Repeats column. Reminders and auto-pay can be set in Recurring afterwards.")
                    .font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
            .font(.grotesk(12))
            .padding(12)
            .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func reconciliation(_ s: StatementImport) -> some View {
        let included = s.rows.filter(\.include)
        let inflow = included.filter { StatementImport.effectSign($0, kind: s.account.kind) > 0 }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let outflow = included.filter { StatementImport.effectSign($0, kind: s.account.kind) < 0 }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let isCard = s.account.kind == .creditCard
        return VStack(alignment: .leading, spacing: 6) {
            Text("CHECK").sectionLabelStyle()
            HStack {
                Text(isCard ? "Owed at start" : "Opening balance")
                Spacer()
                TextField("", value: Binding(get: { Double(draft!.openingMinor) / 100 },
                                            set: { draft!.openingMinor = Int64(($0 * 100).rounded()) }),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 120)
            }
            Text("on \(s.openingOn.date.formatted(.dateTime.day().month(.abbreviated).year()))").font(.grotesk(11)).foregroundStyle(Color.kMuted)
            LabeledContent(isCard ? "+ Spent" : "+ Money in", value: Money.format(isCard ? outflow : inflow))
            LabeledContent(isCard ? "− Paid off and refunded" : "− Money out", value: Money.format(isCard ? inflow : outflow))
            Hairline()
            LabeledContent("= Works out to", value: Money.format(s.computedClosingMinor))
            if let closing = s.closingMinor {
                LabeledContent("Statement says", value: Money.format(closing))
                if s.reconciles == true {
                    Label("Everything adds up", systemImage: "checkmark.circle.fill").foregroundStyle(Color.kGrowth)
                } else {
                    Label("Off by \(Money.format(abs(closing - s.computedClosingMinor))). Check the flagged rows.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.kAmber)
                }
            }
        }
        .font(.grotesk(12))
        .padding(12)
        .background(Color.kPanel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func rowsToolbar(_ s: StatementImport) -> some View {
        let count = { (f: RowFilter) in s.rows.filter(f.admits).count }
        return HStack(spacing: 12) {
            Text("Entries").font(.grotesk(15, .medium)).foregroundStyle(Color.kInk)
            Text("\(s.rows.count) read · \(count(.toAdd)) to add").font(.grotesk(12)).foregroundStyle(Color.kMuted)
            Spacer()
            Picker("Show", selection: $filter) {
                Text("All").tag(RowFilter.all)
                Text("To add · \(count(.toAdd))").tag(RowFilter.toAdd)
                if s.intoExisting { Text("In Kortex · \(count(.inKortex))").tag(RowFilter.inKortex) }
                Text("To check · \(count(.toCheck))").tag(RowFilter.toCheck)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func footer(_ s: StatementImport) -> some View {
        let n = s.rows.filter(\.include).count
        let entries = n == 1 ? "1 entry" : "\(n) entries"
        let into = s.existingAccountUid.flatMap { finance.data.accounts[$0] }
        return HStack(spacing: 12) {
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.grotesk(12)).foregroundStyle(Color.kAlarm).lineLimit(2) }
            Spacer()
            if let statement, statement.accounts.count > 1 {
                Button("Back") { stage = .pickAccount(statement.accounts) }
            }
            Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            Button(into.map { "Add \(entries) to \($0.name)" } ?? "Add account and \(entries)", action: save)
                .keyboardShortcut(.defaultAction)
                .tint(.kSynapse)
                // Nothing new and no bill to add: everything on the statement is already in Kortex.
                .disabled(into != nil && n == 0 && (s.bill == nil || StatementImportRules.billExists(s, in: finance.data)))
        }
        .controlSize(.large)
        .padding(16)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) { TextField(label, text: text).labelsHidden() }.font(.grotesk(12))
    }

    private func binding(_ path: WritableKeyPath<StatementImport, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: path] ?? "" }, set: { draft?[keyPath: path] = $0 })
    }

    private func optionalBinding(_ path: WritableKeyPath<StatementImport, String?>) -> Binding<String> {
        Binding(get: { draft?[keyPath: path] ?? "" }, set: { draft?[keyPath: path] = $0.isEmpty ? nil : $0 })
    }

    // MARK: Flow

    private func read() async {
        stage = .reading(.rendering)
        let categories = Array(finance.data.categories.values)
        do {
            let read = try await StatementReader.read(file, categories: categories, model: model) { stage = .reading($0) }
            statement = read
            let usable = read.accounts.filter { $0.kind == .bank || $0.kind == .credit_card }
            // From an account's Import statement…, go straight to the statement's account of that kind.
            let forInto = into == nil ? [] : usable.filter { target(for: $0) == into }
            if read.accounts.isEmpty || usable.isEmpty {
                stage = .failed("No bank account or credit card was found in it. Is it an account statement?")
            } else if read.accounts.count == 1 {
                begin(read.accounts[0])
            } else if forInto.count == 1 {
                begin(forInto[0])
            } else {
                stage = .pickAccount(read.accounts)
            }
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// The account you have that these rows go into: the one Import statement… was chosen on when the
    /// statement is that kind of account (and doesn't name a different one), else the one with its
    /// last 4 digits. Nil for a new account.
    private func target(for account: ExtractedAccount) -> String? {
        let data = finance.data
        let byNumber = StatementImportRules.existingAccount(for: account, in: data)
        if let into, StatementImportRules.accounts(for: account, in: data).contains(where: { $0.uid == into }) {
            let named = data.accounts[into]?.last4
            let read = account.numberLast4.map { String($0.filter(\.isASCIIDigitForUI).suffix(4)) }
            // A composite statement's other account: don't pour it into the one you chose.
            if let named, let read, read.count == 4, named != read { return byNumber?.uid }
            return into
        }
        return byNumber?.uid
    }

    private func begin(_ account: ExtractedAccount) {
        let uid = target(for: account)
        foundByNumber = uid != nil && uid != into
        prepare(account, into: uid)
    }

    /// Picking another account (or a new one) in Add to: the rows are read again against it.
    private func retarget(_ uid: String?) {
        guard let current, uid != draft?.existingAccountUid else { return }
        foundByNumber = false
        prepare(current, into: uid)
    }

    private func prepare(_ account: ExtractedAccount, into uid: String?) {
        draft = StatementImportRules.prepare(account, into: uid, in: finance.data, today: .today())
        current = account
        error = nil
        filter = .all
        stage = .review
    }

    private func save() {
        guard let draft else { return }
        if let failure = finance.apply(StatementImportRules.commit(draft, in: finance.data)) {
            error = failure.message
            return
        }
        // A composite statement: offer its other accounts next.
        if let statement, statement.accounts.count > 1, let current {
            added.insert(current.id)
            self.draft = nil
            stage = .pickAccount(statement.accounts)
        } else {
            close()
        }
    }
}

extension Character {
    var isASCIIDigitForUI: Bool { ("0"..."9").contains(self) }
}

extension StatementImport {
    /// +1 when a row raises this account's balance as the reconciliation reads it (money in; for a
    /// card, a payment), −1 when it lowers it.
    static func effectSign(_ row: ImportRow, kind: AccountKind) -> Int {
        if kind == .creditCard { return row.kind == .expense ? -1 : 1 }
        return row.kind.isMoneyIn ? 1 : -1
    }
}
