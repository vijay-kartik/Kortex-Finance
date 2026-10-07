import Foundation
import Testing
@testable import KortexFinance

struct FinanceDocsTests {
    private let expense: [String: Any] = [
        "type": "EXPENSE", "amountMinor": NSNumber(value: 4250), "currency": "INR",
        "occurredAt": NSNumber(value: 1_790_000_000_000 as Int64), "occurredOn": "2026-09-28",
        "accountUid": "card-8824", "categoryUid": "food", "merchant": "Whole Foods Market",
        "source": "SMS", "updatedAt": NSNumber(value: 1_790_000_000_500 as Int64), "deleted": false,
        "receipt": ["itemCount": 4, "items": [["name": "Bananas", "qty": 2, "amountMinor": 840]], "taxMinor": 202] as [String: Any],
    ]

    @Test func readsAnExpenseAsAndroidWritesIt() throws {
        guard case .live(let tx) = FinanceDocs.transaction(uid: "t1", expense) else {
            Issue.record("expected a live transaction")
            return
        }
        #expect(tx.type == .expense)
        #expect(tx.amountMinor == 4250)
        #expect(tx.occurredOn == LocalDay(year: 2026, month: 9, day: 28))
        #expect(tx.source == .sms)
        #expect(tx.createdAtMillis == 1_790_000_000_500, "falls back to updatedAt without createdAt")
        #expect(tx.receipt?.itemCount == 4)
        #expect(tx.receipt?.items.first?.quantity == 2)
    }

    @Test func numbersWrittenFromJavaScriptMayBeDoubles() {
        var doc = expense
        doc["amountMinor"] = 4250.0
        guard case .live(let tx) = FinanceDocs.transaction(uid: "t1", doc) else {
            Issue.record("expected a live transaction")
            return
        }
        #expect(tx.amountMinor == 4250)
    }

    @Test func aDeleteMarkerNeedsOnlyUpdatedAt() {
        let doc: [String: Any] = ["updatedAt": NSNumber(value: 5), "deleted": true]
        guard case .deleted(let uid) = FinanceDocs.transaction(uid: "t1", doc) else {
            Issue.record("expected a delete")
            return
        }
        #expect(uid == "t1")
    }

    @Test func skipsWhatItCannotApply() {
        var noUpdatedAt = expense
        noUpdatedAt["updatedAt"] = nil
        #expect(FinanceDocs.transaction(uid: "t", noUpdatedAt) == nil)

        var unknownType = expense
        unknownType["type"] = "REFUND"
        #expect(FinanceDocs.transaction(uid: "t", unknownType) == nil, "an enum only a newer app knows")

        var badDay = expense
        badDay["occurredOn"] = "2026-02-30"
        #expect(FinanceDocs.transaction(uid: "t", badDay) == nil)

        var zero = expense
        zero["amountMinor"] = 0
        #expect(FinanceDocs.transaction(uid: "t", zero) == nil)
    }

    @Test func syncedCategoriesNeverReplaceBuiltIns() {
        var data = FinanceData()
        data.apply([
            RemoteRow.live(Category(uid: "food", name: "Groceries", kind: .expense, colorToken: "Mint", builtIn: false, sortOrder: 9)),
            RemoteRow.deleted(uid: "salary"),
            RemoteRow.live(Category(uid: "c1", name: "Shopping", kind: .expense, colorToken: "Lilac", builtIn: false, sortOrder: 3)),
        ])
        #expect(data.categories["food"]?.name == "Food")
        #expect(data.categories["salary"] != nil)
        #expect(data.categories["c1"]?.name == "Shopping")
    }
}

extension RemoteRow: Equatable where Row: Equatable {
    public static func == (lhs: RemoteRow, rhs: RemoteRow) -> Bool {
        switch (lhs, rhs) {
        case let (.live(a), .live(b)): a == b
        case let (.deleted(a), .deleted(b)): a == b
        default: false
        }
    }
}
