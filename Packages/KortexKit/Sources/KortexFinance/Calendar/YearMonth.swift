import Foundation

/// A month of a year, like Kotlin's `YearMonth`.
public struct YearMonth: Sendable, Hashable, Comparable {
    public let year: Int
    /// 1–12.
    public let month: Int

    public init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    public init(_ day: LocalDay) {
        self.init(year: day.year, month: day.month)
    }

    public func adding(months: Int) -> YearMonth {
        YearMonth(year: year, month: month + months)
    }

    public var lengthOfMonth: Int {
        LocalDay.utc.range(of: .day, in: .month, for: LocalDay(year: year, month: month, day: 1)!.utcDate)!.count
    }

    public var firstDay: LocalDay { LocalDay(year: year, month: month, day: 1)! }
    public var lastDay: LocalDay { LocalDay(year: year, month: month, day: lengthOfMonth)! }

    /// `day` of this month, or its last day when the month is shorter. Day 31 in September is the 30th.
    public func day(_ day: Int) -> LocalDay {
        LocalDay(year: year, month: month, day: min(max(day, 1), lengthOfMonth))!
    }

    /// Midnight on the 1st in the Mac's zone, for formatting month names.
    public var date: Date { firstDay.date }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

public extension LocalDay {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midnight UTC on this day: the zone-free instant used for day arithmetic.
    internal var utcDate: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    internal init(utcDate: Date) {
        let c = Self.utc.dateComponents([.year, .month, .day], from: utcDate)
        self.init(year: c.year!, month: c.month!, day: c.day!)!
    }

    var yearMonth: YearMonth { YearMonth(self) }

    func adding(days: Int) -> LocalDay {
        LocalDay(utcDate: Self.utc.date(byAdding: .day, value: days, to: utcDate)!)
    }

    /// Days from this day to `other`; negative when `other` is earlier.
    func days(to other: LocalDay) -> Int {
        Self.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// ISO day of week: 1 = Monday … 7 = Sunday.
    var isoWeekday: Int {
        let weekday = Self.utc.component(.weekday, from: utcDate) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    /// The first day on or after this one that falls on ISO weekday `iso` (1 = Monday).
    func nextOrSame(isoWeekday iso: Int) -> LocalDay {
        adding(days: (iso - isoWeekday + 7) % 7)
    }

    func isWithin(_ from: LocalDay, _ to: LocalDay) -> Bool { from <= self && self <= to }
}
