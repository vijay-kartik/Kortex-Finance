import KortexFinance
import SwiftUI

/// Scan receipt on the Mac (Figma: Mac · Receipt — review). The receipt beside its fields: reading,
/// then "Which total?" when the total isn't clear, "Already added" when an expense on the same card
/// matches (the receipt joins it rather than counting twice), and the review. The image stays on
/// this Mac; the entry carries its path, as on the phone.
struct ReceiptSheet: View {
    let finance: any FinanceStore
    let file: URL
    let close: () -> Void
    let enterManually: () -> Void

    enum Stage { case reading, unreadable, pickTotal, review }

    @State private var stage: Stage = .reading
    @State private var receipt = ParsedReceipt()
    @State private var preview: NSImage?
    @State private var pickedTotal: Int64?
    @State private var otherTotal = ""
    @State private var amount = ""
    @State private var merchant = ""
    @State private var date = Date()
    @State private var time: DayTime?
    @State private var accountUid = ""
    @State private var unknownLast4: String?
    @State private var categoryUid: String?
    @State private var categoryTouched = false
    @State private var note = ""
    @State private var keepImage = true
    @State private var duplicateDismissed = false
    @State private var showsItems = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            imagePane.frame(width: 340)
            Rectangle().fill(Color.kEdge).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Add expense").font(.grotesk(20, .medium)).foregroundStyle(Color.kInk)
                    Text("FROM RECEIPT").sectionLabelStyle()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.kRaised, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 24).padding(.top, 22)
                content
            }
            .frame(width: 560)
        }
        .frame(height: 640)
        .background(Color.kSheet)
        .task { await read() }
    }

    // MARK: Image

    private var imagePane: some View {
        VStack(spacing: 12) {
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.kPanel).overlay(ProgressView())
            }
            Text(file.lastPathComponent).font(.grotesk(12)).foregroundStyle(Color.kMuted).lineLimit(1).truncationMode(.middle)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .background(Color.kVoid)
    }

    // MARK: Stages

    @ViewBuilder private var content: some View {
        switch stage {
        case .reading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading the receipt…").font(.grotesk(13)).foregroundStyle(Color.kMuted)
                Text("On this Mac; the image doesn't leave it.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            buttons(primary: nil)
        case .unreadable:
            VStack(alignment: .leading, spacing: 10) {
                Label("Couldn't read this receipt", systemImage: "doc.text.magnifyingglass").font(.grotesk(15, .medium)).foregroundStyle(Color.kInk)
                Text("It may be blurry, cut off, or not a receipt. Try a sharper photo, or enter it yourself.")
                    .font(.grotesk(13)).foregroundStyle(Color.kMuted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            buttons(primary: ("Enter it yourself", enterManually))
        case .pickTotal:
            pickTotal
        case .review:
            review
        }
    }

    private var pickTotal: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Picker("Which total did you pay?", selection: $pickedTotal) {
                        ForEach(receipt.candidates, id: \.amountMinor) { c in
                            Text("\(Money.format(c.amountMinor)) · \(c.label)").tag(Int64?.some(c.amountMinor))
                        }
                        Text("Another amount").tag(Int64?.none)
                    }
                    .pickerStyle(.radioGroup)
                    if pickedTotal == nil { AmountField(label: "Amount", text: $otherTotal) }
                } footer: {
                    Text("The total line wasn't clear, so pick the one you paid.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            errorLine
            buttons(primary: ("Use this total", {
                guard let total = pickedTotal ?? Money.parseMinor(otherTotal), total > 0 else { error = FinanceError.invalidAmount.message; return }
                error = nil
                amount = Money.editable(total)
                stage = .review
            }))
        }
    }

    private var review: some View {
        let data = finance.data
        let accounts = data.accounts.values.filter { !$0.archived }.sorted { ($0.kind.isCard ? 0 : 1, $0.createdAtMillis) < ($1.kind.isCard ? 0 : 1, $1.createdAtMillis) }
        let categories = data.categories.values.filter { $0.kind == .expense }
            .sorted { ($0.builtIn ? 0 : 1, $0.sortOrder, $0.name) < ($1.builtIn ? 0 : 1, $1.sortOrder, $1.name) }
        let duplicate = duplicateDismissed ? nil : currentDuplicate
        return VStack(alignment: .leading, spacing: 0) {
            Form {
                if let duplicate { duplicateBanner(duplicate) }
                Section {
                    AmountField(label: "Total", text: $amount)
                    TextField("Merchant", text: $merchant, prompt: Text("Whole Foods Market"))
                        .onChange(of: merchant) { _, new in
                            if !categoryTouched { categoryUid = EntryRules.rememberedCategory(for: new, in: finance.data) }
                        }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    AccountPicker(label: "Paid with", selection: $accountUid, accounts: accounts)
                } footer: {
                    if let last4 = unknownLast4, accountUid.isEmpty {
                        Text("The receipt shows a card ending \(last4), which isn't one of your cards. Pick how you paid, or add the card first.")
                            .font(.grotesk(11)).foregroundStyle(Color.kAmber)
                    } else if receipt.last4 != nil, unknownLast4 == nil {
                        Label("Card ending \(receipt.last4!) on the receipt", systemImage: "checkmark").font(.grotesk(11)).foregroundStyle(Color.kGrowth)
                    }
                }
                Section {
                    CategoryChips(selection: Binding(get: { categoryUid }, set: { categoryUid = $0; categoryTouched = true }),
                                  categories: categories, suggested: EntryRules.rememberedCategory(for: merchant, in: data))
                } header: { Text("Category") }
                if !receipt.items.isEmpty || receipt.taxMinor != nil {
                    Section {
                        DisclosureGroup(isExpanded: $showsItems) {
                            ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                                LabeledContent(item.quantity > 1 ? "\(item.name) × \(item.quantity)" : item.name, value: Money.format(item.amountMinor))
                            }
                            if let tax = receipt.taxMinor { LabeledContent("Tax", value: Money.format(tax)) }
                        } label: {
                            Text(itemSummary).font(.grotesk(13))
                        }
                    } footer: {
                        Text("Line items are kept with the entry.").font(.grotesk(11)).foregroundStyle(Color.kMuted)
                    }
                }
                Section {
                    TextField("Note", text: $note, prompt: Text("Add a note"))
                    Toggle("Keep the receipt image with this entry (on this Mac only)", isOn: $keepImage)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            errorLine
            buttons(primary: ("Save expense", save))
        }
    }

    private func duplicateBanner(_ existing: Entry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Looks like this was already added", systemImage: "doc.on.doc").font(.grotesk(14, .medium)).foregroundStyle(Color.kAmber)
                Text("\(Money.format(existing.amountMinor)) at \(existing.merchant ?? "an expense") on \(EntryFormat.account(existing.accountUid, finance.data)), \(EntryFormat.when(existing)).")
                    .font(.grotesk(12)).foregroundStyle(Color.kInk)
                HStack {
                    Button("Attach receipt to that entry") { attach(to: existing) }.buttonStyle(.borderedProminent).tint(.kSynapse)
                    Button("Add as a new entry") { duplicateDismissed = true }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var errorLine: some View {
        Group {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.grotesk(12)).foregroundStyle(Color.kAlarm)
                    .padding(.horizontal, 24).padding(.bottom, 8)
            }
        }
    }

    private func buttons(primary: (String, () -> Void)?) -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            if let primary {
                Button(primary.0, action: primary.1).keyboardShortcut(.defaultAction).tint(.kSynapse)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: Reading and saving

    private var itemSummary: String {
        let count = receipt.items.reduce(0) { $0 + $1.quantity }
        let parts = [count > 0 ? "\(count) item\(count == 1 ? "" : "s")" : nil, receipt.taxMinor.map { "\(Money.format($0)) tax included" }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func read() async {
        preview = ReceiptScanner.preview(file)
        let text = await ReceiptScanner.recognise(file)
        let parsed = ReceiptParser.parse(text, today: LocalDay.today())
        receipt = parsed
        guard !parsed.unreadable else { stage = .unreadable; return }
        let data = finance.data
        let card = EntryMatching.cardFor(last4: parsed.last4, in: data)
        let name = parsed.merchant ?? ""
        merchant = data.merchants.values.first { $0.payeeKey == FinanceIds.payeeKey(name) }?.displayName ?? name
        categoryUid = EntryRules.rememberedCategory(for: merchant, in: data)
        date = min(parsed.date?.date ?? Date(), Date())
        time = parsed.time
        accountUid = card?.uid ?? ""
        unknownLast4 = card == nil ? parsed.last4 : nil
        if let total = parsed.total {
            amount = Money.editable(total)
            stage = .review
        } else {
            pickedTotal = parsed.candidates.first?.amountMinor
            stage = .pickTotal
        }
    }

    /// When it happened: the receipt's time on its day when printed, else as the phone dates entries.
    private var occurredAt: Int64 {
        let clock = FinanceClock.system
        let day = LocalDay(date: date)
        guard let time, let at = LocalDay.calendar().date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)) else {
            return clock.millisOn(day)
        }
        return Int64(at.timeIntervalSince1970 * 1000)
    }

    private var currentDuplicate: Entry? {
        guard let minor = Money.parseMinor(amount), minor > 0, !accountUid.isEmpty else { return nil }
        return EntryMatching.duplicateOf(amountMinor: minor, accountUid: accountUid, atMillis: occurredAt, exactTime: time != nil,
                                         in: finance.data, clock: .system)
    }

    private func receiptRecord(for uid: String) -> Receipt {
        let kept = keepImage ? ReceiptStore.keep(file, as: uid) : nil
        return Receipt(itemCount: receipt.items.reduce(0) { $0 + $1.quantity }, items: receipt.items, taxMinor: receipt.taxMinor,
                       photoDevicePath: kept?.path, photoMimeType: kept?.mime)
    }

    private func save() {
        guard let minor = Money.parseMinor(amount), minor > 0 else { error = FinanceError.invalidAmount.message; return }
        guard !accountUid.isEmpty else { error = "Pick how you paid."; return }
        let uid = FinanceIds.random()
        let draft = TransactionDraft(type: .expense, amountMinor: minor, accountUid: accountUid, categoryUid: categoryUid,
                                     merchant: merchant, note: note, occurredAtMillis: occurredAt, source: .receipt,
                                     receipt: receiptRecord(for: uid), uid: uid)
        if let failure = finance.apply(EntryRules.add(draft, in: finance.data)) { error = failure.message } else { close() }
    }

    private func attach(to existing: Entry) {
        if let failure = finance.apply(EntryRules.attachReceipt(receiptRecord(for: existing.uid), to: existing.uid, in: finance.data)) {
            error = failure.message
        } else {
            close()
        }
    }
}
