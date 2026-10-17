import KortexFinance
import SwiftUI
import Testing
@testable import KortexKit

@MainActor
struct SessionTests {
    @Test func initialsComeFromTheNameElseTheEmail() {
        #expect(SessionUser(uid: "u", displayName: "Aarav Mehta", email: "a@example.com").initials == "AM")
        #expect(SessionUser(uid: "u", displayName: "priya", email: nil).initials == "P")
        #expect(SessionUser(uid: "u", displayName: nil, email: "zoe@example.com").initials == "Z")
        #expect(SessionUser(uid: "u", displayName: nil, email: nil).initials == "?")
    }

    @Test func userIsSetOnlyWhenSignedIn() async {
        let session = PreviewSession(.signedOut, finance: PreviewFinanceStore())
        #expect(session.user == nil)
        await session.signIn()
        #expect(session.user == PreviewSession.previewUser)
        session.signOut()
        #expect(session.state == .signedOut && session.user == nil)
    }

    @Test func checkGoesThroughTheSession() async {
        struct Refused: Error {}
        let session = PreviewSession(finance: PreviewFinanceStore())
        await #expect(throws: Never.self) { try await session.checkFinanceKey() }
        session.checkFailure = Refused()
        await #expect(throws: Refused.self) { try await session.checkFinanceKey() }
        #expect(session.checks == 2)
    }

    @Test(arguments: [SessionState.starting, .signedOut, .signingIn, .signedIn(PreviewSession.previewUser)])
    func rootViewBuildsWithoutFirebase(_ state: SessionState) {
        let session = PreviewSession(state, finance: PreviewFinanceStore.sample())
        _ = RootView(model: AppModel(), session: session).body
    }

    @Test func settingsBuildWithoutFirebase() {
        let session = PreviewSession(finance: PreviewFinanceStore())
        _ = SettingsView(session: session).body
        _ = AccountNumberSettings(session: session).body
    }
}
