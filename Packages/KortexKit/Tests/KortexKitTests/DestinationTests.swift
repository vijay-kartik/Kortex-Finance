import SwiftUI
import Testing
@testable import KortexKit

struct DestinationTests {
    @Test func sidebarGroupsCoverEveryDestinationOnce() {
        let grouped = Destination.overview + Destination.plan
        #expect(Set(grouped) == Set(Destination.allCases))
        #expect(grouped.count == Destination.allCases.count)
    }

    @Test func shortcutsAreUnique() {
        let keys = Destination.allCases.compactMap { $0.shortcut?.character }
        #expect(Set(keys).count == keys.count)
    }
}
