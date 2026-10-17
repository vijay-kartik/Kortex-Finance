import Foundation
import KortexFinance
import Testing
@testable import KortexKit

/// Each helper keeps the text of the format chain its call sites used to spell out, in any locale.
struct FormatTests {
    let day = LocalDay(year: 2026, month: 10, day: 3)!

    @Test func shortDayIsDayAndShortMonth() {
        #expect(Format.shortDay(day) == day.date.formatted(.dateTime.day().month(.abbreviated)))
    }

    @Test func shortDayYearAddsTheYear() {
        #expect(Format.shortDayYear(day) == day.date.formatted(.dateTime.day().month(.abbreviated).year()))
    }

    @Test func monthYearIsWideMonthAndYear() {
        let month = YearMonth(year: 2026, month: 10)
        #expect(Format.monthYear(month) == month.date.formatted(.dateTime.month(.wide).year()))
        #expect(Format.monthYear(day.yearMonth) == day.date.formatted(.dateTime.month(.wide).year()))
    }

    @Test func fullDueDayIsDueDayWithTheYear() {
        #expect(Format.fullDueDay(day) == day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
    }
}
