import Foundation

// MARK: Card bills paid from a bank account

extension StatementImportRules {
    /// Turns the debits that pay a credit card bill into card payments, each to the card it paid when
    /// that can be told. One the model flagged or whose details read like a card bill is one. With no
    /// card to pay, it stays money out, flagged: as spending it would count the card's purchases twice.
    static func markCardPayments(_ input: [ImportRow], hints: [Bool], in data: FinanceData) -> [ImportRow] {
        var rows = input
        let cards = data.accounts.values.filter { $0.kind == .creditCard && !$0.archived }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        for i in rows.indices where rows[i].kind == .expense {
            let flagged = rows[i].id < hints.count && hints[rows[i].id]
            guard flagged || looksLikeCardBill(rows[i].description, cards: cards) else { continue }
            guard !cards.isEmpty else {
                rows[i].otherSideMissing = true
                rows[i].categoryUid = nil
                if rows[i].issue == nil {
                    rows[i].issue = "Looks like a credit card bill, with no card in Kortex to pay. It's added as money out for now; importing the card's statement turns it into the bill payment."
                }
                continue
            }
            rows[i].kind = .cardPayment
            rows[i].categoryUid = nil
            rows[i].cardUid = paidCard(rows[i], cards: cards, in: data)
        }
        return rows
    }

    /// Card bill wording as Indian banks print it, or one of your cards' numbers beside a card word.
    /// A debit card's purchases and cash withdrawals never are.
    static func looksLikeCardBill(_ description: String, cards: [Account]) -> Bool {
        let d = description.lowercased()
        let w = words(d)
        guard !d.contains("debit card"), w.isDisjoint(with: ["pos", "atm"]) else { return false }
        if cardBillPhrases.contains(where: d.contains) { return true }
        let mentionsCard = d.contains("card") || !w.isDisjoint(with: ["cc", "bbps", "billpay"])
        return mentionsCard && cards.contains { mentionsNumber(d, of: $0.last4) }
    }

    private static let cardBillPhrases = ["credit card", "creditcard", "cc payment", "ccpayment", "cc pymt", "cc bill", "card bill", "cred club", "credclub"]

    /// The details carry the card's last 4 digits, at the end of a run of digits ("XXXXXXXXXXXX4321").
    static func mentionsNumber(_ text: String, of last4: String?) -> Bool {
        guard let last4, last4.count == 4 else { return false }
        return text.split { !$0.isASCIIDigit }.contains { $0.hasSuffix(last4) }
    }

    /// The card a bill payment went to, when only one fits: the card whose number is in the details,
    /// else whose bill on or before that day was for this amount (in full or the minimum), else whose
    /// bank the details name, else your only card.
    static func paidCard(_ row: ImportRow, cards: [Account], in data: FinanceData) -> String? {
        let d = row.description.lowercased()
        let byBill: (Account) -> Bool = { card in
            guard let bill = billPaid(card.uid, on: row.date, in: data) else { return false }
            return [bill.totalDueMinor, bill.minDueMinor].contains(row.amountMinor)
        }
        let byBank: (Account) -> Bool = { card in
            guard let bank = card.institution?.split(separator: " ").first?.lowercased(), bank.count >= 3 else { return false }
            return words(d).contains(bank) || d.contains(bank + "card")
        }
        let tests: [(Account) -> Bool] = [{ mentionsNumber(d, of: $0.last4) }, byBill, byBank, { _ in true }]
        for test in tests {
            let fits = cards.filter(test)
            if fits.count == 1 { return fits[0].uid }
            if fits.count > 1 { return nil }
        }
        return nil
    }

    static func billPaid(_ cardUid: String, on day: LocalDay, in data: FinanceData) -> CardStatement? {
        EntryRules.billPaid(cardUid, on: day, in: data)
    }

