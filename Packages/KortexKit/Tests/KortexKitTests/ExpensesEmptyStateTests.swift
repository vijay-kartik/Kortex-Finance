import KortexFinance
import Testing
@testable import KortexKit

struct ExpensesEmptyStateTests {
    private let today = LocalDay(year: 2026, month: 10, day: 18)!

    @Test func emptyMonthOffersAddExpense() {
        let copy = ExpensesView.emptyCopy(filter: .all, period: .startingAt(today), today: today)
        #expect(copy.title == "No expenses this month")
        #expect(copy.message == "Add an expense to start tracking your month.")
        #expect(copy.action == "Add expense")
        #expect(copy.hint == "⌘N")
        #expect(copy.type == .expense)
    }

    @Test func incomeFilterOffersAddIncome() {
        let copy = ExpensesView.emptyCopy(filter: .income, period: .startingAt(today), today: today)
        #expect(copy.title == "No income this month")
        #expect(copy.action == "Add income")
        #expect(copy.hint == "⇧⌘N")
        #expect(copy.type == .income)
    }

    @Test func namesTheDayAndYear() {
        var period = ExpensesPeriod.startingAt(today)
        period.mode = .daily
        #expect(ExpensesView.emptyCopy(filter: .expenses, period: period, today: today).title == "No expenses today")
        period.mode = .yearly
        #expect(ExpensesView.emptyCopy(filter: .all, period: period, today: today).title == "No expenses this year")
        period.year = 2024
        let past = ExpensesView.emptyCopy(filter: .all, period: period, today: today)
        #expect(past.title == "No expenses in 2024")
        #expect(past.message == "Add an expense to start tracking your year.")
    }
}
