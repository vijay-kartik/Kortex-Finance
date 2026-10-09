import SwiftUI
import Testing
@testable import KortexFinance
@testable import KortexKit

/// Screen actions driven through `PreviewFinanceStore`, without Firebase.
@MainActor
struct FinanceStoreTests {
    private func expenses(_ store: PreviewFinanceStore) -> [KortexFinance.Transaction] {
        store.data.transactions.values.filter { $0.type == .expense }.sorted { $0.amountMinor < $1.amountMinor }
    }

    @Test func setCategoryFromTheEntriesMenuRefilesTheEntries() {
        let store = PreviewFinanceStore.sample()
        let picked = Set(expenses(store).prefix(2).map(\.uid))
        var deleting: [Entry] = []
        let binding = Binding(get: { deleting }, set: { deleting = $0 })

        EntryActions.perform(.setCategory(BuiltInCategories.utilities.uid), on: picked, finance: store, model: AppModel(), deleting: binding)

        #expect(store.changes.count == 1)
        for uid in picked { #expect(store.data.transactions[uid]?.categoryUid == BuiltInCategories.utilities.uid) }
        #expect(deleting.isEmpty)
    }

    @Test func deleteAsksFirstThenRemovesTheEntries() {
        let store = PreviewFinanceStore.sample()
        let uid = expenses(store)[0].uid
        var deleting: [Entry] = []
        let binding = Binding(get: { deleting }, set: { deleting = $0 })

        EntryActions.perform(.delete, on: [uid], finance: store, model: AppModel(), deleting: binding)
        #expect(deleting.map(\.uid) == [uid])
        #expect(store.changes.isEmpty)

        store.apply(EntryRules.delete(deleting.map(\.uid), in: store.data))
        #expect(store.data.transactions[uid] == nil)
    }

    @Test func refusedChangeIsHandedBackAndNotApplied() {
        let store = PreviewFinanceStore.sample()
        let before = store.data.categories.count
        #expect(store.apply(CategoryRules.add(name: "Food", kind: .expense, colorToken: "Mint", in: store.data)) == .nameTaken)
        #expect(store.changes.isEmpty)
        #expect(store.data.categories.count == before)
    }

    @Test func fullNumberIsSealedAndRevealed() async throws {
        let store = PreviewFinanceStore()
        let key = try await store.dataKey()
        store.apply(AccountRules.add(AccountDraft(kind: .creditCard, name: "Card", fullNumber: "4111111111111111"), in: store.data, key: key))
        let card = try #require(store.data.cards.first)
        #expect(card.hasSecret)
        #expect(try await store.revealNumber(of: card.uid) == "4111111111111111")
    }

    @Test func eraseAllKeepsBuiltInCategories() async throws {
        let store = PreviewFinanceStore.sample()
        try await store.eraseAll()
        #expect(store.data.accounts.isEmpty)
        #expect(store.data.transactions.isEmpty)
        #expect(store.data.categories.count == BuiltInCategories.all.count)
    }
}
