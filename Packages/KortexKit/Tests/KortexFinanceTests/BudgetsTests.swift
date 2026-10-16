import Foundation
import Testing
@testable import KortexFinance

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d)! }

private let today = day(2026, 9, 29)
private let aug = YearMonth(year: 2026, month: 8)
private let sep = YearMonth(year: 2026, month: 9)
private let categories = BuiltInCategories.all + [Category(uid: "fun", name: "Fun", kind: .expense, colorToken: "Rose", builtIn: false, sortOrder: 0)]

private func tx(_ type: TransactionType, _ amount: Int64, _ on: LocalDay, _ account: String, to: String? = nil, category: String? = nil) -> Transaction {
    Transaction(uid: UUID().uuidString, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: on,
                       accountUid: account, toAccountUid: to, categoryUid: category, merchant: nil, payeeKey: nil, note: nil,
                       source: .manual, sourceRef: nil, recurringUid: nil, dueOn: nil, statementUid: nil,
                       receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
}

/// kortex's BudgetsTest.kt, case for case.
struct BudgetsTests {
    @Test func noBudgetsMeansTheMonthIsNotBudgeted() {
        let txs = [tx(.expense, 100_00, day(2026, 9, 2), "cash", category: "food")]
        let none = Budgets.status(txs, categories: categories, budgets: [:], month: sep, today: today)
        #expect(none.categories.isEmpty)
        #expect(none.overall == nil)
        // An income category can't be budgeted, nor can one that's gone.
        let ignored = Budgets.status(txs, categories: categories, budgets: ["salary": 1_000_00, "gone": 500_00], month: sep, today: today)
        #expect(ignored.categories.isEmpty)
        #expect(ignored.overall == nil)
    }

    @Test func underAtAndOverBudgetMostUsedFirst() throws {
        let txs = [
            tx(.expense, 3_000_00, day(2026, 8, 5), "cash", category: "food"),
            tx(.expense, 1_000_00, day(2026, 8, 10), "kortex", category: "travel"),
            tx(.expense, 600_00, day(2026, 8, 20), "checking", category: "utilities"),
            tx(.expense, 900_00, day(2026, 9, 1), "cash", category: "food"), // September: not August
        ]
        let budgets: [String: Int64] = ["food": 4_000_00, "travel": 1_000_00, "utilities": 500_00]
        let summary = Budgets.status(txs, categories: categories, budgets: budgets, month: aug, today: today)

        #expect(summary.categories.map(\.categoryUid) == ["utilities", "travel", "food"])
        let (utilities, travel, food) = (summary.categories[0], summary.categories[1], summary.categories[2])
        #expect(utilities.percentUsed == 120)
        #expect(utilities.leftMinor == -100_00)
        #expect(travel.percentUsed == 100)
        #expect(travel.leftMinor == 0)
        #expect(food.percentUsed == 75)
        #expect(food.leftMinor == 1_000_00)
        #expect(food.name == "Food")
        // August is over: the projection is what was spent.
        #expect(food.projectedMinor == 3_000_00)

        let overall = try #require(summary.overall)
        #expect(overall.budgetMinor == 5_500_00)
        #expect(overall.spentMinor == 4_600_00)
        #expect(overall.leftMinor == 900_00)
        #expect(overall.percentUsed == 84)
        #expect(overall.projectedMinor == 4_600_00)
    }

    @Test func uncategorisedAndUnbudgetedSpendStayOut() {
        let txs = [
            tx(.expense, 200_00, day(2026, 8, 3), "cash", category: "food"),
            tx(.expense, 700_00, day(2026, 8, 4), "cash"), // Uncategorised
            tx(.expense, 300_00, day(2026, 8, 5), "cash", category: "fun"), // no budget
            tx(.expense, 400_00, day(2026, 8, 6), "cash", category: "gone"), // deleted category
        ]
        let summary = Budgets.status(txs, categories: categories, budgets: ["food": 1_000_00], month: aug, today: today)
        #expect(summary.categories.map(\.categoryUid) == ["food"])
        #expect(summary.categories.first?.spentMinor == 200_00)
        #expect(summary.overall?.budgetMinor == 1_000_00)
        #expect(summary.overall?.spentMinor == 200_00)
    }

    @Test func incomeTransfersAndCardBillsNeverCountAsSpend() {
        let txs = [
            tx(.income, 5_000_00, day(2026, 8, 1), "checking", category: "food"),
            tx(.transfer, 500_00, day(2026, 8, 2), "checking", to: "savings", category: "food"),
            tx(.cardPayment, 1_400_00, day(2026, 8, 3), "checking", to: "kortex", category: "food"),
            tx(.expense, 250_00, day(2026, 8, 4), "cash", category: "food"),
        ]
        let food = Budgets.status(txs, categories: categories, budgets: ["food": 1_000_00], month: aug, today: today).categories
        #expect(food.count == 1)
        #expect(food.first?.spentMinor == 250_00)
        #expect(food.first?.percentUsed == 25)
    }

    @Test func earlyInTheMonthTheProjectionFollowsThePace() throws {
        let today = day(2026, 9, 3)
        let txs = [
            tx(.expense, 200_00, day(2026, 9, 1), "cash", category: "food"),
            tx(.expense, 100_00, day(2026, 9, 3), "cash", category: "food"),
            tx(.expense, 50_00, day(2026, 9, 2), "cash", category: "travel"),
        ]
        let budgets: [String: Int64] = ["food": 2_000_00, "travel": 1_000_00, "utilities": 500_00]
        let summary = Budgets.status(txs, categories: categories, budgets: budgets, month: sep, today: today)

        let food = try #require(summary.categories.first { $0.categoryUid == "food" })
        #expect(food.spentMinor == 300_00)
        #expect(food.percentUsed == 15)
        #expect(food.projectedMinor == 3_000_00, "₹300 in 3 days → ₹3,000 by the 30th: over")
        let utilities = try #require(summary.categories.first { $0.categoryUid == "utilities" })
        #expect(utilities.spentMinor == 0)
        #expect(utilities.projectedMinor == 0)
        #expect(summary.overall?.projectedMinor == 3_500_00)
        #expect(summary.overall?.projectedMinor == Spending.projectedMonthEndMinor(txs, today: today))
    }

    // MARK: Mac

    @Test func theDashboardWarnsOfTheLargestProjectedOvershoot() {
        var data = FinanceData()
        data.apply([RemoteRow.live(tx(.expense, 300_00, day(2026, 9, 1), "cash", category: "food")),
                    .live(tx(.expense, 150_00, day(2026, 9, 2), "cash", category: "travel"))])
        let model = { DashboardModel(data: data, today: day(2026, 9, 3)) }
        #expect(model().overBudget == nil, "nothing is budgeted")

        // At this pace Food ends near ₹3,000, ₹1,000 over; Travel near ₹1,500, ₹500 over.
        data.apply([RemoteRow.live(Budget(categoryUid: "food", amountMinor: 2_000_00, createdAtMillis: 0, updatedAtMillis: 0)),
                    .live(Budget(categoryUid: "travel", amountMinor: 1_000_00, createdAtMillis: 0, updatedAtMillis: 0))])
        #expect(model().overBudget?.categoryUid == "food")
        #expect(model().overBudget.map { $0.projectedMinor - $0.budgetMinor } == 1_000_00)

        data.apply([RemoteRow.live(Budget(categoryUid: "food", amountMinor: 5_000_00, createdAtMillis: 0, updatedAtMillis: 0))])
        #expect(model().overBudget?.categoryUid == "travel")
        data.apply([RemoteRow<Budget>.deleted(uid: "travel")])
        #expect(model().overBudget == nil, "Food's ₹3,000 is under its ₹5,000")
    }
}
