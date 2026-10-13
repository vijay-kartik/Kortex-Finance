import Foundation
import Testing
@testable import KortexFinance

struct MoneyTests {
    @Test func parsesTypedAmounts() {
        #expect(Money.parseMinor("1,234.5") == 123_450)
        #expect(Money.parseMinor("₹ 42") == 4200)
        #expect(Money.parseMinor(".5") == 50)
        #expect(Money.parseMinor("42.") == 4200)
        #expect(Money.parseMinor("0.05") == 5)
    }

    @Test func rejectsWhatIsNotAnAmount() {
        for text in ["", " ", ".", "1.234", "1.2.3", "-5", "abc"] {
            #expect(Money.parseMinor(text) == nil, "\(text)")
        }
    }

    @Test func rejectsAmountsTooBigForPaiseInsteadOfTrapping() {
        #expect(Money.parseMinor("100000000000000000") == nil)
        #expect(Money.parseMinor(String(Int64.max)) == nil)
        #expect(Money.parseMinor("92233720368547758.08") == nil, "fits after × 100, overflows adding the paise")
        #expect(Money.parseMinor("92233720368547758.07") == Int64.max)
    }

    @Test func rejectsDigitsThatAreNotASCII() {
        #expect(Money.parseMinor("12.५०") == nil)
        #expect(Money.parseMinor("१२") == nil)
        #expect(Money.parseMinor("12.٥") == nil)
        #expect(Money.parseMinor("½") == nil)
        #expect(Money.parseMinor("4²") == nil)
    }

    @Test func editableAmounts() {
        #expect(Money.editable(4250) == "42.50")
        #expect(Money.editable(124_500) == "1245")
        #expect(Money.editable(5) == "0.05")
        for minor: Int64 in [0, 5, 50, 4250, 124_500, 123_456_789_012] {
            #expect(Money.parseMinor(Money.editable(minor)) == minor)
        }
    }

    @Test func formatsWithIndianGrouping() {
        #expect(Money.format(2_485_012) == "₹24,850.12")
        #expect(Money.format(12_345_678_900) == "₹12,34,56,789.00")
    }

    @Test func wholeUnitsRoundHalfUp() {
        #expect(Money.format(446_650, wholeUnits: true) == "₹4,467")
        #expect(Money.format(446_649, wholeUnits: true) == "₹4,466")
    }

    @Test func signs() {
        #expect(Money.format(-4250) == "−₹42.50")
        #expect(Money.format(-4250, signed: true) == "−₹42.50")
        #expect(Money.format(4250, signed: true) == "+₹42.50")
        #expect(Money.format(0, signed: true) == "₹0.00")
    }
}
