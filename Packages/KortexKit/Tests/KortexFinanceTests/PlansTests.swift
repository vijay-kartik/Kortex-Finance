import Testing
@testable import KortexFinance

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d)! }

private func recurring(_ uid: String, _ kind: RecurringKind, _ frequency: Frequency, amount: Int64, anchor: Int, next: LocalDay,
                       interval: Int = 1, paused: Bool = false) -> Recurring {
    Recurring(uid: uid, name: uid, kind: kind, amountMinor: amount, currency: "INR", frequency: frequency, interval: interval,
              anchorDay: anchor, nextDueOn: next, accountUid: "bank", categoryUid: nil, remindDaysBefore: 2,
              autoMarkPaid: false, paused: paused, createdAtMillis: 0, updatedAtMillis: 0)
}

struct PlansTests {
    @Test func totalsConvertEveryFrequencyToAMonthAndSkipPaused() {
        let items = [
            recurring("netflix", .subscription, .monthly, amount: 64_900, anchor: 3, next: day(2026, 10, 3)),
            recurring("icloud", .subscription, .yearly, amount: 1_200_00, anchor: 12, next: day(2027, 3, 12)),
            recurring("maid", .fixed, .weekly, amount: 30_000, anchor: 6, next: day(2026, 10, 3)),
            recurring("old", .fixed, .monthly, amount: 99_999, anchor: 1, next: day(2026, 10, 1), paused: true),
        ]
        let t = RecurringSchedule.totals(items)
        #expect(t.subscriptionsPerMonthMinor == 64_900 + 10_000)
        #expect(t.fixedPerMonthMinor == 130_000, "₹300 a week is ₹1,300 a month")
        #expect(t.subscriptionCount == 2 && t.fixedCount == 1)
        #expect(t.perYearMinor == (64_900 + 10_000 + 130_000) * 12)
    }

