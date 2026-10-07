import Testing
@testable import KortexFinance

/// kortex's ReceiptParserTest, ported: the receipt on Figma's Scan receipt screens.
struct ReceiptParserTests {
    private let today = LocalDay(year: 2026, month: 10, day: 1)!

    private let brewhouse = """
    BREWHOUSE CAFÉ
    100 Ft Rd, Indiranagar
    GSTIN 29ABCDE1234F1Z5
    30/09/2026 13:42      Bill #4821
    Cappuccino x2          420.00
    Avocado toast          380.00
    Banana bread           180.00
    Cold brew              200.00
    Subtotal             1,180.00
    CGST 2.5%               29.50
    SGST 2.5%               29.50
    TOTAL                1,239.00
    PAID VISA ****8824   1,239.00
    Thank you · visit again
    """

    @Test func aClearReceipt() {
        let r = ReceiptParser.parse(brewhouse, today: today)
        #expect(r.merchant == "Brewhouse Café")
        #expect(r.date == LocalDay(year: 2026, month: 9, day: 30))
        #expect(r.time == DayTime(hour: 13, minute: 42))
        #expect(r.total == 1_239_00)
        #expect(r.taxMinor == 59_00)
        #expect(r.last4 == "8824")
        #expect(r.items.map(\.name) == ["Cappuccino", "Avocado toast", "Banana bread", "Cold brew"])
        #expect(r.items.first?.quantity == 2)
        #expect(r.candidates.map(\.amountMinor) == [1_239_00, 1_180_00])
        #expect(r.candidates.first?.label == "Total, incl. ₹59 GST")
    }

    @Test func aSmudgedTotalLeavesTheChoiceToThePerson() {
        let smudged = brewhouse.split(separator: "\n").filter { !$0.hasPrefix("TOTAL") && !$0.hasPrefix("PAID") }.joined(separator: "\n")
        let r = ReceiptParser.parse(smudged, today: today)
        #expect(r.total == nil)
        #expect(r.candidates.map(\.amountMinor) == [1_239_00, 1_180_00])
    }

    @Test func nothingThatLooksLikeMoneyIsUnreadable() {
        #expect(ReceiptParser.parse("BREWHOUSE\n~~ ~~~ ~~\n", today: today).unreadable)
        #expect(ReceiptParser.parse("", today: today).unreadable)
    }

    @Test func textReadingBasics() {
        #expect(TextReading.minorOf("48,557.50") == 4_855_750)
        #expect(TextReading.minorOf("12.5") == 1_250)
        #expect(TextReading.minorOf("1.2.3") == nil)
        #expect(TextReading.date("on 28-Sep", today: today)?.value == LocalDay(year: 2026, month: 9, day: 28))
        #expect(TextReading.date("15 Dec", today: today)?.value == LocalDay(year: 2025, month: 12, day: 15), "a yearless date never lands in the future")
        #expect(TextReading.time("at 6:42 PM")?.value == DayTime(hour: 18, minute: 42))
        #expect(TextReading.tidyName("ACME TECHNOLOGIES PVT LTD") == "Acme Technologies")
        #expect(TextReading.tidyName("Whole Foods Market") == "Whole Foods Market")
    }

    @Test func aMatchingExpenseWithoutAReceiptIsADuplicate() {
        let clock = FinanceClock(nowMillis: 1_790_674_200_000, zone: .current)
        var data = FinanceData()
        let card = Account(uid: "card", kind: .creditCard, name: "KORTEX", institution: nil, last4: "8824", hasSecret: false, bankType: nil,
                           ifsc: nil, linkedAccountUid: nil, network: nil, expiry: nil, holder: nil, creditLimitMinor: nil, statementDay: nil,
                           dueDay: nil, colorToken: nil, archived: false, createdAtMillis: 0, updatedAtMillis: 0)
        data.apply([RemoteRow.live(card)])
        #expect(EntryMatching.cardFor(last4: "8824", in: data)?.uid == "card")
        guard case .success(let change) = EntryRules.add(TransactionDraft(type: .expense, amountMinor: 1_239_00, accountUid: "card",
                                                                         occurredAtMillis: clock.nowMillis - 20 * 60_000), in: data, clock: clock),
              case .transaction(let sms) = change.writes[0] else { Issue.record("no entry"); return }
        data.apply([RemoteRow.live(sms)])
        let dup = EntryMatching.duplicateOf(amountMinor: 1_239_00, accountUid: "card", atMillis: clock.nowMillis, exactTime: true, in: data, clock: clock)
        #expect(dup?.uid == sms.uid)
        #expect(EntryMatching.duplicateOf(amountMinor: 1_240_00, accountUid: "card", atMillis: clock.nowMillis, exactTime: true, in: data, clock: clock) == nil)
    }
}
