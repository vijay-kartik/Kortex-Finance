import SwiftUI
import Testing
@testable import KortexKit

struct KortexButtonStyleTests {
    @Test func sizesFollowTheFigma() {
        #expect(KortexButtonStyle.Size.regular.height == 32)
        #expect(KortexButtonStyle.Size.regular.fontSize == 13)
        #expect(KortexButtonStyle.Size.small.height == 26)
        #expect(KortexButtonStyle.Size.small.fontSize == 12)
    }

    @Test func staticsPickTheirRole() {
        #expect(KortexButtonStyle.kortexPrimary.role == .primary)
        #expect(KortexButtonStyle.kortexSecondary.role == .secondary)
        let cancel = KortexButtonStyle.kortex(.secondary, hint: "esc")
        #expect(cancel.role == .secondary && cancel.size == .regular && cancel.hint == "esc")
    }
}
