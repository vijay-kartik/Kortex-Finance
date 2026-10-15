import Testing
@testable import KortexFinance

struct CategoryOrderTests {
    private func custom(_ uid: String, _ name: String, sortOrder: Int, kind: CategoryKind = .expense) -> Category {
        Category(uid: uid, name: name, kind: kind, colorToken: "Lilac", builtIn: false, sortOrder: sortOrder)
    }

    @Test func listsBuiltInFirstThenSortOrderThenName() {
        let pets = custom("c1", "Pets", sortOrder: 0)
        let books = custom("c2", "Books", sortOrder: 0)
        let rent = custom("c3", "Rent", sortOrder: -1)
        let all = [pets, BuiltInCategories.utilities, books, rent, BuiltInCategories.food, BuiltInCategories.travel]
        #expect(Category.listed(all).map(\.uid) == ["food", "travel", "utilities", "c3", "c2", "c1"])
    }

    @Test func sameSortOrderAndNameStillListInOneOrder() {
        let a = custom("a", "Gifts", sortOrder: 0)
        let b = custom("b", "Gifts", sortOrder: 0)
        #expect(Category.listed([b, a]).map(\.uid) == ["a", "b"])
        #expect(Category.listed([a, b]).map(\.uid) == ["a", "b"])
    }

    @Test func keepsOnlyTheKindAskedFor() {
        let bonus = custom("c1", "Bonus", sortOrder: 0, kind: .income)
        let all = BuiltInCategories.all + [bonus]
        #expect(Category.listed(all, kind: .income).map(\.uid) == ["salary", "c1"])
        #expect(Category.listed(all, kind: .expense).map(\.uid) == ["food", "travel", "utilities"])
    }
}
