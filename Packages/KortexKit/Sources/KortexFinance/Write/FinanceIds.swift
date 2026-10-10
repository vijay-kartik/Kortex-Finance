import CryptoKit
import Foundation

/// Document ids, exactly as kortex's domain/FinanceIds.kt makes them. Where two devices could create
/// the same record (the same SMS pasted on both, Netflix marked paid on both) the id comes from what
/// the record is, so both write one document instead of two.
public enum FinanceIds {
    /// Where a card bill payment came from when that account isn't in Kortex yet (a card's statement
    /// imported before the bank's). No account has this uid, so the payment lowers only the card's
    /// balance; the phone shows it as a deleted account. A bank statement with the matching debit later
    /// moves it to that bank (`StatementImportRules.matchOnCards`).
    public static let unknownAccount = "unknown"

    /// Where a card credit that isn't a bill payment (a refund, a reversal, cashback) comes from. It is
    /// saved as a card payment from this uid, which no account has: it lowers what the card owes and
    /// no other balance, pays no bill, and is never matched to a bank's debit. The purchase it refunds
    /// still counts as spending. The phone, which has no refunds yet, shows it as a bill payment from a
    /// deleted account, with the card's balance right.
    public static let cardCredit = "refund"

    /// Lowercase like Java's `UUID.toString()`.
    public static func random() -> String { UUID().uuidString.lowercased() }

    /// One SMS is one transaction, however often or wherever it's pasted.
    public static func smsTransaction(sender: String, body: String) -> String {
        "sms_" + hash(sender.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() + "\n" + body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The transaction that pays one occurrence of a recurring payment.
    public static func recurringOccurrence(_ recurringUid: String, dueOn: LocalDay) -> String {
        "rec_" + hash("\(recurringUid)|\(dueOn)")
    }

    public static func statement(cardUid: String, statementOn: LocalDay) -> String {
        "stmt_" + hash("\(cardUid)|\(statementOn)")
    }

    public static func merchant(_ payeeKey: String) -> String { "mer_" + hash(self.payeeKey(payeeKey)) }

    /// How a merchant or UPI id is matched: lowercase, trimmed, inner whitespace collapsed.
    public static func payeeKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// First 32 hex characters of SHA-256 of the UTF-8 text.
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }
}

/// "Now" and the device's zone, as kortex's port/Clock.kt uses them to date entries.
public struct FinanceClock: Sendable {
    public var nowMillis: Int64
    public var zone: TimeZone

    public init(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000), zone: TimeZone = .current) {
        self.nowMillis = nowMillis
        self.zone = zone
    }

    public static var system: FinanceClock { FinanceClock() }

    public var today: LocalDay { dayOf(nowMillis) }

    public func dayOf(_ millis: Int64) -> LocalDay {
        LocalDay(date: Date(timeIntervalSince1970: TimeInterval(millis) / 1000), in: zone)
    }

    /// When something picked as happening on `day` is saved: now for today, otherwise noon, so the
    /// day can't slip across zones.
    public func millisOn(_ day: LocalDay) -> Int64 {
        if day == today { return nowMillis }
        let noon = LocalDay.calendar(in: zone).date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        return Int64(noon.timeIntervalSince1970 * 1000)
    }
}
