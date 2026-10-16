import SwiftUI
import Testing
@testable import KortexKit

struct KPillTests {
    @Test func sizesFollowTheFigma() {
        #expect(KPill.Size.regular.fontSize == 11)
        #expect(KPill.Size.regular.verticalPadding == 3)
        #expect(KPill.Size.regular.iconSpacing == 4)
        #expect(KPill.Size.large.fontSize == 12)
        #expect(KPill.Size.large.verticalPadding == 4)
        #expect(KPill.Size.large.iconSpacing == 6)
    }

    @Test func defaultsToARegularPillWithNoIcon() {
        let pill = KPill("Unpaid", color: .kAmber)
        #expect(pill.size == .regular && pill.systemImage == nil)
        let badge = KPill("Due in 16 days", color: .kAmber, size: .large, systemImage: "bell")
        #expect(badge.size == .large && badge.systemImage == "bell")
    }
}
