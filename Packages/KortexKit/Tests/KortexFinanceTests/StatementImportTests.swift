import Testing
@testable import KortexFinance

/// Made-up statements in the shape the model returns.
struct StatementImportTests {
    private let today = LocalDay(year: 2026, month: 10, day: 6)!
    private let clock = FinanceClock(nowMillis: 1_791_270_000_000, zone: .current)

    private func tx(_ date: String, _ desc: String, _ amount: Double, _ dir: ExtractedTransaction.Direction,
                    balance: Double?, merchant: String? = nil, category: String? = nil, recurring: Bool? = nil) -> ExtractedTransaction {
        ExtractedTransaction(date: date, description: desc, merchant: merchant, amount: amount, direction: dir,
                             balanceAfter: balance, balanceAfterIsDebit: nil, reference: nil, categoryId: category, recurring: recurring)
    }

    private func bank(_ txs: [ExtractedTransaction], opening: Double? = 10_000, closing: Double? = nil, number: String = "123-456789-001") -> ExtractedAccount {
        ExtractedAccount(kind: .bank, institution: "Test Bank", productName: "SAVINGS ACCOUNT-RES", numberLast4: number,
                         ifsc: "TEST0000001", holder: "MR TEST PERSON", currency: "INR", periodStart: "2026-09-01", periodEnd: "2026-09-30",
                         statementDate: "2026-09-30", openingBalance: opening, openingBalanceIsDebit: false, closingBalance: closing,
                         closingBalanceIsDebit: false, creditLimit: nil, totalDue: nil, minimumDue: nil, paymentDueDate: nil, transactions: txs)
    }

