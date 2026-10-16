import Foundation

public enum StatementImportRules {
    /// The accounts you have that a statement could go into: bank accounts for a bank statement,
    /// credit cards for a card's.
    public static func accounts(for extracted: ExtractedAccount, in data: FinanceData) -> [Account] {
        let kind: AccountKind = extracted.kind == .credit_card ? .creditCard : .bank
        return data.accounts.values.filter { $0.kind == kind && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
    }

    /// The account you have that this statement is for, by its last 4 digits.
    public static func existingAccount(for extracted: ExtractedAccount, in data: FinanceData) -> Account? {
        guard let last4 = extracted.numberLast4.map({ String($0.filter(\.isASCIIDigit).suffix(4)) }), last4.count == 4 else { return nil }
        return accounts(for: extracted, in: data).first { $0.last4 == last4 }
    }

    /// Turns the model's reading of one account into a reviewable import: amounts to paise, dates
    /// parsed, categories checked against yours, merchant memory applied, and every row checked
    /// against the running balance printed beside it. Into an account you have (`into`), each row is
    /// also matched against its entries, and rows already there are left out.
    public static func prepare(_ extracted: ExtractedAccount, into existingUid: String? = nil, in data: FinanceData, today: LocalDay) -> StatementImport {
        let kind: AccountKind = extracted.kind == .credit_card ? .creditCard : .bank
        let existing = existingUid.flatMap { data.accounts[$0] }.flatMap { $0.kind == kind ? $0 : nil }
        // A card's bill payment is from your bank when you have one; with several it's unknown until shown.
        let banks = data.accounts.values.filter { $0.kind == .bank && !$0.archived }
        let onlyBank = banks.count == 1 ? banks.first : nil
        var rows: [ImportRow] = []
        var seen: [String: Int] = [:]
        for (i, t) in extracted.transactions.enumerated() {
            let day = parseDay(t.date) ?? parseDay(extracted.periodStart) ?? today
            let rowKind: ImportRow.Kind = kind == .creditCard
                ? (t.direction == .debit ? .expense : .cardPayment)
                : (t.direction == .credit ? .income : .expense)
            let categoryKind: CategoryKind = rowKind == .income ? .income : .expense
            let merchant = t.merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let remembered = merchant.isEmpty ? nil : EntryRules.rememberedCategory(for: merchant, in: data)
            let suggested = t.categoryId.flatMap { data.categories[$0]?.kind == categoryKind ? $0 : nil }
            rows.append(ImportRow(
                id: i, include: true, date: day, description: t.description.trimmingCharacters(in: .whitespacesAndNewlines),
                merchant: merchant, kind: rowKind, amountMinor: minor(t.amount),
                categoryUid: rowKind == .cardPayment ? nil : (remembered.flatMap { data.categories[$0]?.kind == categoryKind ? $0 : nil } ?? suggested),
                fromAccountUid: rowKind == .cardPayment ? onlyBank?.uid : nil,
                reference: t.reference,
                printedBalanceMinor: t.balanceAfter.map { signedBalance($0, debit: t.balanceAfterIsDebit, kind: kind) },
                issue: nil
            ))
            // Two identical rows (two coffees on one day) are told apart by their order.
            let base = "\(t.date)|\(t.direction.rawValue)|\(minor(t.amount))|\(FinanceIds.payeeKey(t.description))"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            rows[i].key = n == 0 ? base : "\(base)|\(n)"
        }

        let opening = extracted.openingBalance.map { signedBalance($0, debit: extracted.openingBalanceIsDebit, kind: kind) }
            ?? inferOpening(rows, kind: kind) ?? 0
        rows = check(rows, opening: opening, kind: kind)
        for i in rows.indices {
            if rows[i].amountMinor <= 0 { rows[i].include = false; rows[i].issue = "No amount was read." }
            if kind == .creditCard && rows[i].kind == .cardPayment && !looksLikePayment(rows[i].description) {
                // A credit that isn't a bill payment: a refund, a reversal, cashback.
                rows[i].kind = .cardCredit
                rows[i].fromAccountUid = nil
            }
        }
        let last4 = existing?.last4 ?? extracted.numberLast4.map { String($0.filter(\.isASCIIDigit).suffix(4)) }
        let transferHints = extracted.transactions.map { $0.ownTransfer == true }
        if kind == .bank {
            rows = markCardPayments(rows, hints: extracted.transactions.map { $0.cardBillPayment == true }, in: data)
            rows = markTransfers(rows, hints: transferHints, into: existing?.uid, in: data)
        }
        if let existing { rows = reconcile(rows, with: existing, in: data) }
        if kind == .bank {
            rows = matchOnCards(rows, in: data)
            rows = matchTransfers(rows, hints: transferHints, into: existing?.uid, last4: last4, in: data)
        }
        if kind == .creditCard { rows = matchOnBanks(rows, cardLast4: last4, in: data) }
        rows = suggestRepeats(markMandates(rows), hints: extracted.transactions.map { $0.recurring == true }, in: data)

        let institution = extracted.institution?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [institution, extracted.productName.map(tidyProduct)].compactMap { $0 }.joined(separator: " ")
        var draft = AccountDraft(
            kind: kind,
            name: name.isEmpty ? (kind == .creditCard ? "Credit card" : "Bank account") : name,
            institution: institution,
            last4: extracted.numberLast4.flatMap { digits -> String? in
                let d = digits.filter(\.isASCIIDigit)
                return d.count >= 4 ? String(d.suffix(4)) : nil
            },
            bankType: kind == .bank ? ((extracted.productName ?? "").localizedCaseInsensitiveContains("current") ? .current : .savings) : nil,
            ifsc: extracted.ifsc,
            holder: extracted.holder.map(TextReading.tidyName)
        )
        var bill: ImportBill?
        if kind == .creditCard {
            draft.creditLimitMinor = extracted.creditLimit.map(minor)
            let statementOn = parseDay(extracted.statementDate) ?? parseDay(extracted.periodEnd)
            let dueOn = parseDay(extracted.paymentDueDate)
            draft.statementDay = statementOn?.day
            draft.dueDay = dueOn?.day
            if let statementOn, let dueOn, let total = extracted.totalDue, total > 0 {
                bill = ImportBill(statementOn: statementOn, dueOn: dueOn, totalMinor: minor(total),
                                  minMinor: extracted.minimumDue.map(minor) ?? 0, periodStart: parseDay(extracted.periodStart))
            }
        }
        let firstDay = rows.map(\.date).min()
        let lastDay = rows.map(\.date).max()
        let openingOn = parseDay(extracted.periodStart) ?? firstDay ?? today
        let closingOn = parseDay(extracted.periodEnd) ?? parseDay(extracted.statementDate) ?? lastDay ?? today
        return StatementImport(
            account: draft,
            openingMinor: opening,
            openingOn: min(openingOn, firstDay ?? openingOn),
            closingMinor: extracted.closingBalance.map { signedBalance($0, debit: extracted.closingBalanceIsDebit, kind: kind) }
                ?? rows.last(where: { $0.printedBalanceMinor != nil })?.printedBalanceMinor,
            closingOn: max(closingOn, lastDay ?? closingOn),
            rows: rows,
            bill: bill,
            accountUid: existing?.uid ?? FinanceIds.random(),
            existingAccountUid: existing?.uid
        )
    }

    /// How many days a statement's date may be from the entry's: cards post a few days after the purchase.
    static let matchWindowDays = 3

    // MARK: Reading the rows

    /// Walks the rows against the balance printed beside each. A row whose amount only fits the
    /// other way round is turned round and flagged; one that fits neither way is flagged.
    static func check(_ input: [ImportRow], opening: Int64, kind: AccountKind) -> [ImportRow] {
        var rows = input
        var running = opening
        for i in rows.indices {
            let effect = StatementImport.effect(rows[i], kind: kind)
            guard let printed = rows[i].printedBalanceMinor else { running += effect; continue }
            if running + effect == printed {
                running = printed
                continue
            }
            if running - effect == printed {
                rows[i].kind = flipped(rows[i].kind, kind: kind, description: rows[i].description)
                rows[i].issue = "Direction corrected to match the printed balance."
            } else {
                rows[i].issue = "Doesn't match the printed balance of \(Money.format(printed)). Check the amount."
            }
            running = printed
        }
        return rows
    }

    private static func flipped(_ k: ImportRow.Kind, kind: AccountKind, description: String) -> ImportRow.Kind {
        if kind == .creditCard { return k == .expense ? (looksLikePayment(description) ? .cardPayment : .cardCredit) : .expense }
        switch k {
        case .transferOut: return .transferIn
        case .transferIn: return .transferOut
        case .income: return .expense
        default: return .income
        }
    }

    /// The balance before the first row, from the first printed balance.
    private static func inferOpening(_ rows: [ImportRow], kind: AccountKind) -> Int64? {
        guard let first = rows.first, let printed = first.printedBalanceMinor else { return nil }
        return printed - StatementImport.effect(first, kind: kind)
    }

    /// A bank balance printed DR is overdrawn (negative). A card's balance is what's owed, positive
    /// when printed DR (or plain); a credit balance on a card is negative.
    static func signedBalance(_ value: Double, debit: Bool?, kind: AccountKind) -> Int64 {
        let m = minor(abs(value))
        if kind == .creditCard { return debit == false || value < 0 ? -m : m }
        return debit == true || value < 0 ? -m : m
    }

    static func minor(_ rupees: Double) -> Int64 {
        Int64((Decimal(rupees) * 100 as NSDecimalNumber).rounding(accordingToBehavior:
            NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
                                   raiseOnUnderflow: false, raiseOnDivideByZero: false)).int64Value)
    }

    static func parseDay(_ text: String?) -> LocalDay? { text.flatMap(LocalDay.init) }

    private static func looksLikePayment(_ description: String) -> Bool {
        let d = description.lowercased()
        return ["payment", "paymt", "pymt", "thank you", "neft", "imps", "upi", "autopay", "auto debit", "bbps"].contains { d.contains($0) }
    }

    private static func tidyProduct(_ product: String) -> String {
        TextReading.tidyName(product.replacingOccurrences(of: "-RES", with: "").replacingOccurrences(of: "ACCOUNT", with: "Account"))
    }

    /// The details' words, lowercased, for the heuristics that look for one.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }
}
