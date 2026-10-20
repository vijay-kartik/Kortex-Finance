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

    @Test func labels() {
        let fortnightly = recurring("x", .fixed, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5), interval: 2)
        #expect(RecurringSchedule.frequencyLabel(fortnightly) == "every 2 weeks")
        #expect(RecurringSchedule.repeatsLabel(fortnightly) == "Every 2 weeks")
        #expect(RecurringSchedule.repeatsLabel(.yearly, interval: 1) == "Every year")
        #expect(Frequency.monthly.unit == "month")
        #expect(RecurringSchedule.reminderLabel(-1) == "Off")
        #expect(RecurringSchedule.reminderLabel(0) == "On the day")
    }

    @Test func pendingSubtitles() {
        func item(_ kind: PendingKind, min: Int64? = nil) -> PendingItem {
            PendingItem(kind: kind, sourceUid: "x", title: "x", amountMinor: 1, dueOn: day(2026, 10, 5), minDueMinor: min)
        }
        let fortnightly = recurring("x", .subscription, .weekly, amount: 1, anchor: 1, next: day(2026, 10, 5), interval: 2)
        let monthly = recurring("x", .fixed, .monthly, amount: 1, anchor: 5, next: day(2026, 10, 5))
        #expect(Pending.subtitle(item(.cardBill, min: 120_000), recurring: nil) == "Card bill · min ₹1,200")
        #expect(Pending.subtitle(item(.cardBill), recurring: nil) == "Card bill")
        #expect(Pending.subtitle(item(.subscription), recurring: fortnightly) == "Subscription · every 2 weeks")
        #expect(Pending.subtitle(item(.fixed), recurring: monthly) == "Fixed · monthly")
        #expect(Pending.subtitle(item(.subscription), recurring: nil) == "Subscription", "no trailing separator")
        #expect(RecurringKind.subscription.pendingKind == .subscription && RecurringKind.fixed.pendingKind == .fixed)
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