    /// Expected values from kortex's RecurringScheduleTest.kt.
    @Test func nextAfterKeepsToTheAnchorForEveryFrequency() {
        let leap = recurring("prime", .subscription, .yearly, amount: 1_499_00, anchor: 29, next: day(2028, 2, 29))
        #expect(RecurringSchedule.nextAfter(leap, day(2028, 2, 29)) == day(2029, 2, 28))
        #expect(RecurringSchedule.nextAfter(leap, day(2029, 2, 28)) == day(2030, 2, 28))
        #expect(RecurringSchedule.nextAfter(leap, day(2031, 2, 28)) == day(2032, 2, 29), "back on the 29th in a leap year")

        let bimonthly = recurring("water", .fixed, .monthly, amount: 1, anchor: 10, next: day(2026, 10, 10), interval: 2)
        #expect(RecurringSchedule.nextAfter(bimonthly, day(2026, 10, 10)) == day(2026, 12, 10))

        let weekly = recurring("maid", .fixed, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5))
        #expect(RecurringSchedule.nextAfter(weekly, day(2026, 10, 5)) == day(2026, 10, 12))
        #expect(RecurringSchedule.occurrences(weekly, until: day(2026, 11, 2)) ==
                [day(2026, 10, 5), day(2026, 10, 12), day(2026, 10, 19), day(2026, 10, 26), day(2026, 11, 2)])
        let fortnightly = recurring("maid", .fixed, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5), interval: 2)
        #expect(RecurringSchedule.nextAfter(fortnightly, day(2026, 10, 5)) == day(2026, 10, 19))
        #expect(RecurringSchedule.nextAfter(weekly, day(2026, 10, 7)) == day(2026, 10, 19), "a moved date goes back to its weekday")
    }

    @Test func occurrencesStartAtTheNextDueDayOverdueIncludedAndStopWhenPaused() {
        let netflix = recurring("netflix", .subscription, .monthly, amount: 649_00, anchor: 3, next: day(2026, 10, 3))
        #expect(RecurringSchedule.occurrences(netflix, until: day(2026, 10, 29)) == [day(2026, 10, 3)])
        let overdue = recurring("netflix", .subscription, .monthly, amount: 649_00, anchor: 3, next: day(2026, 9, 3))
        #expect(RecurringSchedule.occurrences(overdue, until: day(2026, 10, 29)) == [day(2026, 9, 3), day(2026, 10, 3)])
        let paused = recurring("netflix", .subscription, .monthly, amount: 649_00, anchor: 3, next: day(2026, 10, 3), paused: true)
        #expect(RecurringSchedule.occurrences(paused, until: day(2027, 1, 1)).isEmpty)
        let weekly = recurring("maid", .fixed, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5))
        #expect(RecurringSchedule.occurrences(weekly, until: day(2030, 1, 1)).count == 60)
    }

    @Test func nearestDueFindsTheOccurrenceAPaymentPays() {
        let weekly = recurring("maid", .fixed, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5))
        #expect(RecurringSchedule.nearestDue(weekly, to: day(2026, 10, 8)) == day(2026, 10, 5), "three days late")
        #expect(RecurringSchedule.nearestDue(weekly, to: day(2026, 10, 10)) == day(2026, 10, 12), "two days early")

        let insurance = recurring("insurance", .fixed, .yearly, amount: 1, anchor: 2, next: day(2027, 1, 2))
        #expect(RecurringSchedule.nearestDue(insurance, to: day(2027, 12, 30)) == day(2028, 1, 2), "early, across the new year")
        #expect(RecurringSchedule.nearestDue(insurance, to: day(2028, 1, 6)) == day(2028, 1, 2))
        let leap = recurring("prime", .subscription, .yearly, amount: 1, anchor: 29, next: day(2028, 2, 29))
        #expect(RecurringSchedule.nearestDue(leap, to: day(2029, 3, 2)) == day(2029, 2, 28))
    }

    @Test func perMonthNormalisesWeeklyAndYearlyAmounts() {
        #expect(RecurringSchedule.perMonthMinor(recurring("w", .fixed, .weekly, amount: 100_00, anchor: 1, next: day(2026, 10, 5))) == 433_33)
        #expect(RecurringSchedule.perMonthMinor(recurring("y", .fixed, .yearly, amount: 1_499_00, anchor: 31, next: day(2027, 1, 31))) == 124_92)
        #expect(RecurringSchedule.perMonthMinor(recurring("m", .fixed, .monthly, amount: 20_000_00, anchor: 31, next: day(2027, 1, 31),
                                                          interval: 2)) == 10_000_00)
    }

    @Test func labels() {
        let fortnightly = recurring("x", .fixed, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5), interval: 2)
        #expect(RecurringSchedule.frequencyLabel(fortnightly) == "every 2 weeks")
        #expect(RecurringSchedule.repeatsLabel(fortnightly) == "Every 2 weeks")
        #expect(RecurringSchedule.reminderLabel(-1) == "Off")
        #expect(RecurringSchedule.reminderLabel(0) == "On the day")
    }

    @Test func calendarDueDaysCoverWeeklyOccurrencesAndUnpaidBills() {
        let weekly = recurring("maid", .fixed, .weekly, amount: 30_000, anchor: 6, next: day(2026, 9, 26))
        let statement = CardStatement(uid: "s", cardUid: "card", periodStart: day(2026, 8, 26), statementOn: day(2026, 9, 25),
                                      dueOn: day(2026, 10, 15), totalDueMinor: 140_000, minDueMinor: 20_000, source: .auto,
                                      createdAtMillis: 0, updatedAtMillis: 0)
        let days = Pending.dueDays(in: YearMonth(year: 2026, month: 10), statements: [statement], recurring: [weekly], transactions: [])
        #expect(days.keys.sorted() == [day(2026, 10, 3), day(2026, 10, 10), day(2026, 10, 15), day(2026, 10, 17), day(2026, 10, 24), day(2026, 10, 31)])
        #expect(days[day(2026, 10, 15)] == [.cardBill])
    }
}
