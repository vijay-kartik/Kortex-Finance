import SwiftUI
import Testing
@testable import KortexKit

struct SplitBarTests {
    @Test func firstTakesItsShareLessHalfTheGap() {
        #expect(SplitBar.firstWidth(first: 300, rest: 100, in: 200) == 148.5)
        #expect(SplitBar.firstWidth(first: 100, rest: 0, in: 200) == 198.5)
    }

    @Test func smallFirstIsAtLeastSixPoints() {
        #expect(SplitBar.firstWidth(first: 1, rest: 1_000_000, in: 200) == 6)
    }

    @Test func noFirstHasNoWidth() {
        #expect(SplitBar.firstWidth(first: 0, rest: 500, in: 200) == 0)
        #expect(SplitBar.firstWidth(first: 0, rest: 0, in: 200) == 0)
    }
}
