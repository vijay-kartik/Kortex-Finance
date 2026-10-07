import Foundation

/// A compiled pattern with Java-like semantics (ICU), so kortex's Kotlin regexes port unchanged.
struct Pattern: @unchecked Sendable {
    struct Match {
        let range: Range<String.Index>
        let value: String
        /// Capture groups 1…n; nil when a group didn't take part.
        let groups: [String?]
        let groupRanges: [Range<String.Index>?]
    }

    private let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    func matches(in text: String) -> [Match] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let range = Range(m.range, in: text) else { return nil }
            var groups: [String?] = []
            var ranges: [Range<String.Index>?] = []
            for i in stride(from: 1, to: m.numberOfRanges, by: 1) {
                let r = Range(m.range(at: i), in: text)
                ranges.append(r)
                groups.append(r.map { String(text[$0]) })
            }
            return Match(range: range, value: String(text[range]), groups: groups, groupRanges: ranges)
        }
    }

    func firstMatch(in text: String) -> Match? { matches(in: text).first }
    func contains(in text: String) -> Bool { firstMatch(in: text) != nil }
}

/// A value found in a text and where.
public struct Found<T> {
    public let value: T
    public let range: Range<String.Index>
}

/// A time of day, as receipts print it.
public struct DayTime: Sendable, Hashable {
    public let hour: Int
    public let minute: Int
}

/// Amounts, dates and times as Indian receipts write them, as kortex's domain/read/TextReading.kt.
public enum TextReading {
    /// A bare amount with paise, as receipts print it: "1,239.00".
    static let bareAmount = Pattern(#"(?<![\d.,])([0-9][0-9,]*\.[0-9]{2})(?![\d])"#)

    /// "48,557.50" → 4855750 paise; nil if it isn't a number.
    public static func minorOf(_ text: String) -> Int64? {
        let clean = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean.filter({ $0 == "." }).count <= 1 else { return nil }
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let fraction = String((parts.count > 1 ? String(parts[1]) : "").padding(toLength: 2, withPad: "0", startingAt: 0).prefix(2))
        guard whole.allSatisfy(\.isASCIIDigit), fraction.allSatisfy(\.isASCIIDigit), whole.count <= 12,
              let w = Int64(whole), let f = Int64(fraction) else { return nil }
        return w * 100 + f
    }

    private static let numeric = Pattern(#"(?<!\d)(\d{1,4})[-/.](\d{1,2})[-/.](\d{2,4})(?!\d)"#)
    private static let named = Pattern(
        #"(?<!\d)(\d{1,2})(?:st|nd|rd|th)?[\s-]?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?(?:[\s,-]+'?(\d{2,4}))?(?!\d)"#,
        ignoreCase: true
    )
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// The first date in `text`: "28-09-26", "28/09/2026", "2026-09-28", "28 Sep", "28-Sep-26". Day
    /// before month, as in India. A date without a year takes the one that keeps it on or before today.
    public static func date(_ text: String, today: LocalDay) -> Found<LocalDay>? {
        var candidates: [Found<LocalDay>] = []
        for m in numeric.matches(in: text) {
            guard let a = m.groups[0], let b = m.groups[1], let c = m.groups[2], let bi = Int(b) else { continue }
            let day = a.count == 4
                ? Int(c).flatMap { LocalDay(year: Int(a)!, month: bi, day: $0) }
                : Int(a).flatMap { LocalDay(year: year(c), month: bi, day: $0) }
            if let day { candidates.append(Found(value: day, range: m.range)) }
        }
        for m in named.matches(in: text) {
            guard let d = m.groups[0].flatMap(Int.init), let name = m.groups[1],
                  let month = months.firstIndex(of: String(name.prefix(3)).lowercased()).map({ $0 + 1 }) else { continue }
            let day: LocalDay?
            if let explicit = m.groups[2], !explicit.isEmpty {
                day = LocalDay(year: year(explicit), month: month, day: d)
            } else if let thisYear = LocalDay(year: today.year, month: month, day: d) {
                day = thisYear > today ? LocalDay(year: today.year - 1, month: month, day: d) : thisYear
            } else {
                day = nil
            }
            if let day { candidates.append(Found(value: day, range: m.range)) }
        }
        return candidates.min { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static let clock = Pattern(#"(?<!\d)(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp]\.?[Mm]\.?)?(?!\d)"#)

    /// The first time in `text`: "18:42", "6:42 PM", "06:42:10 pm".
    public static func time(_ text: String) -> Found<DayTime>? {
        for m in clock.matches(in: text) {
            guard var hour = m.groups[0].flatMap(Int.init), let minute = m.groups[1].flatMap(Int.init) else { continue }
            let meridiem = (m.groups[2] ?? "").lowercased().replacingOccurrences(of: ".", with: "")
            if meridiem == "pm" && hour < 12 { hour += 12 }
            if meridiem == "am" && hour == 12 { hour = 0 }
            if (0..<24).contains(hour) && (0..<60).contains(minute) { return Found(value: DayTime(hour: hour, minute: minute), range: m.range) }
        }
        return nil
    }

    private static func year(_ text: String) -> Int {
        let n = Int(text) ?? 0
        return text.count == 2 ? 2000 + n : n
    }

    private static let companySuffixes: Set<String> = ["PVT", "PRIVATE", "LTD", "LIMITED", "LLP", "INC", "CO", "CORP"]
    private static let keepUpper: Set<String> = ["UK", "US", "IN", "HP", "TV", "SBI"]

    /// "WHOLE FOODS MARKET" → "Whole Foods Market"; company suffixes dropped.
    public static func tidyName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept = words
        while let last = kept.last, companySuffixes.contains(last.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()) {
            kept.removeLast()
        }
        if kept.isEmpty { kept = words }
        let shouting = !kept.contains { $0.contains(where: \.isLowercase) }
        return kept.map { word in
            if !shouting || (word.count <= 2 && word.allSatisfy(\.isLetter) && keepUpper.contains(word.uppercased())) { return word }
            return word.lowercased().prefix(1).uppercased() + word.lowercased().dropFirst()
        }.joined(separator: " ")
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
