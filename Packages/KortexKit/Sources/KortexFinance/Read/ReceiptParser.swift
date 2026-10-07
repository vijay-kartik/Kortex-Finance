import Foundation

/// One amount that could be what was paid (Figma: Scan receipt 04).
public struct TotalCandidate: Sendable, Hashable {
    public let amountMinor: Int64
    public let label: String
}

/// A receipt, read from the text recognised in its image.
public struct ParsedReceipt: Sendable {
    public var merchant: String?
    public var date: LocalDay?
    public var time: DayTime?
    /// Most likely first. More than one, and `total` nil, means the person has to pick.
    public var candidates: [TotalCandidate] = []
    public var total: Int64?
    public var taxMinor: Int64?
    public var items: [ReceiptItem] = []
    public var last4: String?

    /// Nothing that looks like money: too blurry, or not a receipt (Scan receipt 06).
    public var unreadable: Bool { candidates.isEmpty && total == nil }

    public init(merchant: String? = nil, date: LocalDay? = nil, time: DayTime? = nil, candidates: [TotalCandidate] = [],
                total: Int64? = nil, taxMinor: Int64? = nil, items: [ReceiptItem] = [], last4: String? = nil) {
        self.merchant = merchant
        self.date = date
        self.time = time
        self.candidates = candidates
        self.total = total
        self.taxMinor = taxMinor
        self.items = items
        self.last4 = last4
    }
}

/// Reads the text recognised on a receipt, as kortex's domain/read/Receipt.kt: patterns find the
/// total, tax, items, date and card.
public enum ReceiptParser {
    public static func parse(_ text: String, today: LocalDay) -> ParsedReceipt {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return ParsedReceipt() }

        struct Priced { let line: String; let label: String; let amountMinor: Int64 }
        let priced: [Priced] = lines.compactMap { line in
            guard let m = TextReading.bareAmount.matches(in: line).last, let minor = TextReading.minorOf(m.value) else { return nil }
            return Priced(line: line, label: line[..<m.range.lowerBound].trimmingCharacters(in: .whitespaces), amountMinor: minor)
        }

        let total = priced.last { total.contains(in: $0.label) && !subtotal.contains(in: $0.label) }
        let sub = priced.last { subtotal.contains(in: $0.label) }
        let taxSum = priced.filter { tax.contains(in: $0.label) && !self.total.contains(in: $0.label) }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let taxMinor = taxSum > 0 ? taxSum : nil
        let paidLine = priced.last { paid.contains(in: $0.line) }

        var candidates: [TotalCandidate] = []
        if let total { candidates.append(TotalCandidate(amountMinor: total.amountMinor, label: taxMinor.map { "Total, incl. \(rupees($0)) GST" } ?? "Total")) }
        if let paidLine, paidLine.amountMinor != total?.amountMinor { candidates.append(TotalCandidate(amountMinor: paidLine.amountMinor, label: "Paid by card")) }
        if total == nil, let sub, let taxMinor { candidates.append(TotalCandidate(amountMinor: sub.amountMinor + taxMinor, label: "Subtotal plus tax")) }
        if let sub { candidates.append(TotalCandidate(amountMinor: sub.amountMinor, label: "Subtotal, before tax")) }
        if candidates.isEmpty, let largest = priced.max(by: { $0.amountMinor < $1.amountMinor }) {
            candidates.append(TotalCandidate(amountMinor: largest.amountMinor, label: "Largest amount"))
        }
        var seen = Set<Int64>()
        candidates = candidates.filter { seen.insert($0.amountMinor).inserted }

        // Sure when the total line is there and the card payment, if printed, agrees with it.
        let sure = total != nil && (paidLine == nil || paidLine!.amountMinor == total!.amountMinor)

        let itemEnd = priced.firstIndex { subtotal.contains(in: $0.label) || self.total.contains(in: $0.label) || tax.contains(in: $0.label) }
        let items: [ReceiptItem] = priced.prefix(itemEnd ?? priced.count)
            .filter { $0.label.contains(where: \.isLetter) && !notAnItem.contains(in: $0.line) }
            .map { p in
                let qty = quantity.firstMatch(in: p.label)
                var name = p.label
                if let qty { name.removeSubrange(qty.range) }
                name = name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-:.")).trimmingCharacters(in: .whitespaces)
                let count = qty?.groups.compactMap { $0 }.first { !$0.isEmpty }.flatMap(Int.init) ?? 1
                return ReceiptItem(name: name, quantity: count, amountMinor: p.amountMinor)
            }
            .filter { $0.name.count >= 2 }

