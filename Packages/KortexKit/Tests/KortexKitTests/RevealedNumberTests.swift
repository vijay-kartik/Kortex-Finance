import Foundation
import Testing
@testable import KortexKit

/// On a notification center of its own, so the tests never hear the real app or workspace.
@MainActor
struct RevealedNumberTests {
    private let away = Notification.Name("RevealedNumberTests.away")

    @Test func hidesAfterTheTimeout() async {
        let center = NotificationCenter()
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await RevealedNumber.waitToHide(after: .milliseconds(50), on: [(center, away)])
        }
        #expect(elapsed >= .milliseconds(50))
        #expect(elapsed < .seconds(5))
    }

    @Test func hidesAsSoonAsTheUserStepsAway() async throws {
        let center = NotificationCenter()
        let clock = ContinuousClock()
        let start = clock.now
        let wait = Task { await RevealedNumber.waitToHide(after: .seconds(30), on: [(center, away)]) }
        try await Task.sleep(for: .milliseconds(100))
        center.post(name: away, object: nil)
        await wait.value
        #expect(clock.now - start < .seconds(5))
    }

    @Test func ignoresOtherNotifications() async throws {
        let center = NotificationCenter()
        let clock = ContinuousClock()
        let start = clock.now
        let wait = Task { await RevealedNumber.waitToHide(after: .milliseconds(300), on: [(center, away)]) }
        try await Task.sleep(for: .milliseconds(50))
        center.post(name: Notification.Name("RevealedNumberTests.other"), object: nil)
        await wait.value
        #expect(clock.now - start >= .milliseconds(300))
    }

    @Test func listensForTheAppResigningAndTheScreenLocking() {
        let names = RevealedNumber.away.map(\.1.rawValue)
        #expect(names.contains("NSApplicationDidResignActiveNotification"))
        #expect(names.contains("NSWorkspaceScreensDidSleepNotification"))
        #expect(names.contains("com.apple.screenIsLocked"))
    }
}
