import Testing
@testable import KortexKit

struct FormatCountTests {
    @Test func defaultPluralAddsS() {
        #expect(Format.count(0, "account") == "0 accounts")
        #expect(Format.count(1, "account") == "1 account")
        #expect(Format.count(2, "account") == "2 accounts")
    }

    @Test func irregularPluralIsUsedAsGiven() {
        #expect(Format.count(0, "entry", "entries") == "0 entries")
        #expect(Format.count(1, "entry", "entries") == "1 entry")
        #expect(Format.count(2, "entry", "entries") == "2 entries")
    }

    @Test func pointsReadTheSame() {
        #expect(Format.points(1) == "1 point")
        #expect(Format.points(3) == "3 points")
    }
}
