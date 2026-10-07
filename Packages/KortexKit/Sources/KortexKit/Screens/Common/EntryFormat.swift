import KortexFinance
import SwiftUI

typealias Entry = KortexFinance.Transaction
typealias SpendCategory = KortexFinance.Category

/// How an entry reads in lists, tables and the inspector.
enum EntryFormat {
    static func title(_ tx: Entry, _ data: FinanceData) -> String {
        if let merchant = tx.merchant { return merchant }
        if let note = tx.note { return note }
        if tx.isCardCredit { return "Refund / credit" }
        switch tx.type {
        case .opening: return "Opening balance"
        case .transfer: return "Transfer"
        case .cardPayment: return "Card bill payment"
        case .income: return tx.categoryUid.flatMap { data.categories[$0]?.name } ?? "Income"
        case .expense: return tx.categoryUid.flatMap { data.categories[$0]?.name } ?? "Expense"
        }
    }

    /// "HDFC Checking ••4471", or "Deleted account" when it's gone.
    static func account(_ uid: String?, _ data: FinanceData) -> String {
        guard let uid else { return "—" }
        if uid == FinanceIds.unknownAccount { return "Unknown account" }
        if uid == FinanceIds.cardCredit { return "Refund / credit" }
        guard let a = data.accounts[uid] else { return "Deleted account" }
        return a.last4.map { "\(a.name) ••\($0)" } ?? a.name
    }

    static func categoryName(_ uid: String?, _ data: FinanceData) -> String? {
        uid.flatMap { data.categories[$0]?.name }
    }

    static func category(_ tx: Entry, _ data: FinanceData) -> SpendCategory? {
        tx.categoryUid.flatMap { data.categories[$0] }
    }

    /// Money in shows +, money out −, moves between your own accounts show unsigned.
    static func amount(_ tx: Entry) -> String {
        switch tx.type {
        case .income, .opening: Money.format(tx.amountMinor, currency: tx.currency, signed: true)
        case .expense: Money.format(-tx.amountMinor, currency: tx.currency)
        case .transfer, .cardPayment: Money.format(tx.amountMinor, currency: tx.currency)
        }
    }

    static func amountColor(_ tx: Entry) -> Color {
        switch tx.type {
        case .income, .opening: .kGrowth
        case .expense: .kInk
        case .transfer, .cardPayment: .kMuted
        }
    }

    static func source(_ s: TransactionSource) -> String {
        switch s {
        case .manual: "MANUAL"
        case .sms: "SMS"
        case .receipt: "RECEIPT"
        case .recurring: "RECURRING"
        case .agent: "AGENT"
        case .api: "API"
        case .statement: "STATEMENT"
        }
    }

    /// "SMS", "Receipt", "Added by hand": how the entry got in, in words.
    static func sourceName(_ s: TransactionSource) -> String {
        switch s {
        case .manual: "Added by hand"
        case .sms: "SMS"
        case .receipt: "Receipt"
        case .recurring: "Recurring payment"
        case .agent: "Kortex chat"
        case .api: "API"
        case .statement: "Account statement"
        }
    }

    /// The entry's type in words; a card credit reads as one, not as a bill payment.
    static func kind(_ tx: Entry) -> String { tx.isCardCredit ? "Refund / credit" : type(tx.type) }

    static func type(_ t: TransactionType) -> String {
        switch t {
        case .opening: "Opening balance"
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        case .cardPayment: "Card bill payment"
        }
    }

    /// "Mon, 28 Sep 2026 · 6:42 PM".
    static func when(_ tx: Entry) -> String {
        let day = tx.occurredOn.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        let time = Date(timeIntervalSince1970: TimeInterval(tx.occurredAtMillis) / 1000).formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time)"
    }
}

/// The small mono chip in the Source column: SMS, RECEIPT, MANUAL…
struct SourceChip: View {
    let source: TransactionSource

    var body: some View {
        Text(EntryFormat.source(source))
            .font(.mono(9))
            .tracking(0.8)
            .foregroundStyle(Color.kMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.kRaised, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// A category's dot and name.
struct CategoryLabel: View {
    let category: SpendCategory?

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(category.map { Color.token($0.colorToken) } ?? Color.kMuted).frame(width: 8, height: 8)
            Text(category?.name ?? "Uncategorised").font(.grotesk(12)).foregroundStyle(category == nil ? Color.kMuted : Color.kInk)
        }
    }
}
