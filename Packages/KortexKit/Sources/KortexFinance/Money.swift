import Foundation

/// Amounts are kept in minor units (paise for INR), as on Android.
public enum Money {
    /// What someone typed in an amount field: "1,234.5", "₹ 42", "42.50" → paise. Nil when it isn't
    /// an amount, or has more than two decimals.
    public static func parseMinor(_ text: String) -> Int64? {
        let clean = text.filter { !$0.isWhitespace && $0 != "," && $0 != "₹" }
        guard !clean.isEmpty, clean.allSatisfy({ $0.isNumber || $0 == "." }), clean.filter({ $0 == "." }).count <= 1 else { return nil }
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        var fraction: Int64 = 0
        if parts.count == 2 {
            let digits = parts[1]
            guard digits.count <= 2 else { return nil }
            fraction = Int64(digits.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        }
        return whole * 100 + fraction
    }

    /// Paise as an editable amount: "42.50", "1245" (no symbol or grouping).
    public static func editable(_ minor: Int64) -> String {
        minor % 100 == 0 ? "\(minor / 100)" : String(format: "%d.%02d", minor / 100, minor % 100)
    }

    /// "₹24,850.12" — Indian digit grouping for INR, the currency's own conventions otherwise.
    /// `wholeUnits` drops the paise, rounding: "₹4,467" for the big pending figure.
    public static func format(_ minor: Int64, currency: String = "INR", signed: Bool = false, wholeUnits: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: currency == "INR" ? "en_IN" : Locale.current.identifier)
        let fractionDigits = formatter.maximumFractionDigits
        if wholeUnits {
            formatter.maximumFractionDigits = 0
            formatter.roundingMode = .halfUp
        }
        let major = Decimal(minor) / pow(10, fractionDigits)
        let text = formatter.string(from: abs(major) as NSDecimalNumber) ?? "\(major)"
        if minor < 0 { return "−" + text }
        return signed && minor > 0 ? "+" + text : text
    }
}
