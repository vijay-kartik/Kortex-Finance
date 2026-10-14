import Testing
@testable import KortexFinance
@testable import KortexKit

/// Add-or-edit sheets: a record deleted elsewhere while its sheet is open never turns it into Add.
@MainActor
struct SheetRecordTests {
    private func isNew<R>(_ record: SheetRecord<R>) -> Bool { if case .new = record { true } else { false } }
    private func isGone<R>(_ record: SheetRecord<R>) -> Bool { if case .gone = record { true } else { false } }
    private func editing<R>(_ record: SheetRecord<R>) -> R? { if case .editing(let r) = record { r } else { nil } }

    @Test func noUidIsAnAddSheet() {
        let store = PreviewFinanceStore.sample()
        #expect(isNew(SheetRecord(nil, in: store.data.accounts)))
        #expect(isNew(SheetRecord(nil, in: store.data.recurring)))
        #expect(isNew(SheetRecord(nil, in: store.data.categories)))
    }

    @Test func deletedAccountIsGone() throws {
        let store = PreviewFinanceStore.sample()
        let uid = try #require(store.data.accounts.keys.first)
        #expect(editing(SheetRecord(uid, in: store.data.accounts))?.uid == uid)

        store.apply(AccountRules.delete(uid, in: store.data))
        #expect(isGone(SheetRecord(uid, in: store.data.accounts)))
    }

    @Test func deletedRecurringPaymentIsGone() throws {
        let store = PreviewFinanceStore.sample()
        let account = try #require(store.data.accounts.keys.first)
        store.apply(RecurringRules.save(nil, RecurringDraft(name: "Netflix", kind: .subscription, amountMinor: 64_900, frequency: .monthly,
                                                            nextDueOn: LocalDay.today(), accountUid: account), in: store.data))
        let uid = try #require(store.data.recurring.keys.first)
        #expect(editing(SheetRecord(uid, in: store.data.recurring))?.uid == uid)

        store.apply(RecurringRules.delete(uid, in: store.data))
        #expect(isGone(SheetRecord(uid, in: store.data.recurring)))
    }

    @Test func deletedCategoryIsGone() throws {
        let store = PreviewFinanceStore.sample()
        store.apply(CategoryRules.add(name: "Pets", kind: .expense, colorToken: "Mint", in: store.data))
        let uid = try #require(store.data.categories.values.first { $0.name == "Pets" }?.uid)
        #expect(editing(SheetRecord(uid, in: store.data.categories))?.uid == uid)

        store.apply(CategoryRules.delete(uid, moveTo: nil, in: store.data))
        #expect(isGone(SheetRecord(uid, in: store.data.categories)))
    }
}
