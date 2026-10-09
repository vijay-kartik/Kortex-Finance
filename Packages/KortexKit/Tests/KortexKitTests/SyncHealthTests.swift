import Testing
@testable import KortexCloud

struct SyncHealthTests {
    private let collections = ["finAccounts", "finTransactions", "finMerchants"]

    private func allLive() -> SyncHealth {
        var health = SyncHealth(collections: collections)
        for name in collections { health.received(name, fromCache: false) }
        return health
    }

    @Test func loadingUntilEveryCollectionAnswers() {
        var health = SyncHealth(collections: collections)
        #expect(health.status == .loading)
        health.received("finAccounts", fromCache: false)
        health.received("finTransactions", fromCache: false)
        #expect(health.status == .loading)
        health.received("finMerchants", fromCache: false)
        #expect(health.status == .live)
    }

    @Test func offlineWhenAnyAnswerIsCached() {
        var health = allLive()
        health.received("finMerchants", fromCache: true)
        #expect(health.status == .offline)
    }

    @Test func errorThenAnotherCollectionsSnapshotIsStillFailed() {
        var health = allLive()
        health.failed("finTransactions", message: "Missing or insufficient permissions.")
        #expect(health.status == .failed("Missing or insufficient permissions."))
        health.received("finAccounts", fromCache: false)
        health.received("finMerchants", fromCache: true)
        #expect(health.status == .failed("Missing or insufficient permissions."))
    }

    @Test func recoversOnceTheReattachedListenerAnswers() {
        var health = allLive()
        health.failed("finTransactions", message: "Unavailable")
        health.received("finTransactions", fromCache: false)
        #expect(health.status == .live)
    }

    @Test func staysFailedWhileAnyCollectionIsDown() {
        var health = allLive()
        health.failed("finAccounts", message: "a")
        health.failed("finMerchants", message: "m")
        health.received("finAccounts", fromCache: false)
        #expect(health.status == .failed("m"))
        health.received("finMerchants", fromCache: false)
        #expect(health.status == .live)
    }

    @Test func retryBacksOffAndCaps() {
        var health = allLive()
        var delays: [Duration] = []
        for _ in 0..<8 {
            health.failed("finTransactions", message: "x")
            delays.append(health.retryDelay(for: "finTransactions"))
        }
        #expect(delays == [2, 4, 8, 16, 32, 60, 60, 60].map { .seconds($0) })
        // A snapshot resets the backoff.
        health.received("finTransactions", fromCache: false)
        health.failed("finTransactions", message: "x")
        #expect(health.retryDelay(for: "finTransactions") == .seconds(2))
    }
}