        return ParsedReceipt(
            merchant: merchant(lines),
            date: TextReading.date(text, today: today)?.value,
            time: TextReading.time(text)?.value,
            candidates: candidates,
            total: sure ? total!.amountMinor : (candidates.count == 1 ? candidates[0].amountMinor : nil),
            taxMinor: taxMinor,
            items: items,
            last4: card.firstMatch(in: text)?.groups[0]
        )
    }

    /// The first line that reads like a name: letters, not an address, tax id, date or heading.
    private static func merchant(_ lines: [String]) -> String? {
        lines.prefix(6).first { line in
            line.filter(\.isLetter).count >= 3 && !notAName.contains(in: line) && line.filter(\.isASCIIDigit).count <= 2
        }.map(TextReading.tidyName)
    }

    private static func rupees(_ minor: Int64) -> String { "₹\((minor + 50) / 100)" }

    private static let total = Pattern(#"\b(grand\s+total|total|net\s+amount|amount\s+due|bill\s+amount|amount\s+payable|net\s+payable)\b"#, ignoreCase: true)
    private static let subtotal = Pattern(#"\bsub\s*-?\s*total\b"#, ignoreCase: true)
    private static let tax = Pattern(#"\b(cgst|sgst|igst|gst|vat|tax|cess|service\s+charge)\b"#, ignoreCase: true)
    private static let paid = Pattern(#"\b(paid|visa|mastercard|master\s+card|rupay|amex|card|upi)\b"#, ignoreCase: true)
    private static let card = Pattern(#"[*xX•]{2,}\s*(\d{4})\b"#)
    private static let quantity = Pattern(#"(?:\bx\s?(\d{1,3})\b|\b(\d{1,3})\s?x\b|\bqty[:\s]*(\d{1,3})\b)"#, ignoreCase: true)
    private static let notAnItem = Pattern(#"\b(change|cash|tender|round(ing)?\s*off|discount|balance|paid|visa|card|upi)\b"#, ignoreCase: true)
    private static let notAName = Pattern(
        #"\b(tax\s+invoice|invoice|receipt|bill\s*(no|#)|gstin|fssai|phone|tel|ph[:.]|road|rd\b|street|st\b|nagar|floor|main|cross|sector|date|time|table|cashier|welcome)\b"#,
        ignoreCase: true
    )
}

/// Which account a receipt is about, and whether it's already been added, as kortex's EntryMatching.kt.
public enum EntryMatching {
    public static let receiptDuplicateMinutes: Int64 = 60

    /// The card whose last 4 digits these are; nil means ask. Cards are preferred for a receipt.
    public static func cardFor(last4: String?, in data: FinanceData) -> Account? {
        guard let last4 else { return nil }
        let matches = data.accounts.values.filter { !$0.archived && $0.last4 == last4 }.sorted { $0.createdAtMillis < $1.createdAtMillis }
        return matches.first { $0.kind.isCard } ?? matches.first
    }

    /// An expense this receipt probably repeats (Scan receipt 05): the same amount on the same card
    /// within an hour, or the same day when the receipt has no time. Only expenses without a receipt.
    public static func duplicateOf(amountMinor: Int64, accountUid: String?, atMillis: Int64, exactTime: Bool,
                                   in data: FinanceData, clock: FinanceClock) -> Transaction? {
        guard let accountUid else { return nil }
        let day = clock.dayOf(atMillis)
        return data.transactions.values
            .filter { $0.type == .expense && $0.receipt == nil && $0.amountMinor == amountMinor && $0.accountUid == accountUid }
            .filter { exactTime ? abs($0.occurredAtMillis - atMillis) <= receiptDuplicateMinutes * 60_000 : $0.occurredOn == day }
            .min { abs($0.occurredAtMillis - atMillis) < abs($1.occurredAtMillis - atMillis) }
    }
}
