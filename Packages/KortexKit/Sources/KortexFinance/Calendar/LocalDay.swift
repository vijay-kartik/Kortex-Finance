import Foundation

/// A calendar day with no time or zone, stored as `yyyy-MM-dd` like Kotlin's `LocalDate`.
/// Finance groups by these rather than by instants, so a day means what it meant on the device that saved it.
public struct LocalDay: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard (1...12).contains(month), (1...31).contains(day),
              let date = Self.utc.date(from: components),
              Self.utc.component(.day, from: date) == day
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`; nil for anything else, including impossible dates.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Today in the given zone (the Mac's own by default).
    public static func today(in timeZone: TimeZone = .current) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return LocalDay(year: c.year!, month: c.month!, day: c.day!)!
    }

    /// Midnight at the start of this day in the Mac's zone, for formatting.
    public var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

}