    @Test func aCleanBankStatementReconciles() {
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "UPI/Swiggy", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy", category: "food"),
            tx("2026-09-05", "NEFT SALARY ACME", 50_000, .credit, balance: 59_749.50, merchant: "Acme", category: "salary"),
        ], closing: 59_749.50), in: FinanceData(), today: today)
        #expect(s.account.kind == .bank && s.account.last4 == "9001")
        #expect(s.account.bankType == .savings)
        #expect(s.openingMinor == 1_000_000)
        #expect(s.rows.map(\.kind) == [.expense, .income])
        #expect(s.rows.allSatisfy { $0.issue == nil })
        #expect(s.rows[0].categoryUid == "food" && s.rows[1].categoryUid == "salary")
        #expect(s.reconciles == true)
    }

    @Test func aWrongDirectionIsCorrectedByTheRunningBalance() {
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "REFUND", 100, .debit, balance: 10_100),
            tx("2026-09-03", "ATM", 500, .debit, balance: 9_000),
        ]), in: FinanceData(), today: today)
        #expect(s.rows[0].kind == .income)
        #expect(s.rows[0].issue?.contains("corrected") == true)
        #expect(s.rows[1].issue?.contains("Check the amount") == true, "100 − 500 ≠ 9,000 either way")
    }

    @Test func openingIsInferredWithoutABroughtForwardLine() {
        let s = StatementImportRules.prepare(bank([tx("2026-09-02", "X", 300, .debit, balance: 700)], opening: nil), in: FinanceData(), today: today)
        #expect(s.openingMinor == 100_000)
    }

    @Test func savingWritesTheAccountOpeningEntriesAndMerchants() throws {
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "UPI/Swiggy", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy", category: "food"),
        ]), in: FinanceData(), today: today)
        let writes = try StatementImportRules.commit(s, in: FinanceData(), clock: clock).get().writes
        guard case .account(let a) = writes[0], case .transaction(let opening) = writes[1], case .transaction(let entry) = writes[2],
              case .merchant(let m) = writes[3] else { Issue.record("unexpected writes \(writes)"); return }
        #expect(a.uid == s.accountUid)
        #expect(opening.type == .opening && opening.amountMinor == 1_000_000 && opening.occurredOn == LocalDay(year: 2026, month: 9, day: 1))
        #expect(entry.type == .expense && entry.source == .statement && entry.occurredOn == LocalDay(year: 2026, month: 9, day: 2))
        #expect(entry.accountUid == a.uid && entry.categoryUid == "food")
        #expect(m.payeeKey == "swiggy")
        // Saving the same review twice writes the same documents, not a second copy.
        let again = try StatementImportRules.commit(s, in: FinanceData(), clock: clock).get().writes
        if case .transaction(let e2) = again[2] { #expect(e2.uid == entry.uid) }
    }

    @Test func aCardStatementBringsItsBillAndItsRefundsAsCredits() throws {
        var data = FinanceData()
        let checking = Account(uid: "bank", kind: .bank, name: "Checking", institution: nil, last4: nil, hasSecret: false, bankType: .savings,
                               ifsc: nil, linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                               dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
        data.apply([RemoteRow.live(checking)])
        let card = ExtractedAccount(kind: .credit_card, institution: "Test Bank", productName: "Platinum Credit Card", numberLast4: "4321",
                                    ifsc: nil, holder: nil, currency: "INR", periodStart: "2026-08-26", periodEnd: "2026-09-25",
                                    statementDate: "2026-09-25", openingBalance: 2_000, openingBalanceIsDebit: true, closingBalance: 1_450,
                                    closingBalanceIsDebit: true, creditLimit: 100_000, totalDue: 1_450, minimumDue: 200, paymentDueDate: "2026-10-15",
                                    transactions: [
                                        tx("2026-08-30", "PAYMENT RECEIVED THANK YOU", 2_000, .credit, balance: 0),
                                        tx("2026-09-02", "AMAZON", 1_500, .debit, balance: 1_500, merchant: "Amazon"),
                                        tx("2026-09-04", "AMAZON REVERSAL", 50, .credit, balance: 1_450),
                                    ])
        let s = StatementImportRules.prepare(card, in: data, today: today)
        #expect(s.account.kind == .creditCard && s.account.statementDay == 25 && s.account.dueDay == 15)
        #expect(s.rows.map(\.kind) == [.cardPayment, .expense, .cardCredit], "a reversal is a refund, not a bill payment")
        #expect(s.rows[0].fromAccountUid == "bank" && s.rows[2].fromAccountUid == nil)
        #expect(s.rows.allSatisfy(\.include) && s.reconciles == true)
        #expect(s.bill?.totalMinor == 145_000)
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        #expect(writes.contains { if case .statement(let b) = $0 { return b.dueOn == LocalDay(year: 2026, month: 10, day: 15) } else { return false } })
        #expect(writes.contains { if case .transaction(let t) = $0 { return t.type == .cardPayment && t.accountUid == "bank" } else { return false } })
        let credit = try #require(writes.compactMap { if case .transaction(let t) = $0, t.isCardCredit { t } else { nil } }.first)
        #expect(credit.amountMinor == 5_000 && credit.toAccountUid == s.accountUid && credit.statementUid == nil)
        #expect(credit.note == "AMAZON REVERSAL" && credit.categoryUid == nil)
        var after = data
        after.apply(writes.compactMap { if case .account(let a) = $0 { RemoteRow.live(a) } else { nil } })
        after.apply(writes.compactMap { if case .transaction(let t) = $0 { RemoteRow.live(t) } else { nil } })
        let txs = Array(after.transactions.values)
        #expect(Balances.balance(of: after.accounts[s.accountUid]!, transactions: txs, accounts: after.accounts) == 145_000, "what the statement says is owed")
        #expect(Spending.spentMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 150_000, "the purchase still counts in full")
    }

    @Test func aBanksDebitIsNeverTakenForACardsRefund() throws {
        let cardImport = StatementImportRules.prepare(cardStatement([tx("2026-09-05", "FLIPKART REFUND", 5_000, .credit, balance: 0)]),
                                                      in: FinanceData(), today: today)
        #expect(cardImport.rows[0].kind == .cardCredit)
        let data = saved(try StatementImportRules.commit(cardImport, in: FinanceData(), clock: clock).get(), onto: FinanceData())
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-05", "NEFT DR 0012345", 5_000, .debit, balance: nil),
            tx("2026-09-05", "CC PAYMENT", 5_000, .debit, balance: nil),
        ]), in: data, today: today)
        #expect(s.rows.allSatisfy { $0.replaces == nil }, "a refund came from the shop, not from a bank")
    }

    // MARK: Recurring

    private func day(_ text: String) -> LocalDay { LocalDay(text)! }

    /// A bank account the phone already has, with a home loan EMI on the 5th that it auto-pays.
    private func withLoan(nextDueOn: String, phonePaid: String? = nil) -> FinanceData {
        var data = FinanceData()
        data.apply([RemoteRow.live(Account(uid: "bank", kind: .bank, name: "Checking", institution: nil, last4: nil, hasSecret: false,
                                           bankType: .savings, ifsc: nil, linkedAccountUid: nil, network: nil, expiry: nil, holder: nil,
                                           creditLimitMinor: nil, statementDay: nil, dueDay: nil, colorToken: nil, archived: false,
                                           createdAtMillis: 0, updatedAtMillis: 0))])
        let loan = Recurring(uid: "loan", name: "Home Loan EMI", kind: .fixed, amountMinor: 2_400_000, currency: "INR", frequency: .monthly,
                             interval: 1, anchorDay: 5, nextDueOn: day(nextDueOn), accountUid: "bank", categoryUid: nil, remindDaysBefore: -1,
                             autoMarkPaid: true, paused: false, createdAtMillis: 0, updatedAtMillis: 0)
        data.apply([RemoteRow.live(loan)])
        if let phonePaid {
            let uid = FinanceIds.recurringOccurrence("loan", dueOn: day(phonePaid))
            data.apply([RemoteRow.live(Transaction(
                uid: uid, type: .expense, amountMinor: 2_400_000, currency: "INR", occurredAtMillis: 0, occurredOn: day(phonePaid),
                accountUid: "bank", toAccountUid: nil, categoryUid: nil, merchant: "Home Loan EMI", payeeKey: "home loan emi", note: nil,
                source: .recurring, sourceRef: nil, recurringUid: "loan", dueOn: day(phonePaid), statementUid: nil, receipt: nil,
                createdAtMillis: 5, updatedAtMillis: 5))])
        }
        return data
    }

    @Test func repeatingExpensesAreSuggestedAsRecurring() {
        let s = StatementImportRules.prepare(bank([
            tx("2026-07-05", "CARD NETFLIX.COM", 649, .debit, balance: nil, merchant: "Netflix"),
            tx("2026-07-09", "UPI/Swiggy", 250, .debit, balance: nil, merchant: "Swiggy"),
            tx("2026-08-05", "CARD NETFLIX.COM", 649, .debit, balance: nil, merchant: "Netflix"),
            tx("2026-08-09", "UPI/Swiggy", 900, .debit, balance: nil, merchant: "Swiggy"),
            tx("2026-08-10", "NACH DR ICICI PRU SIP", 5_000, .debit, balance: nil, merchant: "ICICI Prudential"),
            tx("2026-08-12", "SPOTIFY", 119, .debit, balance: nil, merchant: "Spotify", recurring: true),
            tx("2026-08-15", "SALARY", 9_000, .credit, balance: nil, merchant: "Acme", recurring: true),
        ]), in: FinanceData(), today: today)
        #expect(s.rows.map(\.repeats) == [
            .new(.subscription), .no, .new(.subscription), .no, .new(.fixed), .new(.subscription), .no,
        ], "Swiggy's amounts differ; money in never repeats")
    }

    @Test func anExpenseMatchingARecurringPaymentPaysIt() {
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-06", "ACH D- HOME LOAN EMI 00123", 24_000, .debit, balance: nil),
            tx("2026-09-07", "ACH D- HOME LOAN EMI 00123", 12_000, .debit, balance: nil),
        ]), in: withLoan(nextDueOn: "2026-09-05"), today: today)
        #expect(s.rows[0].repeats == .pays(recurringUid: "loan"))
        #expect(s.rows[1].repeats == .new(.fixed), "half the EMI isn't this payment, but still reads like a mandate")
    }

    @Test func markingOneRowMarksTheMerchantsOthers() {
        var s = StatementImportRules.prepare(bank([
            tx("2026-07-02", "GYM", 1_500, .debit, balance: nil, merchant: "Cult"),
            tx("2026-08-03", "GYM", 1_800, .debit, balance: nil, merchant: "Cult"),
            tx("2026-08-04", "MONEY IN", 1_800, .credit, balance: nil, merchant: "Cult"),
        ]), in: FinanceData(), today: today)
        #expect(s.rows[0].repeats == .no)
        s.setRepeats(.new(.subscription), forRow: 1)
        #expect(s.rows.map(\.repeats) == [.new(.subscription), .new(.subscription), .no])
        s.setRepeats(.no, forRow: 0)
        #expect(s.rows.allSatisfy { $0.repeats == .no })
    }

    @Test func savingStartsARecurringPaymentPaidByItsRows() throws {
        var s = StatementImportRules.prepare(bank([
            tx("2026-07-05", "CARD NETFLIX.COM", 499, .debit, balance: nil, merchant: "Netflix", category: "food"),
            tx("2026-08-06", "CARD NETFLIX.COM", 649, .debit, balance: nil, merchant: "Netflix", category: "food"),
            tx("2026-08-09", "UPI/Swiggy", 250, .debit, balance: nil, merchant: "Swiggy"),
        ]), in: FinanceData(), today: today)
        #expect(s.rows.allSatisfy { $0.repeats == .no }, "a price rise is more than 5%: not suggested")
        s.setRepeats(.new(.subscription), forRow: 0)
        #expect(StatementImportRules.newRecurring(s).map(\.name) == ["Netflix"])
        let writes = try StatementImportRules.commit(s, in: FinanceData(), clock: clock).get().writes
        let payments = writes.compactMap { if case .recurring(let r) = $0 { r } else { nil } }
        let entries = writes.compactMap { if case .transaction(let t) = $0 { t } else { nil } }
        #expect(payments.count == 1)
        let r = try #require(payments.first)
        #expect(r.name == "Netflix" && r.kind == .subscription && r.amountMinor == 64_900 && r.frequency == .monthly)
        #expect(r.accountUid == s.accountUid && r.anchorDay == 6 && r.nextDueOn == day("2026-09-06"))
        let netflix = entries.filter { $0.recurringUid == r.uid }
        #expect(netflix.map(\.dueOn) == [day("2026-07-06"), day("2026-08-06")], "each pays the occurrence nearest its date")
        #expect(netflix.allSatisfy { $0.uid == FinanceIds.recurringOccurrence(r.uid, dueOn: $0.dueOn!) && $0.source == .statement })
        #expect(netflix.map(\.amountMinor) == [49_900, 64_900], "each keeps what was actually paid")
        #expect(entries.contains { $0.merchant == "Swiggy" && $0.recurringUid == nil && $0.uid.hasPrefix("imp_") })
    }

    @Test func aRowPayingAnOccurrenceThePhoneRecordedReplacesIt() throws {
        let data = withLoan(nextDueOn: "2026-09-05", phonePaid: "2026-08-05")
        let s = StatementImportRules.prepare(bank([
            tx("2026-08-05", "ACH D- HOME LOAN EMI", 24_000, .debit, balance: nil),
            tx("2026-09-06", "ACH D- HOME LOAN EMI", 24_000, .debit, balance: nil),
        ]), in: data, today: today)
        #expect(s.rows.allSatisfy { $0.repeats == .pays(recurringUid: "loan") })
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        let entries = writes.compactMap { if case .transaction(let t) = $0, t.type == .expense { t } else { nil } }
        #expect(entries.map(\.uid) == [FinanceIds.recurringOccurrence("loan", dueOn: day("2026-08-05")),
                                        FinanceIds.recurringOccurrence("loan", dueOn: day("2026-09-05"))])
        #expect(entries.allSatisfy { $0.accountUid == s.accountUid }, "the statement's account is where the money left")
        #expect(entries[0].createdAtMillis == 5, "the phone's entry is replaced, not doubled")
        let loan = writes.compactMap { if case .recurring(let r) = $0 { r } else { nil } }
        #expect(loan.map(\.uid) == ["loan"] && loan.first?.nextDueOn == day("2026-10-05"))
    }

    // MARK: Into an account you have

    private func account(_ uid: String, _ kind: AccountKind, last4: String?) -> Account {
        Account(uid: uid, kind: kind, name: uid, institution: nil, last4: last4, hasSecret: false, bankType: kind == .bank ? .savings : nil,
                ifsc: nil, linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
    }

    private func entry(_ uid: String, _ type: TransactionType, _ amount: Int64, on: String, account: String = "bank", to: String? = nil,
                       merchant: String? = nil, ref: String? = nil) -> Transaction {
        Transaction(uid: uid, type: type, amountMinor: amount, currency: "INR", occurredAtMillis: 0, occurredOn: day(on), accountUid: account,
                    toAccountUid: to, categoryUid: nil, merchant: merchant, payeeKey: merchant.map(FinanceIds.payeeKey), note: nil,
                    source: .sms, sourceRef: ref, recurringUid: nil, dueOn: nil, statementUid: nil, receipt: nil, createdAtMillis: 1, updatedAtMillis: 1)
    }

    /// The statement's account ("9001") already in Kortex, opened with ₹10,000 on 1 Sep, with what the phone recorded.
    private func existingBank(_ entries: [Transaction]) -> FinanceData {
        var data = FinanceData()
        data.apply([RemoteRow.live(account("bank", .bank, last4: "9001")), RemoteRow.live(account("card", .creditCard, last4: "4321"))])
        data.apply([RemoteRow.live(entry("open", .opening, 1_000_000, on: "2026-08-31"))] + entries.map { RemoteRow.live($0) })
        return data
    }

    @Test func theStatementsAccountIsFoundByItsLastFourDigits() {
        let data = existingBank([])
        #expect(StatementImportRules.existingAccount(for: bank([]), in: data)?.uid == "bank")
        #expect(StatementImportRules.accounts(for: bank([]), in: data).map(\.uid) == ["bank"], "a bank statement never goes into a card")
    }

    @Test func rowsAlreadyInKortexAreMatchedAndLeftOut() {
        let data = existingBank([
            entry("swiggy", .expense, 25_050, on: "2026-09-02", merchant: "Swiggy"),
            // The card bill, paid from this account on the phone: a debit on the bank statement.
            entry("bill", .cardPayment, 500_000, on: "2026-09-09", to: "card"),
            entry("cafe", .expense, 30_000, on: "2026-09-14", merchant: "Blue Tokai"),
            // Not on the statement at all.
            entry("cash", .expense, 99_900, on: "2026-09-20", merchant: "Croma"),
        ])
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "UPI/DR/4411/SWIGGY", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy"),
            tx("2026-09-05", "NEFT SALARY ACME", 50_000, .credit, balance: 59_749.50, merchant: "Acme"),
            tx("2026-09-10", "CC PAYMENT 4321", 5_000, .debit, balance: 54_749.50),
            tx("2026-09-16", "POS 7781 THIRD WAVE", 300, .debit, balance: 54_449.50, merchant: "Third Wave"),
        ], closing: 54_449.50), into: "bank", in: data, today: today)
        #expect(s.intoExisting && s.accountUid == "bank")
        #expect(s.rows.map { $0.match?.transactionUid } == ["swiggy", nil, "bill", "cafe"])
        #expect(s.rows.map(\.include) == [false, true, false, false])
        #expect(s.rows[0].match?.sure == true && s.rows[2].match?.sure == true, "same payee; a nameless card payment a day off")
        #expect(s.rows[3].match?.sure == false, "same amount two days apart under another name is worth a look")

        let r = try! #require(s.reconciliation(in: data))
        #expect(r.kortexOpeningMinor == 1_000_000)
        #expect(r.notOnStatement.map(\.uid) == ["cash"])
        #expect(r.kortexClosingMinor + 99_900 == s.closingMinor, "only the entry missing from the statement keeps Kortex off")
    }

    @Test func eachEntryMatchesOneRowTheClosestFirst() {
        let data = existingBank([entry("coffee", .expense, 20_000, on: "2026-09-03", merchant: "Cafe")])
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "CAFE", 200, .debit, balance: nil),
            tx("2026-09-03", "CAFE", 200, .debit, balance: nil),
            tx("2026-09-03", "CAFE", 200, .debit, balance: nil),
        ]), into: "bank", in: data, today: today)
        #expect(s.rows.map { $0.match?.transactionUid } == [nil, "coffee", nil])
        #expect(Set(s.rows.map(\.key)).count == 3, "identical rows still get their own entries")
    }

    @Test func aReferenceMatchesAcrossTheWindow() {
        let data = existingBank([entry("upi", .expense, 120_000, on: "2026-09-01", ref: "624512345678")])
        let s = StatementImportRules.prepare(bank([tx("2026-09-08", "UPI/624512345678/RENT", 1_200, .debit, balance: nil)]),
                                             into: "bank", in: data, today: today)
        #expect(s.rows[0].match == ImportMatch(transactionUid: "upi", sure: true, reason: "Same reference"))
    }

    @Test func savingIntoAnAccountAddsOnlyTheNewRows() throws {
        let data = existingBank([entry("swiggy", .expense, 25_050, on: "2026-09-02", merchant: "Swiggy")])
        let statement = bank([
            tx("2026-09-02", "UPI/SWIGGY", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy"),
            tx("2026-09-05", "NEFT SALARY ACME", 50_000, .credit, balance: 59_749.50, merchant: "Acme", category: "salary"),
        ])
        let s = StatementImportRules.prepare(statement, into: "bank", in: data, today: today)
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        let entries = writes.compactMap { if case .transaction(let t) = $0 { t } else { nil } }
        #expect(!writes.contains { if case .account = $0 { true } else { false } }, "the account is left as it is")
        #expect(entries.map(\.type) == [.income], "no opening entry, and Swiggy is already there")
        #expect(entries[0].accountUid == "bank" && entries[0].source == .statement)

        // Imported again later, the salary is recognised as this import's own entry.
        var after = data
        after.apply(entries.map { RemoteRow.live($0) })
        let again = StatementImportRules.prepare(statement, into: "bank", in: after, today: today)
        #expect(again.rows.allSatisfy { !$0.include })
        #expect(again.rows[1].match?.reason == "Imported from this statement before")
    }

    @Test func aCardsBillIsNotAddedTwice() throws {
        var data = existingBank([])
        data.apply([RemoteRow.live(CardStatement(uid: "phone", cardUid: "card", periodStart: day("2026-08-26"), statementOn: day("2026-09-24"),
                                                 dueOn: day("2026-10-14"), totalDueMinor: 145_000, minDueMinor: 20_000, source: .sms,
                                                 createdAtMillis: 0, updatedAtMillis: 0))])
        let card = ExtractedAccount(kind: .credit_card, institution: "Test Bank", productName: "Platinum", numberLast4: "4321", ifsc: nil,
                                    holder: nil, currency: "INR", periodStart: "2026-08-26", periodEnd: "2026-09-25", statementDate: "2026-09-25",
                                    openingBalance: 0, openingBalanceIsDebit: true, closingBalance: 1_450, closingBalanceIsDebit: true,
                                    creditLimit: nil, totalDue: 1_450, minimumDue: 200, paymentDueDate: "2026-10-15",
                                    transactions: [tx("2026-09-02", "AMAZON", 1_450, .debit, balance: 1_450, merchant: "Amazon")])
        #expect(StatementImportRules.existingAccount(for: card, in: data)?.uid == "card")
        let s = StatementImportRules.prepare(card, into: "card", in: data, today: today)
        #expect(StatementImportRules.billExists(s, in: data))
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        #expect(!writes.contains { if case .statement = $0 { true } else { false } })
        #expect(writes.contains { if case .transaction(let t) = $0 { t.accountUid == "card" && t.type == .expense } else { false } })
    }

    @Test func aNewPaymentIsMonthlyUnlessChosenYearly() throws {
        var s = StatementImportRules.prepare(bank([
            tx("2026-07-15", "GYM", 1_500, .debit, balance: nil, merchant: "Cult"),
            tx("2026-08-14", "GYM", 1_500, .debit, balance: nil, merchant: "Cult"),
            tx("2026-09-15", "GYM", 1_500, .debit, balance: nil, merchant: "Cult"),
        ]), in: FinanceData(), today: today)
        s.setRepeats(.new(.subscription), forRow: 0)
        let guessed = try #require(StatementImportRules.newRecurring(s).first)
        #expect(guessed.frequency == .monthly)
        #expect(guessed.nextDueOn == day("2026-10-15"))
        s.frequencies[guessed.uid] = .yearly
        let chosen = try #require(StatementImportRules.newRecurring(s).first)
        #expect(chosen.uid == guessed.uid && chosen.frequency == .yearly && chosen.nextDueOn == day("2027-09-15"))
        let writes = try StatementImportRules.commit(s, in: FinanceData(), clock: clock).get().writes
        #expect(writes.contains { if case .recurring(let r) = $0 { r.frequency == .yearly } else { false } })
    }

    @Test func mandateDebitsWithoutAMerchantGetATidyNameAndOnePaymentPerAmount() throws {
        let s = StatementImportRules.prepare(bank([
            tx("2026-07-05", "NACH trxn ACH/INDIAN CLEARING CORP/ICIC7020807210000150/P6401585X021553 381262741279437", 2_000, .debit, balance: nil),
            tx("2026-07-07", "NACH trxn ACH/INDIAN CLEARING CORP/HDFC7020800000000222/Q1 99", 15_000, .debit, balance: nil),
            tx("2026-08-05", "NACH trxn ACH/INDIAN CLEARING CORP/ICIC7020807210000188/P6401585X021553 381262741279999", 2_000, .debit, balance: nil),
            tx("2026-08-07", "NACH trxn ACH/INDIAN CLEARING CORP/HDFC7020800000000333/Q1 98", 15_000, .debit, balance: nil),
            tx("2026-08-09", "ACH D- HOME LOAN EMI 00123", 24_000, .debit, balance: nil),
        ]), in: FinanceData(), today: today)
        #expect(s.rows.map(StatementImportRules.paymentName) == [
            "Indian Clearing", "Indian Clearing", "Indian Clearing", "Indian Clearing", "Home Loan EMI",
        ])
        let payments = StatementImportRules.newRecurring(s)
        #expect(payments.map(\.amountMinor).sorted() == [200_000, 1_500_000, 2_400_000], "not one payment per row, nor one per clearing house")
        #expect(payments.allSatisfy { $0.name.count <= 40 && $0.frequency == .monthly })
        let writes = try StatementImportRules.commit(s, in: FinanceData(), clock: clock).get().writes
        let linked = writes.compactMap { if case .transaction(let t) = $0, t.recurringUid != nil { t } else { nil } }
        #expect(linked.count == 5)
        #expect(Set(linked.map(\.recurringUid)).count == 3)
    }

    // MARK: Twin instalments

    private func nach(_ date: String, _ amount: Double, _ ref: String) -> ExtractedTransaction {
        tx(date, "NACH trxn ACH/INDIAN CLEARING CORP/ICIC7020807210000150/\(ref) 3812\(String(date.filter(\.isNumber).reversed()))", amount, .debit, balance: nil)
    }

    @Test func twoSameInstalmentsAMonthWithoutAReferenceAreTwoPayments() throws {
        let s = StatementImportRules.prepare(bank([
            nach("2026-07-02", 2_000, "X"), nach("2026-07-06", 2_000, "X"),
            nach("2026-08-05", 2_000, "X"), nach("2026-08-03", 2_000, "X"),
            nach("2026-09-01", 2_000, "X"), nach("2026-09-04", 2_000, "X"),
        ]), in: FinanceData(), today: today)
        #expect(s.rows.allSatisfy { $0.mandateRef == nil }, "the shared route code is on two debits a month")
        let payments = StatementImportRules.newRecurring(s)
        #expect(payments.map(\.anchorDay).sorted() == [2, 5], "each month's first debit is one payment, its second the other")
        let writes = try StatementImportRules.commit(s, in: FinanceData(), clock: clock).get().writes
        let linked = writes.compactMap { if case .transaction(let t) = $0, t.recurringUid != nil { t } else { nil } }
        #expect(linked.count == 6, "no debit left over as a plain entry")
        #expect(Set(linked.map { "\($0.recurringUid!)|\($0.dueOn!)" }).count == 6)
    }

    @Test func aReferenceOnEveryDebitOfOneMandateKeepsTwinsApartWhateverTheirOrder() throws {
        let s = StatementImportRules.prepare(bank([
            nach("2026-07-02", 2_000, "P6401585X021553"), nach("2026-07-06", 2_000, "P7701234X000111"),
            nach("2026-08-03", 2_000, "P7701234X000111"), nach("2026-08-05", 2_000, "P6401585X021553"),
        ]), in: FinanceData(), today: today)
        #expect(s.rows.map(\.mandateRef) == ["P6401585X021553", "P7701234X000111", "P7701234X000111", "P6401585X021553"])
        let (payments, byRow) = StatementImportRules.startedPayments(s, now: 0)
        #expect(payments.count == 2)
        #expect(byRow[0] == byRow[3] && byRow[1] == byRow[2] && byRow[0] != byRow[1], "by mandate, not by which came first")
    }

    @Test func aMonthsDebitsShareOutTheMatchingPaymentsInDateOrder() throws {
        var data = withLoan(nextDueOn: "2026-09-05")
        for (uid, anchor) in [("early", 2), ("late", 4)] {
            data.apply([RemoteRow.live(Recurring(uid: uid, name: "Indian Clearing", kind: .fixed, amountMinor: 200_000, currency: "INR",
                                                 frequency: .monthly, interval: 1, anchorDay: anchor, nextDueOn: day("2026-09-0\(anchor)"),
                                                 accountUid: "bank", categoryUid: nil, remindDaysBefore: -1, autoMarkPaid: false, paused: false,
                                                 createdAtMillis: 0, updatedAtMillis: 0))])
        }
        let s = StatementImportRules.prepare(bank([
            nach("2026-09-06", 2_000, "X"), nach("2026-09-03", 2_000, "X"), nach("2026-09-09", 2_000, "X"),
        ]), in: data, today: today)
        #expect(s.rows[1].repeats == .pays(recurringUid: "early") && s.rows[0].repeats == .pays(recurringUid: "late"))
        #expect(s.rows[2].repeats == .new(.fixed), "a third debit is one you don't track yet")
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        let moved = writes.compactMap { if case .recurring(let r) = $0, r.uid == "early" || r.uid == "late" { r } else { nil } }
        #expect(Set(moved.map(\.nextDueOn)) == [day("2026-10-02"), day("2026-10-04")])
    }

    // MARK: Card bills paid from a bank account

    private func bill(_ uid: String, card: String, on: String, total: Int64, min: Int64 = 0) -> CardStatement {
        CardStatement(uid: uid, cardUid: card, periodStart: day(on).adding(days: -30), statementOn: day(on), dueOn: day(on).adding(days: 20),
                      totalDueMinor: total, minDueMinor: min, source: .manual, createdAtMillis: 0, updatedAtMillis: 0)
    }

    /// Two cards ("4321" and "8765", the second from HDFC) and no bank account yet; the first has a ₹5,000 bill from 25 Aug.
    private func twoCards() -> FinanceData {
        var data = FinanceData()
        var hdfc = account("hdfc", .creditCard, last4: "8765")
        hdfc.institution = "HDFC Bank"
        hdfc.createdAtMillis = 1
        data.apply([RemoteRow.live(account("card", .creditCard, last4: "4321")), RemoteRow.live(hdfc)])
        data.apply([RemoteRow.live(bill("aug", card: "card", on: "2026-08-25", total: 500_000, min: 25_000))])
        return data
    }

    @Test func billPaymentsOnABankStatementPayTheCardTheyName() {
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "UPI/Swiggy", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy"),
            tx("2026-09-03", "IB BILLPAY DR-XXXXXXXXXXXX4321", 2_000, .debit, balance: 7_749.50),
            tx("2026-09-04", "CREDIT CARD PAYMENT HDFC", 1_000, .debit, balance: 6_749.50),
            tx("2026-09-05", "CC PAYMENT", 5_000, .debit, balance: 1_749.50),
            tx("2026-09-06", "CC PAYMENT", 700, .debit, balance: 1_049.50),
            tx("2026-09-07", "POS 512345XXXXXX4321 CROMA", 49, .debit, balance: 1_000.50),
        ]), in: twoCards(), today: today)
        #expect(s.rows.map(\.kind) == [.expense, .cardPayment, .cardPayment, .cardPayment, .cardPayment, .expense])
        #expect(s.rows.map(\.cardUid) == [nil, "card", "hdfc", "card", nil, nil], "by number, bank, the bill's amount; two cards and nothing to go by is a pick")
        #expect(s.rows[1].categoryUid == nil && s.rows[1].repeats == .no)
    }

    @Test func theModelsFlagMarksAPaymentAndYourOnlyCardIsTheOnePaid() {
        var data = FinanceData()
        data.apply([RemoteRow.live(account("card", .creditCard, last4: "4321"))])
        var payment = tx("2026-09-03", "NEFT/CRED/AX1234", 2_000, .debit, balance: 8_000)
        payment.cardBillPayment = true
        let s = StatementImportRules.prepare(bank([payment]), in: data, today: today)
        #expect(s.rows[0].kind == .cardPayment && s.rows[0].cardUid == "card")
    }

    @Test func withNoCardABillPaymentStaysMoneyOutAndIsFlagged() {
        let s = StatementImportRules.prepare(bank([tx("2026-09-03", "CC PAYMENT 4321", 2_000, .debit, balance: 8_000)]), in: FinanceData(), today: today)
        #expect(s.rows[0].kind == .expense)
        #expect(s.rows[0].issue?.contains("credit card bill") == true)
    }

    @Test func savingABillPaymentMovesMoneyFromTheBankToTheCardAgainstItsBill() throws {
        let data = twoCards()
        let s = StatementImportRules.prepare(bank([tx("2026-09-05", "CC PAYMENT 4321", 5_000, .debit, balance: 5_000)]), in: data, today: today)
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        let paid = try #require(writes.compactMap { if case .transaction(let t) = $0, t.type == .cardPayment { t } else { nil } }.first)
        #expect(paid.accountUid == s.accountUid && paid.toAccountUid == "card" && paid.statementUid == "aug")
        #expect(paid.categoryUid == nil && paid.merchant == nil)
        var after = data
        after.apply(writes.compactMap { if case .account(let a) = $0 { RemoteRow.live(a) } else { nil } })
        after.apply(writes.compactMap { if case .transaction(let t) = $0 { RemoteRow.live(t) } else { nil } })
        let txs = Array(after.transactions.values)
        #expect(Statements.unpaidMinor(data.statements["aug"]!, txs) == 0)
        #expect(Spending.spentMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 0, "a bill payment isn't spending")
    }

    @Test func aBillPaymentWithNoCardChosenIsRefused() {
        let data = twoCards()
        let s = StatementImportRules.prepare(bank([tx("2026-09-06", "CC PAYMENT", 700, .debit, balance: 9_300)]), in: data, today: today)
        #expect(s.rows[0].cardUid == nil)
        #expect(throws: FinanceError.cardPaymentNeedsCard) { try StatementImportRules.commit(s, in: data, clock: clock).get() }
    }

    @Test func aPaymentTheCardHasFromAnotherAccountMovesToThisOne() throws {
        var data = twoCards()
        data.apply([RemoteRow.live(account("other", .bank, last4: "1111"))])
        // The card's statement was imported first, guessing the payment came from "other".
        var guessed = entry("guess", .cardPayment, 500_000, on: "2026-09-06", account: "other", to: "card")
        guessed.statementUid = "aug"
        data.apply([RemoteRow.live(guessed)])
        let s = StatementImportRules.prepare(bank([tx("2026-09-05", "CC PAYMENT 4321", 5_000, .debit, balance: 5_000)]), in: data, today: today)
        #expect(s.rows[0].replaces == "guess" && s.rows[0].include)
        #expect(s.rows[0].issue?.contains("other") == true)
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        let payments = writes.compactMap { if case .transaction(let t) = $0, t.type == .cardPayment { t } else { nil } }
        #expect(payments.count == 1)
        #expect(payments[0].uid == "guess" && payments[0].accountUid == s.accountUid && payments[0].statementUid == "aug")
    }

    // MARK: A bank's card bill saved as money out, then the card's statement

    private func cardStatement(_ txs: [ExtractedTransaction]) -> ExtractedAccount {
        ExtractedAccount(kind: .credit_card, institution: "Test Bank", productName: "Platinum Credit Card", numberLast4: "4321",
                         ifsc: nil, holder: nil, currency: "INR", periodStart: "2026-08-26", periodEnd: "2026-09-25",
                         statementDate: "2026-09-25", openingBalance: 5_000, openingBalanceIsDebit: true, closingBalance: 1_500,
                         closingBalanceIsDebit: true, creditLimit: 100_000, totalDue: 1_500, minimumDue: 200, paymentDueDate: "2026-10-15",
                         transactions: txs)
    }

    /// `data` with every write of `change` applied.
    private func saved(_ change: Change, onto data: FinanceData) -> FinanceData {
        var after = data
        for write in change.writes {
            switch write {
            case .account(let a): after.apply([RemoteRow.live(a)])
            case .transaction(let t): after.apply([RemoteRow.live(t)])
            case .statement(let b): after.apply([RemoteRow.live(b)])
            default: break
            }
        }
        return after
    }

    @Test func aBankStatementImportedBeforeTheCardIsPutRightByTheCardsStatement() throws {
        var payment = tx("2026-09-04", "NEFT/CRED/AX1234", 5_000, .debit, balance: 4_749.50, category: "bills")
        payment.cardBillPayment = true
        let bankImport = StatementImportRules.prepare(bank([
            tx("2026-09-02", "UPI/Swiggy", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy", category: "food"),
            payment,
        ]), in: FinanceData(), today: today)
        #expect(bankImport.rows[1].kind == .expense && bankImport.rows[1].otherSideMissing)
        #expect(bankImport.rows[1].categoryUid == nil, "a card bill is never put in a category")
        var data = saved(try StatementImportRules.commit(bankImport, in: FinanceData(), clock: clock).get(), onto: FinanceData())
        let debit = try #require(data.transactions.values.first { $0.amountMinor == 500_000 })
        #expect(debit.type == .expense && debit.note == "NEFT/CRED/AX1234" && debit.categoryUid == nil)

        let cardImport = StatementImportRules.prepare(cardStatement([
            tx("2026-09-02", "AMAZON", 1_500, .debit, balance: 6_500, merchant: "Amazon"),
            tx("2026-09-05", "PAYMENT RECEIVED THANK YOU", 5_000, .credit, balance: 1_500),
        ]), in: data, today: today)
        let row = cardImport.rows[1]
        #expect(row.kind == .cardPayment && row.include)
        #expect(row.replaces == debit.uid && row.fromAccountUid == bankImport.accountUid)
        #expect(row.issue?.contains("NEFT/CRED/AX1234") == true)

        data = saved(try StatementImportRules.commit(cardImport, in: data, clock: clock).get(), onto: data)
        let txs = Array(data.transactions.values)
        let payments = txs.filter { $0.type == .cardPayment }
        #expect(payments.count == 1 && payments[0].uid == debit.uid, "the debit became the payment; nothing paid twice")
        #expect(payments[0].occurredOn == day("2026-09-04"), "on the day the money left the bank")
        #expect(payments[0].categoryUid == nil && payments[0].toAccountUid == cardImport.accountUid)
        #expect(Spending.spentMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 25_050 + 150_000, "Swiggy and Amazon, not the bill")
        let bankAccount = try #require(data.accounts[bankImport.accountUid])
        let card = try #require(data.accounts[cardImport.accountUid])
        #expect(Balances.balance(of: bankAccount, transactions: txs, accounts: data.accounts) == 474_950)
        #expect(Balances.balance(of: card, transactions: txs, accounts: data.accounts) == 150_000)
    }

    @Test func aDebitThatReadsLikeTheBillIsPreferredAndNamedOnesAreLeftAlone() {
        var data = existingBank([
            entry("atm", .expense, 500_000, on: "2026-09-05", merchant: "Cash"),
            entry("blank", .expense, 500_000, on: "2026-09-05"),
            entry("emi", .expense, 500_000, on: "2026-09-05"),
            entry("sms", .expense, 500_000, on: "2026-09-06"),
        ])
        var emi = data.transactions["emi"]!
        emi.recurringUid = "loan"
        var sms = data.transactions["sms"]!
        sms.note = "HDFC CC PAYMENT XX4321"
        data.apply([RemoteRow.live(emi), RemoteRow.live(sms)])
        // A new card, so the phone's card isn't in the way.
        data.apply([RemoteRow<Account>.deleted(uid: "card")])
        let s = StatementImportRules.prepare(cardStatement([
            tx("2026-09-05", "PAYMENT RECEIVED THANK YOU", 5_000, .credit, balance: 0),
            tx("2026-09-05", "PAYMENT RECEIVED THANK YOU", 5_000, .credit, balance: -5_000),
        ]), in: data, today: today)
        #expect(s.rows.map(\.replaces) == ["sms", "blank"], "wording first, a day off; then the nameless one; never named or recurring")
        #expect(s.rows.allSatisfy { $0.fromAccountUid == "bank" })
    }

    @Test func choosingAnotherPaidFromAccountKeepsTheDebitAsItIs() throws {
        var data = existingBank([entry("blank", .expense, 500_000, on: "2026-09-05")])
        data.apply([RemoteRow<Account>.deleted(uid: "card"), RemoteRow.live(account("wallet", .bank, last4: nil))])
        var s = StatementImportRules.prepare(cardStatement([tx("2026-09-05", "PAYMENT RECEIVED THANK YOU", 5_000, .credit, balance: 0)]),
                                             in: data, today: today)
        #expect(s.rows[0].replaces == "blank")
        s.rows[0].fromAccountUid = "wallet"
        let writes = try StatementImportRules.commit(s, in: data, clock: clock).get().writes
        #expect(!writes.contains { if case .transaction(let t) = $0 { return t.uid == "blank" } else { return false } })
    }

    // MARK: Transfers between your accounts

    /// Another savings account you have, at ICICI, ending 5555.
    private func withICICI() -> FinanceData {
        var data = FinanceData()
        var icici = account("icici", .bank, last4: "5555")
        icici.institution = "ICICI Bank"
        data.apply([RemoteRow.live(icici)])
        return data
    }

    private func flagged(_ t: ExtractedTransaction) -> ExtractedTransaction {
        var t = t
        t.ownTransfer = true
        return t
    }

    @Test func moneyBetweenYourAccountsIsATransferAndAPaymentToSomeoneElseIsNot() throws {
        let data = withICICI()
        let s = StatementImportRules.prepare(bank([
            tx("2026-09-02", "IMPS/TRF TO A/C XXXX5555", 20_000, .debit, balance: nil, category: "bills"),
            tx("2026-09-03", "UPI/RAHUL SHARMA/XX5555", 500, .debit, balance: nil, merchant: "Rahul Sharma", category: "food"),
            flagged(tx("2026-09-04", "NEFT CR SELF ICICI", 3_000, .credit, balance: nil)),
            flagged(tx("2026-09-05", "IMPS SELF", 1_000, .debit, balance: nil, category: "bills")),
        ]), in: data, today: today)
        #expect(s.rows.map(\.kind) == [.transferOut, .expense, .transferIn, .expense])
        #expect(s.rows.map(\.transferAccountUid) == ["icici", nil, "icici", nil], "by number, a named payee never, by bank; nothing to go by stays money out")
        #expect(s.rows[0].categoryUid == nil && s.rows[1].categoryUid == "food")
        #expect(s.rows[3].otherSideMissing && s.rows[3].categoryUid == nil && s.rows[3].issue?.contains("transfer") == true)

        let after = saved(try StatementImportRules.commit(s, in: data, clock: clock).get(), onto: data)
        let txs = Array(after.transactions.values)
        let transfers = txs.filter { $0.type == .transfer }.sorted { $0.amountMinor > $1.amountMinor }
        #expect(transfers.map { [$0.accountUid, $0.toAccountUid] } == [[s.accountUid, "icici"], ["icici", s.accountUid]])
        #expect(transfers.allSatisfy { $0.categoryUid == nil })
        #expect(Spending.spentMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 50_000 + 100_000, "Rahul and the unresolved one, never the transfers")
        #expect(Spending.incomeMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 0)
        #expect(Balances.balance(of: after.accounts["icici"]!, transactions: txs, accounts: after.accounts) == 2_000_000 - 300_000)
    }

    @Test func aTransferToAnAccountNotYetInKortexIsPutRightByThatAccountsStatement() throws {
        let first = StatementImportRules.prepare(bank([flagged(tx("2026-09-04", "IMPS/SELF/TO XX9002", 20_000, .debit, balance: nil, category: "bills"))]),
                                                 in: FinanceData(), today: today)
        #expect(first.rows[0].kind == .expense && first.rows[0].otherSideMissing && first.rows[0].categoryUid == nil)
        var data = saved(try StatementImportRules.commit(first, in: FinanceData(), clock: clock).get(), onto: FinanceData())
        let debit = try #require(data.transactions.values.first { $0.amountMinor == 2_000_000 })
        #expect(debit.note == "IMPS/SELF/TO XX9002")

        // The other account's statement: a plain credit, unflagged, naming nothing. The debit names this account.
        let second = StatementImportRules.prepare(bank([tx("2026-09-05", "IMPS CR 60123", 20_000, .credit, balance: nil, category: "salary")],
                                                       number: "9002"), in: data, today: today)
        #expect(second.rows[0].kind == .transferIn && second.rows[0].transferAccountUid == first.accountUid)
        #expect(second.rows[0].replaces == debit.uid && second.rows[0].categoryUid == nil)

        data = saved(try StatementImportRules.commit(second, in: data, clock: clock).get(), onto: data)
        let txs = Array(data.transactions.values)
        let moved = try #require(data.transactions[debit.uid])
        #expect(moved.type == .transfer && moved.accountUid == first.accountUid && moved.toAccountUid == second.accountUid)
        #expect(moved.occurredOn == day("2026-09-04") && moved.categoryUid == nil)
        #expect(txs.filter { $0.type != .opening }.count == 1, "one transfer, not money out and money in")
        #expect(Spending.spentMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 0)
        #expect(Spending.incomeMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 0)
        #expect(Balances.balance(of: data.accounts[second.accountUid]!, transactions: txs, accounts: data.accounts) == 1_000_000 + 2_000_000)
    }

    @Test func anUnflaggedRowIsNeverTakenForATransferOnTheAmountAlone() {
        var data = withICICI()
        data.apply([RemoteRow.live(entry("in", .income, 50_000, on: "2026-09-03", account: "icici"))])
        let s = StatementImportRules.prepare(bank([tx("2026-09-03", "UPI/SHOP", 500, .debit, balance: nil)]), in: data, today: today)
        #expect(s.rows[0].kind == .expense && s.rows[0].replaces == nil)
    }

    @Test func aTransferWithNoOtherAccountChosenIsRefused() {
        let data = withICICI()
        var s = StatementImportRules.prepare(bank([tx("2026-09-03", "UPI/SHOP", 500, .debit, balance: nil)]), in: data, today: today)
        s.rows[0].kind = .transferOut
        #expect(throws: FinanceError.transferNeedsAccount) { try StatementImportRules.commit(s, in: data, clock: clock).get() }
    }

    // MARK: A card's statement before any bank

    @Test func aCardsBillPaymentWithNoBankIsFromAnUnknownAccountUntilTheBanksStatementShowsIt() throws {
        let cardImport = StatementImportRules.prepare(cardStatement([
            tx("2026-09-02", "AMAZON", 1_500, .debit, balance: 6_500, merchant: "Amazon"),
            tx("2026-09-05", "PAYMENT RECEIVED THANK YOU", 5_000, .credit, balance: 1_500),
        ]), in: FinanceData(), today: today)
        #expect(cardImport.rows[1].kind == .cardPayment && cardImport.rows[1].fromAccountUid == nil)
        var data = saved(try StatementImportRules.commit(cardImport, in: FinanceData(), clock: clock).get(), onto: FinanceData())
        let payment = try #require(data.transactions.values.first { $0.type == .cardPayment })
        #expect(payment.accountUid == FinanceIds.unknownAccount && payment.toAccountUid == cardImport.accountUid)
        let card = try #require(data.accounts[cardImport.accountUid])
        #expect(Balances.balance(of: card, transactions: Array(data.transactions.values), accounts: data.accounts) == 150_000,
                "the card owes what its statement says, before any bank is in Kortex")

        // The bank's statement: a debit for the amount a day before, with nothing to say it's a card bill.
        let bankImport = StatementImportRules.prepare(bank([
            tx("2026-09-02", "UPI/Swiggy", 250.50, .debit, balance: 9_749.50, merchant: "Swiggy"),
            tx("2026-09-04", "NEFT DR 0012345", 5_000, .debit, balance: 4_749.50),
        ]), in: data, today: today)
        let row = bankImport.rows[1]
        #expect(row.kind == .cardPayment && row.cardUid == cardImport.accountUid && row.replaces == payment.uid)
        #expect(row.issue?.contains("unknown account") == true)

        data = saved(try StatementImportRules.commit(bankImport, in: data, clock: clock).get(), onto: data)
        let txs = Array(data.transactions.values)
        let payments = txs.filter { $0.type == .cardPayment }
        #expect(payments.count == 1 && payments[0].uid == payment.uid, "assigned, not paid twice")
        #expect(payments[0].accountUid == bankImport.accountUid && payments[0].toAccountUid == cardImport.accountUid)
        #expect(Balances.balance(of: card, transactions: txs, accounts: data.accounts) == 150_000)
        #expect(Balances.balance(of: data.accounts[bankImport.accountUid]!, transactions: txs, accounts: data.accounts) == 474_950)
        #expect(Spending.spentMinor(txs, from: day("2026-09-01"), to: day("2026-09-30")) == 25_050 + 150_000)
    }

    @Test func aNamedDebitIsNotTakenForAnUnknownBillPayment() throws {
        let cardImport = StatementImportRules.prepare(cardStatement([tx("2026-09-05", "PAYMENT RECEIVED", 5_000, .credit, balance: 0)]),
                                                      in: FinanceData(), today: today)
        let data = saved(try StatementImportRules.commit(cardImport, in: FinanceData(), clock: clock).get(), onto: FinanceData())
        let s = StatementImportRules.prepare(bank([tx("2026-09-05", "UPI/RAHUL", 5_000, .debit, balance: nil, merchant: "Rahul")]), in: data, today: today)
        #expect(s.rows[0].kind == .expense && s.rows[0].replaces == nil)
    }
}
