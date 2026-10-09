import Foundation

/// Each collection's listener state, folded into one `FinanceSync.Status`. No Firebase here, so the
/// folding can be tested on its own.
struct SyncHealth {
    let collections: [String]

    /// Per collection: nil before its first snapshot or while its listener is down, else whether
    /// that snapshot came from the cache.
    private(set) var fromCache: [String: Bool] = [:]
    /// Collections whose listener ended with an error, with the message. Cleared by the next
    /// snapshot from the re-attached listener.
    private(set) var failed: [String: String] = [:]
    /// Errors in a row per collection, for the retry backoff.
    private(set) var attempts: [String: Int] = [:]

    init(collections: [String]) {
        self.collections = collections
    }

    mutating func received(_ collection: String, fromCache cached: Bool) {
        fromCache[collection] = cached
        failed[collection] = nil
        attempts[collection] = nil
    }

    mutating func failed(_ collection: String, message: String) {
        fromCache[collection] = nil
        failed[collection] = message
        attempts[collection, default: 0] += 1
    }

    /// How long to wait before re-attaching a failed collection's listener: 2s, 4s, 8s… up to a minute.
    func retryDelay(for collection: String) -> Duration {
        let attempt = max(attempts[collection] ?? 1, 1)
        return .seconds(min(2 << min(attempt - 1, 5), 60))
    }

    /// Failed while any collection's listener is down, then loading until every collection has
    /// answered, then offline if any answer came from the cache.
    var status: FinanceSync.Status {
        if let down = collections.first(where: { failed[$0] != nil }), let message = failed[down] {
            return .failed(message)
        }
        guard collections.allSatisfy({ fromCache[$0] != nil }) else { return .loading }
        return collections.contains { fromCache[$0] == true } ? .offline : .live
    }
}
