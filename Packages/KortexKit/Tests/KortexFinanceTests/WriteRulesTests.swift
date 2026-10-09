import Foundation
import Testing
@testable import KortexFinance

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDay { LocalDay(year: y, month: m, day: d)! }

/// 2026-09-29 15:00 IST.
private let clock = FinanceClock(nowMillis: 1_790_674_200_000, zone: TimeZone(identifier: "Asia/Kolkata")!)

private func account(_ uid: String, _ kind: AccountKind) -> Account {
    Account(uid: uid, kind: kind, name: uid, institution: nil, last4: nil, hasSecret: false, bankType: nil, ifsc: nil,
            linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
            dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
}

private func sample() -> FinanceData {
    var data = FinanceData()
    data.apply([RemoteRow.live(account("bank", .bank)), .live(account("card", .creditCard))])
    data.apply([RemoteRow.live(Recurring(uid: "netflix", name: "Netflix", kind: .subscription, amountMinor: 64_900, currency: "INR",
                                         frequency: .monthly, interval: 1, anchorDay: 3, nextDueOn: day(2026, 10, 3), accountUid: "card",
                                         categoryUid: nil, remindDaysBefore: 2, autoMarkPaid: false, paused: false,
                                         createdAtMillis: 0, updatedAtMillis: 0))])
    return data
}

private func writes(_ r: Result<Change, FinanceError>) -> [RecordWrite] {
    (try? r.get().writes) ?? []
}

struct FinanceIdsTests {
    /// Expected values computed independently (Python hashlib), as Kotlin's FinanceIds makes them.
    @Test func idsMatchAndroid() {
        #expect(FinanceIds.recurringOccurrence("netflix", dueOn: day(2026, 10, 3)) == "rec_380a5096301d35a0715af716cf7f57ec")
        #expect(FinanceIds.merchant("  Whole   Foods MARKET ") == "mer_92e16175eaae2c954e5d9d9589b8dce7")
        #expect(FinanceIds.statement(cardUid: "card", statementOn: day(2026, 9, 25)) == "stmt_202a4a89a7a742a2ef8bd157e4e31af9")
        #expect(FinanceIds.smsTransaction(sender: " vm-hdfcbk ", body: "Rs.42.50 spent\n") == "sms_885f0c68fc40a1570325556b06b2fcee")
        #expect(FinanceIds.random().allSatisfy { !$0.isUppercase })
    }

    @Test func clockDatesLikeAndroid() {
        #expect(clock.today == day(2026, 9, 29))
        #expect(clock.millisOn(day(2026, 9, 29)) == clock.nowMillis, "today is now")
        #expect(clock.dayOf(clock.millisOn(day(2026, 9, 20))) == day(2026, 9, 20), "other days are noon")
    }
}

struct WriteRulesTests {
    @Test func addingAnExpenseLearnsTheMerchant() {
        var data = sample()
        let result = EntryRules.add(TransactionDraft(type: .expense, amountMinor: 4_250, accountUid: "card", categoryUid: "food",
                                                     merchant: "  Whole Foods Market "), in: data, clock: clock)
        guard case .success(let change) = result, case .transaction(let tx) = change.writes[0], case .merchant(let m) = change.writes[1] else {
            Issue.record("expected an entry and a merchant"); return
        }
        #expect(tx.merchant == "Whole Foods Market")
        #expect(tx.payeeKey == "whole foods market")
        #expect(tx.occurredOn == day(2026, 9, 29))
        #expect(m.uid == FinanceIds.merchant("whole foods market"))
        #expect(m.categoryUid == "food")
        // The next entry for the same payee gets that category suggested.
        data.apply([RemoteRow.live(m)])
        #expect(EntryRules.rememberedCategory(for: "WHOLE FOODS MARKET", in: data) == "food")
    }

    @Test func refusesWhatAndroidRefuses() {
        let data = sample()
        #expect(EntryRules.add(TransactionDraft(type: .expense, amountMinor: 0, accountUid: "bank"), in: data, clock: clock).failure == .invalidAmount)
        #expect(EntryRules.add(TransactionDraft(type: .income, amountMinor: 100, accountUid: "card"), in: data, clock: clock).failure == .refundNotSupported)
        #expect(EntryRules.add(TransactionDraft(type: .income, amountMinor: 100, accountUid: "bank", categoryUid: "food"), in: data, clock: clock).failure == .wrongCategoryKind)
        #expect(EntryRules.add(TransactionDraft(type: .cardPayment, amountMinor: 100, accountUid: "card", toAccountUid: "bank"), in: data, clock: clock).failure == .invalidTarget)
        #expect(EntryRules.add(TransactionDraft(type: .expense, amountMinor: 100, accountUid: "gone"), in: data, clock: clock).failure == .unknownAccount)
    }

    @Test func markPaidRecordsTheOccurrenceOnceAndMovesTheDueDate() {
        var data = sample()
        let first = writes(RecurringRules.markPaid("netflix", dueOn: day(2026, 10, 3), in: data, clock: clock))
        guard case .recurring(let moved) = first[0], case .transaction(let tx) = first[1] else { Issue.record("expected both"); return }
        #expect(moved.nextDueOn == day(2026, 11, 3))
        #expect(tx.uid == FinanceIds.recurringOccurrence("netflix", dueOn: day(2026, 10, 3)))
        #expect(tx.source == .recurring && tx.recurringUid == "netflix" && tx.dueOn == day(2026, 10, 3))
        // Paid already (here or on the phone): no second entry, just the date.
        data.apply([RemoteRow.live(tx)])
        let again = writes(RecurringRules.markPaid("netflix", dueOn: day(2026, 10, 3), in: data, clock: clock))
        #expect(again.count == 1)
        if case .recurring(let r) = again.first { #expect(r.nextDueOn == day(2026, 11, 3)) }
    }

    @Test func skipAndAnchors() {
        let data = sample()
        guard case .recurring(let r) = writes(RecurringRules.skip("netflix", dueOn: day(2026, 10, 3), in: data, clock: clock)).first else {
            Issue.record("expected a recurring write"); return
        }
        #expect(r.nextDueOn == day(2026, 11, 3))
        let saved = writes(RecurringRules.save(nil, RecurringDraft(name: "Rent", kind: .fixed, amountMinor: 2_500_000, frequency: .monthly,
                                                                   nextDueOn: day(2026, 10, 31), accountUid: "bank"), in: data, clock: clock))
        guard case .recurring(let rent) = saved.first else { Issue.record("expected rent"); return }
        #expect(rent.anchorDay == 31)
    }

    @Test func changingAnEntrysCategoryFindsThePayeesOtherEntriesAndRefilesThem() throws {
        var data = sample()
        data.apply([RemoteRow.live(Category(uid: "c1", name: "Shopping", kind: .expense, colorToken: "Lilac", builtIn: false, sortOrder: 3))])
        func add(_ merchant: String?, _ category: String?, type: TransactionType = .expense, at: Int64) throws -> Transaction {
            let change = try EntryRules.add(TransactionDraft(type: type, amountMinor: 500, accountUid: "bank", categoryUid: category,
                                                             merchant: merchant, occurredAtMillis: clock.nowMillis - at), in: data, clock: clock).get()
            guard case .transaction(let tx) = change.writes[0] else { throw CancellationError() }
            data.apply([RemoteRow.live(tx)])
            return tx
        }
        let edited = try add("Swiggy", "food", at: 1)
        let older = try add("SWIGGY ", "food", at: 3)
        let uncategorised = try add("swiggy", nil, at: 2)
        _ = try add("Swiggy", "c1", at: 4)                       // already where it's going
        _ = try add("Swiggy", nil, type: .income, at: 5)         // a refund is income: another kind of category
        _ = try add("Zomato", "food", at: 6)

        var draft = TransactionDraft(type: .expense, amountMinor: 500, accountUid: "bank", categoryUid: "c1", merchant: "Swiggy")
        let others = EntryRules.samePayee(as: edited.uid, draft, in: data)
        #expect(others.map(\.uid) == [uncategorised.uid, older.uid], "same payee and type, not yet in Shopping, newest first")

        let writes = try EntryRules.edit(edited.uid, draft, alsoRefiling: others.map(\.uid), in: data, clock: clock).get().writes
        let entries = writes.compactMap { if case .transaction(let t) = $0 { t } else { nil } }
        #expect(Set(entries.map(\.uid)) == [edited.uid, older.uid, uncategorised.uid])
        #expect(entries.allSatisfy { $0.categoryUid == "c1" })
        #expect(writes.contains { if case .merchant(let m) = $0 { m.categoryUid == "c1" } else { false } }, "new Swiggy entries are suggested Shopping")

        // Only this one: the others stay where they are.
        #expect(try EntryRules.edit(edited.uid, draft, alsoRefiling: [], in: data, clock: clock).get().writes
            .filter { if case .transaction = $0 { true } else { false } }.count == 1)
        // Renaming the payee looks for the new name's entries.
        draft.merchant = "Zomato"
        #expect(EntryRules.samePayee(as: edited.uid, draft, in: data).count == 1)
    }

    @Test func settingACategoryOnSeveralEntriesFilesOnlyTheOnesItFits() throws {
        var data = sample()
        data.apply([RemoteRow.live(Category(uid: "c1", name: "Shopping", kind: .expense, colorToken: "Lilac", builtIn: false, sortOrder: 3))])
        let salaryKind = try #require(data.categories.values.first { $0.kind == .income })
        func add(_ draft: TransactionDraft) throws -> String {
            let change = try EntryRules.add(draft, in: data, clock: clock).get()
            guard case .transaction(let tx) = change.writes[0] else { throw CancellationError() }
            data.apply([RemoteRow.live(tx)])
            return tx.uid
        }
        let swiggy = try add(TransactionDraft(type: .expense, amountMinor: 500, accountUid: "bank", categoryUid: "food", merchant: "Swiggy"))
        let blank = try add(TransactionDraft(type: .expense, amountMinor: 700, accountUid: "bank"))
        let already = try add(TransactionDraft(type: .expense, amountMinor: 900, accountUid: "bank", categoryUid: "c1"))
        let salary = try add(TransactionDraft(type: .income, amountMinor: 9_000, accountUid: "bank", categoryUid: salaryKind.uid))
        let writes = try EntryRules.setCategory([swiggy, blank, already, salary], to: "c1", in: data, clock: clock).get().writes
        let entries = writes.compactMap { if case .transaction(let t) = $0 { t } else { nil } }
        #expect(Set(entries.map(\.uid)) == [swiggy, blank], "income keeps its kind of category; one already there isn't rewritten")
        #expect(entries.allSatisfy { $0.categoryUid == "c1" })
        #expect(writes.contains { if case .merchant(let m) = $0 { m.payeeKey == "swiggy" && m.categoryUid == "c1" } else { false } })

        let cleared = try EntryRules.setCategory([swiggy, salary, already], to: nil, in: data, clock: clock).get().writes
        #expect(cleared.count == 3 && cleared.allSatisfy { if case .transaction(let t) = $0 { t.categoryUid == nil } else { false } },
                "Remove Category clears expenses and income alike, and teaches nothing")
        #expect(EntryRules.setCategory([swiggy], to: "gone", in: data, clock: clock).failure == .notFound)
    }

    @Test func deletingSeveralEntriesLeavesOpeningBalances() throws {
        var data = sample()
        func entry(_ uid: String, _ type: TransactionType) -> Transaction {
            Transaction(uid: uid, type: type, amountMinor: 100, currency: "INR", occurredAtMillis: 0, occurredOn: day(2026, 9, 1),
                        accountUid: "bank", toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual,
                        sourceRef: nil, recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
        }
        data.apply([RemoteRow.live(entry("open", .opening)), .live(entry("spend", .expense))])
        let writes = try EntryRules.delete(["open", "spend", "missing"], in: data, clock: clock).get().writes
        #expect(writes.count == 1)
        if case .delete(let col, let uid, _) = writes.first { #expect(col == .transactions && uid == "spend") }
        #expect(EntryRules.delete(["open"], in: data, clock: clock).failure == .notFound)
    }

    @Test func markingMoneyOutAsATransferTakesTheOtherAccountsRecordAlong() throws {
        var data = sample()
        data.apply([RemoteRow.live(account("savings", .bank))])
        func entry(_ uid: String, _ type: TransactionType, _ amount: Int64, _ account: String, _ d: Int, recurring: String? = nil) -> Transaction {
            Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: clock.millisOn(day(2026, 9, d)),
                        occurredOn: day(2026, 9, d), accountUid: account, toAccountUid: nil, categoryUid: type == .expense ? "food" : nil,
                        merchant: "IMPS SELF", payeeKey: "imps self", note: nil, source: .statement, sourceRef: nil, recurringUid: recurring,
                        dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
        }
        data.apply([
            entry("out", .expense, 2_000_000, "bank", 4),
            entry("in", .income, 2_000_000, "savings", 5),            // the other side, a day later
            entry("late", .income, 2_000_000, "savings", 20),         // too far apart
            entry("less", .income, 500_000, "savings", 4),            // another amount
            entry("elsewhere", .income, 2_000_000, "bank", 4),        // not in the other account
        ].map { RemoteRow.live($0) })

        let draft = TransactionDraft(type: .transfer, amountMinor: 2_000_000, accountUid: "bank", toAccountUid: "savings",
                                     occurredAtMillis: clock.millisOn(day(2026, 9, 4)))
        #expect(EntryRules.transferOtherSide(of: "out", draft, in: data, clock: clock)?.uid == "in")
        let writes = try EntryRules.editMerging("out", draft, in: data, clock: clock).get().writes
        #expect(writes.count == 2)
        guard case .transaction(let t) = writes[0], case .delete(let col, let gone, _) = writes[1] else { Issue.record("\(writes)"); return }
        #expect(t.uid == "out" && t.type == .transfer && t.accountUid == "bank" && t.toAccountUid == "savings")
        #expect(t.categoryUid == nil && t.merchant == nil)
        #expect(col == .transactions && gone == "in")

        // From the other end: the money in, marked as a transfer from the bank, finds the money out.
        let back = TransactionDraft(type: .transfer, amountMinor: 2_000_000, accountUid: "bank", toAccountUid: "savings",
                                    occurredAtMillis: clock.millisOn(day(2026, 9, 5)))
        #expect(EntryRules.transferOtherSide(of: "in", back, in: data, clock: clock)?.uid == "out")
        // A transfer that leaves the entry's own account off both ends has no other side to find.
        let away = TransactionDraft(type: .transfer, amountMinor: 2_000_000, accountUid: "cash", toAccountUid: "savings")
        #expect(EntryRules.transferOtherSide(of: "out", away, in: data, clock: clock) == nil)
        // Nothing to take along: just the edit.
        data.apply([RemoteRow<Transaction>.deleted(uid: "in")])
        #expect(try EntryRules.editMerging("out", draft, in: data, clock: clock).get().writes.count == 1)
        // A recurring payment's debit isn't someone's other side.
        data.apply([RemoteRow.live(entry("emi", .income, 2_000_000, "savings", 4, recurring: "loan"))])
        #expect(EntryRules.transferOtherSide(of: "out", draft, in: data, clock: clock) == nil)
    }

    @Test func aCardBillPaymentIsEditableAndMoneyOutCanBecomeOne() throws {
        var data = sample()
        data.apply([RemoteRow.live(account("other", .creditCard))])
        func bill(_ uid: String, card: String, _ d: Int) -> CardStatement {
            CardStatement(uid: uid, cardUid: card, periodStart: day(2026, 8, d), statementOn: day(2026, 9, d), dueOn: day(2026, 9, d + 3),
                          totalDueMinor: 500_000, minDueMinor: 0, source: .manual, createdAtMillis: 0, updatedAtMillis: 0)
        }
        data.apply([RemoteRow.live(bill("aug", card: "card", 1)), .live(bill("sep", card: "card", 20)), .live(bill("theirs", card: "other", 1))])
        func entry(_ uid: String, _ type: TransactionType, _ account: String, to: String? = nil, bill: String? = nil) -> Transaction {
            Transaction(uid: uid, type: type, amountMinor: 500_000, currency: "INR", occurredAtMillis: clock.millisOn(day(2026, 9, 25)),
                        occurredOn: day(2026, 9, 25), accountUid: account, toAccountUid: to, categoryUid: type == .expense ? "food" : nil,
                        merchant: type == .expense ? "CC PAYMENT" : nil, payeeKey: nil, note: nil, source: .statement, sourceRef: nil,
                        recurringUid: nil, dueOn: nil, statementUid: bill, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
        }
        data.apply([RemoteRow.live(entry("paid", .cardPayment, "bank", to: "card", bill: "aug"))])
        func payment(from: String = "bank", to: String = "card", bill: String?) -> TransactionDraft {
            TransactionDraft(type: .cardPayment, amountMinor: 500_000, accountUid: from, toAccountUid: to,
                             occurredAtMillis: clock.millisOn(day(2026, 9, 25)), statementUid: bill)
        }
        func saved(_ r: Result<Change, FinanceError>) throws -> Transaction {
            guard case .transaction(let t) = try r.get().writes[0] else { throw CancellationError() }
            return t
        }

        // Paired with the wrong bill, then the right one; a bill of another card never sticks.
        #expect(try saved(EntryRules.editMerging("paid", payment(bill: "sep"), in: data, clock: clock)).statementUid == "sep")
        #expect(try saved(EntryRules.editMerging("paid", payment(to: "other", bill: "aug"), in: data, clock: clock)).statementUid == nil)
        // Paid from an account Kortex doesn't have yet.
        #expect(try saved(EntryRules.editMerging("paid", payment(from: FinanceIds.unknownAccount, bill: "sep"), in: data, clock: clock)).accountUid
                == FinanceIds.unknownAccount)
        // A card payment that was money out after all: back to an expense, with a category and no card.
        let spent = try saved(EntryRules.edit("paid", TransactionDraft(type: .expense, amountMinor: 500_000, accountUid: "bank", categoryUid: "food",
                                                                        merchant: "Swiggy"), in: data, clock: clock))
        #expect(spent.type == .expense && spent.toAccountUid == nil && spent.statementUid == nil && spent.categoryUid == "food")

        // Money out that was the card's bill: it takes over the card's payment from an unknown account, and its bill.
        data.apply([RemoteRow.live(entry("debit", .expense, "bank")),
                    .live(entry("unknown", .cardPayment, FinanceIds.unknownAccount, to: "card", bill: "sep"))])
        let writes = try EntryRules.editMerging("debit", payment(bill: nil), in: data, clock: clock).get().writes
        guard case .transaction(let t) = writes[0], case .delete(_, let gone, _) = writes[1] else { Issue.record("\(writes)"); return }
        #expect(t.uid == "debit" && t.type == .cardPayment && t.categoryUid == nil && t.merchant == nil && t.statementUid == "sep")
        #expect(gone == "unknown")
    }

    @Test func whatDeletedAccountsLeaveBehindGoesWithoutMovingYourBalances() throws {
        var data = sample()   // "bank" and "card" stay
        data.apply([RemoteRow.live(account("old", .bank)), .live(account("oldCard", .creditCard))])
        func entry(_ uid: String, _ type: TransactionType, _ from: String, to: String? = nil, bill: String? = nil) -> Transaction {
            Transaction(uid: uid, type: type, amountMinor: 1_000, currency: "INR", occurredAtMillis: 0, occurredOn: day(2026, 9, 1),
                        accountUid: from, toAccountUid: to, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual,
                        sourceRef: nil, recurringUid: nil, dueOn: nil, statementUid: bill, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
        }
        data.apply([
            entry("open", .opening, "bank"),
            entry("oldOpen", .opening, "old"),
            entry("oldSpend", .expense, "old"),
            entry("toBank", .transfer, "old", to: "bank"),                       // part of bank's balance
            entry("oldPaysCard", .cardPayment, "old", to: "card"),               // part of card's balance
            entry("bankPaysOld", .cardPayment, "bank", to: "oldCard", bill: "oldBill"),
            entry("oldCardSpend", .expense, "oldCard"),
            entry("oldCardRefund", .cardPayment, FinanceIds.cardCredit, to: "oldCard"),
            entry("between", .transfer, "old", to: "oldCard"),
        ].map { RemoteRow.live($0) })
        data.apply([RemoteRow.live(CardStatement(uid: "oldBill", cardUid: "oldCard", periodStart: day(2026, 8, 1), statementOn: day(2026, 9, 1),
                                                 dueOn: day(2026, 9, 20), totalDueMinor: 1_000, minDueMinor: 0, source: .manual,
                                                 createdAtMillis: 0, updatedAtMillis: 0))])
        let balances = { (d: FinanceData) in [d.balanceMinor(of: d.accounts["bank"]!), d.balanceMinor(of: d.accounts["card"]!)] }
        let before = balances(data)

        // Deleting one account with its entries.
        let found = AccountRules.leftovers(of: ["old"], in: data)
        #expect(Set(found.entries.map(\.uid)) == ["oldOpen", "oldSpend"], "a transfer to another deleted-to-be account isn't gone yet")
        #expect(Set(found.relabeled.map(\.uid)) == ["toBank", "oldPaysCard", "between"])

        // Both deleted earlier, as on the phone: tidying up.
        data.apply([RemoteRow<Account>.deleted(uid: "old"), .deleted(uid: "oldCard")])
        #expect(AccountRules.deletedAccountUids(in: data) == ["old", "oldCard"])
        let writes = try AccountRules.removeLeftovers(in: data, clock: clock).get().writes
        var after = data
        var removed: Set<String> = []
        for w in writes {
            switch w {
            case .transaction(let t): after.apply([RemoteRow.live(t)])
            case .delete(.transactions, let uid, _): removed.insert(uid); after.apply([RemoteRow<Transaction>.deleted(uid: uid)])
            case .delete(.statements, let uid, _): removed.insert(uid); after.apply([RemoteRow<CardStatement>.deleted(uid: uid)])
            default: break
            }
        }
        #expect(removed == ["oldOpen", "oldSpend", "oldCardSpend", "oldCardRefund", "between", "oldBill"])
        #expect(after.transactions["toBank"]?.accountUid == FinanceIds.unknownAccount && after.transactions["toBank"]?.toAccountUid == "bank")
        #expect(after.transactions["oldPaysCard"]?.accountUid == FinanceIds.unknownAccount)
        #expect(after.transactions["bankPaysOld"]?.toAccountUid == FinanceIds.unknownAccount && after.transactions["bankPaysOld"]?.statementUid == nil)
        #expect(balances(after) == before, "what you still have doesn't move")
        #expect(AccountRules.deletedAccountUids(in: after).isEmpty)
        #expect(AccountRules.removeLeftovers(in: after, clock: clock).failure == .notFound)
    }

    @Test func anAccountsOpeningBalanceCanBeChanged() throws {
        var data = sample()
        func entry(_ uid: String, _ type: TransactionType, _ amount: Int64, _ account: String, _ d: Int) -> Transaction {
            Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: clock.millisOn(day(2026, 9, d)),
                        occurredOn: day(2026, 9, d), accountUid: account, toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil,
                        note: nil, source: .manual, sourceRef: nil, recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil,
                        createdAtMillis: 0, updatedAtMillis: 0)
        }
        data.apply([entry("open", .opening, 10_000, "card", 1), entry("spend", .expense, 2_000, "card", 5),
                    entry("bankSpend", .expense, 500, "bank", 3)].map { RemoteRow.live($0) })
        func applied(_ r: Result<Change, FinanceError>) throws -> FinanceData {
            var d = data
            for w in try r.get().writes {
                switch w {
                case .transaction(let t): d.apply([RemoteRow.live(t)])
                case .delete(.transactions, let uid, _): d.apply([RemoteRow<Transaction>.deleted(uid: uid)])
                case .account(let a): d.apply([RemoteRow.live(a)])
                default: break
                }
            }
            return d
        }

        // The card owed more at the start than was entered: its opening entry changes, not a new one.
        let raised = try applied(AccountRules.update("card", AccountDraft(data.accounts["card"]!), opening: 15_000, in: data, clock: clock))
        #expect(raised.transactions["open"]?.amountMinor == 15_000)
        #expect(raised.balanceMinor(of: raised.accounts["card"]!) == 17_000)
        #expect(try AccountRules.setOpening("card", to: 10_000, in: data, clock: clock).get().writes.isEmpty, "unchanged writes nothing")
        #expect(try applied(AccountRules.setOpening("card", to: 0, in: data, clock: clock)).transactions["open"] == nil, "0 removes it")
        #expect(AccountRules.update("card", AccountDraft(data.accounts["card"]!), opening: -1, in: data, clock: clock).failure == .invalidAmount)
        #expect(try AccountRules.update("card", AccountDraft(data.accounts["card"]!), in: data, clock: clock).get().writes.count == 1,
                "no opening given leaves it")

        // An account with none gets one on the day of its first entry, so its history never starts below it.
        let opened = try applied(AccountRules.setOpening("bank", to: 50_000, in: data, clock: clock))
        let added = try #require(opened.transactions.values.first { $0.type == .opening && $0.accountUid == "bank" })
        #expect(added.amountMinor == 50_000 && added.occurredOn == day(2026, 9, 3))
        #expect(opened.balanceMinor(of: opened.accounts["bank"]!) == 49_500)
    }

    @Test func deletingAnAccountWithItsEntries() throws {
        var data = sample()
        data.apply([RemoteRow.live(account("old", .bank))])
        let spend = Transaction(uid: "s", type: .expense, amountMinor: 100, currency: "INR", occurredAtMillis: 0, occurredOn: day(2026, 9, 1),
                                accountUid: "old", toAccountUid: nil, categoryUid: nil, merchant: nil, payeeKey: nil, note: nil, source: .manual,
                                sourceRef: nil, recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: 0, updatedAtMillis: 0)
        data.apply([RemoteRow.live(spend)])
        #expect(try AccountRules.delete("old", in: data, clock: clock).get().writes.count == 1, "kept by default")
        let writes = try AccountRules.delete("old", withEntries: true, in: data, clock: clock).get().writes
        #expect(writes.count == 2)
        if case .delete(let col, let uid, _) = writes[1] { #expect(col == .transactions && uid == "s") }
    }

    @Test func deletingACategoryMovesItsEntries() {
        var data = sample()
        let custom = Category(uid: "c1", name: "Shopping", kind: .expense, colorToken: "Lilac", builtIn: false, sortOrder: 3)
        data.apply([RemoteRow.live(custom)])
        guard case .transaction(let tx) = writes(EntryRules.add(TransactionDraft(type: .expense, amountMinor: 900, accountUid: "bank", categoryUid: "c1"),
                                                                in: data, clock: clock)).first else { Issue.record("no entry"); return }
        data.apply([RemoteRow.live(tx)])
        let change = writes(CategoryRules.delete("c1", moveTo: "food", in: data, clock: clock))
        #expect(change.count == 3)
        if case .transaction(let moved) = change[0] { #expect(moved.categoryUid == "food") }
        let deleted = change.compactMap { write -> String? in
            guard case .delete(let collection, let uid, let at) = write, at == clock.nowMillis else { return nil }
            return "\(collection.rawValue)/\(uid)"
        }
        #expect(deleted == ["finBudgets/c1", "finCategories/c1"], "its budget goes with it, as on the phone")
        #expect(CategoryRules.delete("food", moveTo: nil, in: data, clock: clock).failure == .builtIn)
        #expect(CategoryRules.add(name: " food ", kind: .expense, colorToken: "Mint", in: data, clock: clock).failure == .nameTaken)
    }

    @Test func addingAnAccountWritesItsOpeningEntry() {
        let data = sample()
        let change = writes(AccountRules.add(AccountDraft(kind: .bank, name: "HDFC", last4: "4471", openingMinor: 1_245_000), in: data, clock: clock))
        #expect(change.count == 2)
        if case .transaction(let opening) = change[1] { #expect(opening.type == .opening && opening.amountMinor == 1_245_000) }
        #expect(AccountRules.add(AccountDraft(kind: .bank, name: "X", last4: "12a4"), in: data, clock: clock).failure == .invalidLast4)
    }

    @Test func documentsCarryEveryFieldLikeAndroid() {
        let data = sample()
        guard case .transaction(let tx) = writes(EntryRules.add(TransactionDraft(type: .expense, amountMinor: 4_250, accountUid: "bank"),
                                                                in: data, clock: clock)).first else { Issue.record("no entry"); return }
        let doc = FinanceDocWriter.document(.transaction(tx), serverTime: "SERVER")
        #expect(doc.collection == .transactions)
        let expected: Set<String> = ["type", "amountMinor", "currency", "occurredAt", "occurredOn", "accountUid", "toAccountUid",
                                     "categoryUid", "merchant", "payeeKey", "note", "source", "sourceRef", "recurringUid", "dueOn",
                                     "statementUid", "receipt", "createdAt", "updatedAt", "serverUpdatedAt", "deleted"]
        #expect(Set(doc.fields.keys) == expected)
        #expect(doc.fields["merchant"] is NSNull, "nulls are written so a merge clears them")
        #expect(doc.fields["occurredOn"] as? String == "2026-09-29")
        // A document we write reads back as the same record.
        if case .live(let read) = FinanceDocs.transaction(uid: tx.uid, doc.fields) { #expect(read == tx) } else { Issue.record("didn't read back") }
        let delete = FinanceDocWriter.document(.delete(.transactions, uid: "t", atMillis: 5), serverTime: "SERVER")
        #expect(delete.fields["deleted"] as? Bool == true && delete.fields.count == 3)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}

struct ResetRulesTests {
    @Test func marksEveryDocumentDeletedButBuiltInCategories() {
        let live: [(collection: FinCollection, uid: String)] = [
            (.accounts, "bank"), (.secrets, "bank"), (.transactions, "t1"), (.categories, "food"), (.categories, "pets"), (.merchants, "m1"),
            (.budgets, "food"), (.budgets, "pets"),
        ]
        let deleted = ResetRules.eraseAll(live, clock: clock).writes.compactMap { write -> String? in
            guard case .delete(let collection, let uid, let at) = write, at == clock.nowMillis else { return nil }
            return "\(collection.rawValue)/\(uid)"
        }
        #expect(deleted == ["finAccounts/bank", "finSecrets/bank", "finTransactions/t1", "finCategories/pets", "finMerchants/m1",
                           "finBudgets/food", "finBudgets/pets"], "built-in categories stay, their budgets don't")
    }
}

struct SecretsTests {
    private let key = DataKey(userUid: "u1", bytes: Data(0..<32), version: 1)!

    /// Sealed by Node's AES-256-GCM in Tink's AesGcmJce layout (nonce, cipher text, tag), as the phone seals.
    @Test func opensWhatThePhoneSeals() {
        let sealed = SealedSecret(cipherText: "ZGVmZ2hpamtsbW5vfCrvV0jYZ68PU27Z61RbzFJtDlA5di9VIaNl0opwkeQ=", keyVersion: 1)
        #expect(SecretBox.open(sealed, accountUid: "acc_1", key: key) == "4111111111111111")
        // Bound to its account and its key version.
        #expect(SecretBox.open(sealed, accountUid: "acc_2", key: key) == nil)
        #expect(SecretBox.open(SealedSecret(cipherText: sealed.cipherText, keyVersion: 2), accountUid: "acc_1", key: key) == nil)
    }

    @Test func sealsWhatItOpens() throws {
        let sealed = try #require(SecretBox.seal("50100012345678", accountUid: "acc_1", key: key))
        #expect(Data(base64Encoded: sealed.cipherText)?.count == 12 + 14 + 16)
        #expect(SecretBox.open(sealed, accountUid: "acc_1", key: key) == "50100012345678")
    }

    @Test func numbersAreEightToNineteenDigits() throws {
        #expect(try AccountNumbers.clean("4111 1111-1111 1111").get() == "4111111111111111")
        #expect(try AccountNumbers.clean("  ").get() == nil)
        #expect(throws: FinanceError.invalidNumber) { try AccountNumbers.clean("1234567").get() }
        #expect(throws: FinanceError.invalidNumber) { try AccountNumbers.clean("4111x11111111111").get() }
        #expect(AccountNumbers.grouped("50100012345678") == "5010 0012 3456 78")
    }

    @Test func addingWithAFullNumberSealsItAndFlagsTheAccount() throws {
        var draft = AccountDraft(kind: .creditCard, name: "Regalia", fullNumber: "4111 1111 1111 1111")
        #expect(throws: FinanceError.noFinanceKey) { try AccountRules.add(draft, in: FinanceData(), clock: clock).get() }
        let writes = try AccountRules.add(draft, in: FinanceData(), key: key, clock: clock).get().writes
        guard case .account(let a) = writes[0], case .secret(let uid, let sealed, _) = writes[1] else { Issue.record("\(writes)"); return }
        #expect(a.hasSecret && a.last4 == "1111" && uid == a.uid)
        #expect(SecretBox.open(sealed, accountUid: a.uid, key: key) == "4111111111111111")
        let doc = FinanceDocWriter.document(writes[1], serverTime: "now")
        #expect(doc.collection == .secrets && doc.fields["keyVersion"] as? Int == 1 && doc.fields["deleted"] as? Bool == false)

        draft.last4 = "2222"
        #expect(throws: FinanceError.invalidNumber) { try AccountRules.add(draft, in: FinanceData(), key: key, clock: clock).get() }
    }

    @Test func editingKeepsTheNumberUnlessANewOneIsGiven() throws {
        let data = sample()
        var draft = AccountDraft(data.accounts["card"]!)
        #expect(try AccountRules.update("card", draft, in: data, clock: clock).get().writes.count == 1)
        draft.fullNumber = "5555444433332222"
        let writes = try AccountRules.update("card", draft, in: data, key: key, clock: clock).get().writes
        guard case .account(let a) = writes[0], case .secret = writes[1] else { Issue.record("\(writes)"); return }
        #expect(a.hasSecret && a.last4 == "2222")
    }
}