    /// A bill payment a card already has from another account is the same payment as a debit here
    /// when it's for the same amount within a few days. The row then takes its place rather than paying
    /// the card twice, and saving records it as paid from this account. A card payment row matches its
    /// card's payments. So does a debit with no payee, against a payment whose account is unknown (a
    /// card's statement imported before this bank's): the amount is all there is to go by, and the
    /// debit becomes that card's bill payment.
    static func matchOnCards(_ input: [ImportRow], in data: FinanceData) -> [ImportRow] {
        var rows = input
        var taken = Set(rows.compactMap { $0.match?.transactionUid })
        for i in rows.indices where rows[i].include && rows[i].match == nil && rows[i].replaces == nil {
            let row = rows[i]
            let isPayment = row.kind == .cardPayment
            guard isPayment || (row.kind == .expense && row.merchant.cleaned == nil) else { continue }
            let found = data.transactions.values.filter { tx in
                guard tx.type == .cardPayment, !tx.isCardCredit, tx.amountMinor == row.amountMinor, !taken.contains(tx.uid),
                      tx.toAccountUid.flatMap({ data.accounts[$0] })?.kind == .creditCard,
                      abs(row.date.days(to: tx.occurredOn)) <= matchWindowDays else { return false }
                if isPayment { return row.cardUid == nil || tx.toAccountUid == row.cardUid }
                return tx.accountUid == FinanceIds.unknownAccount
            }.min { (abs(row.date.days(to: $0.occurredOn)), $0.uid) < (abs(row.date.days(to: $1.occurredOn)), $1.uid) }
            guard let tx = found, let cardUid = tx.toAccountUid else { continue }
            taken.insert(tx.uid)
            if !isPayment {
                rows[i].kind = .cardPayment
                rows[i].categoryUid = nil
                rows[i].repeats = .no
                rows[i].mandateRef = nil
            }
            rows[i].cardUid = cardUid
            rows[i].replaces = tx.uid
            let card = data.accounts[cardUid].map { c in c.last4.map { "\(c.name) ••\($0)" } ?? c.name } ?? "The card"
            let day = tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
            rows[i].issue = tx.accountUid == FinanceIds.unknownAccount
                ? "\(card) has a bill payment of this amount on \(day) from an unknown account: this is it. Saving records it as paid from this account."
                : "\(card) already has this payment, recorded from \(data.accounts[tx.accountUid]?.name ?? "another account"). Saving records it as paid from this account instead."
        }
        return rows
    }

    /// A card statement's bill payment that a bank statement already recorded as money out (imported
    /// before the card was in Kortex) is that debit: the same amount within a few days, from a bank,
    /// cash or wallet, reading like a card bill or carrying the row's reference, else with no name and
    /// no category (how such a debit is often saved). The row is then paid from that account and
    /// saving turns the debit into this payment, so it's no longer spending and the card isn't paid
    /// twice. Debits paying a recurring payment are left alone.
    static func matchOnBanks(_ input: [ImportRow], cardLast4: String?, in data: FinanceData) -> [ImportRow] {
        var rows = input
        var taken = Set(rows.compactMap { $0.match?.transactionUid })
        let probe = cardLast4.map { last4 in [Account(
            uid: "", kind: .creditCard, name: "", institution: nil, last4: last4, hasSecret: false, bankType: nil, ifsc: nil,
            linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil, dueDay: nil,
            colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)] } ?? []
        for i in rows.indices where rows[i].kind == .cardPayment && rows[i].include && rows[i].match == nil {
            let row = rows[i]
            // How each debit fits: 0 reads like this bill, 1 has nothing to say otherwise; nil doesn't fit.
            func fit(_ tx: Transaction) -> Int? {
                guard tx.type == .expense, tx.recurringUid == nil, tx.amountMinor == row.amountMinor, !taken.contains(tx.uid),
                      abs(row.date.days(to: tx.occurredOn)) <= matchWindowDays,
                      let from = data.accounts[Balances.ledger(of: tx.accountUid, in: data.accounts)], !from.kind.isCard
                else { return nil }
                let details = [tx.merchant, tx.note].compactMap { $0 }.joined(separator: " ")
                if looksLikeCardBill(details, cards: probe) || sameReference(row, tx) { return 0 }
                return tx.merchant == nil && tx.categoryUid == nil ? 1 : nil
            }
            let found = data.transactions.values.compactMap { tx in fit(tx).map { (tx, $0) } }
                .min { ($0.1, abs(row.date.days(to: $0.0.occurredOn)), $0.0.uid) < ($1.1, abs(row.date.days(to: $1.0.occurredOn)), $1.0.uid) }?.0
            guard let tx = found else { continue }
            taken.insert(tx.uid)
            let bank = Balances.ledger(of: tx.accountUid, in: data.accounts)
            rows[i].fromAccountUid = bank
            rows[i].replaces = tx.uid
            let day = tx.occurredOn.date.formatted(.dateTime.day().month(.abbreviated))
            let what = (tx.merchant ?? tx.note).map { "\"\($0)\"" } ?? "A debit with no details"
            rows[i].issue = "\(what), money out from \(data.accounts[bank]?.name ?? "a bank") on \(day), is this payment. Saving makes it "
                + "the card's bill payment, so it no longer counts as spending. Pick another paid-from account to keep it as it is."
        }
        return rows
    }
}
