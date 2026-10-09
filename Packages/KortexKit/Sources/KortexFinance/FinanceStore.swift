import Foundation
import Observation

/// Where the synced data stands, for the sidebar's status line.
public enum FinanceStatus: Equatable, Sendable {
    case idle
    /// Waiting for the first answer from every collection.
    case loading
    /// Everything is current with the server.
    case live
    /// Showing Firestore's cached copy; the server can't be reached.
    case offline
    case failed(String)
}

/// What the screens and sheets read and write through. `KortexCloud.FinanceSync` is the real one, on
/// Firestore; `PreviewFinanceStore` keeps everything in memory, for previews and tests.
@MainActor
public protocol FinanceStore: AnyObject, Observable {
    var data: FinanceData { get }
    var status: FinanceStatus { get }
    /// Why the last write didn't go through, for the window to show.
    var writeError: String? { get }

    /// Commits a change from the write rules, or hands back why the rules refused it.
    @discardableResult
    func apply(_ result: Result<Change, FinanceError>) -> FinanceError?
    /// The key that seals full numbers, for `AccountRules.add` / `update` with a full number.
    func dataKey() async throws -> DataKey
    /// An account's full number, opened. Nil when none is kept.
    func revealNumber(of accountUid: String) async throws -> String?
    /// Reset data: every finance record deleted, built-in categories aside.
    func eraseAll() async throws
}

/// A `FinanceStore` in memory: changes land in `data` straight away, as the listeners would bring
/// them back. Full numbers are kept as sealed, and opened with `key`.
@MainActor
@Observable
public final class PreviewFinanceStore: FinanceStore {
    public private(set) var data: FinanceData
    public var status: FinanceStatus = .live
    public var writeError: String?
    /// Every change applied, oldest first.
    public private(set) var changes: [Change] = []

    @ObservationIgnored private let key: DataKey
    @ObservationIgnored private var secrets: [String: SealedSecret] = [:]

    public init(_ data: FinanceData = FinanceData()) {
        self.data = data
        key = DataKey(userUid: "preview", bytes: Data(repeating: 7, count: 32), version: 1)!
    }

    @discardableResult
    public func apply(_ result: Result<Change, FinanceError>) -> FinanceError? {
        switch result {
        case .failure(let error):
            return error
        case .success(let change):
            changes.append(change)
            data.apply(change)
            for write in change.writes {
                if case .secret(let uid, let sealed, _) = write { secrets[uid] = sealed }
                if case .delete(.secrets, let uid, _) = write { secrets[uid] = nil }
            }
            return nil
        }
    }

    public func dataKey() async throws -> DataKey { key }

    public func revealNumber(of accountUid: String) async throws -> String? {
        secrets[accountUid].flatMap { SecretBox.open($0, accountUid: accountUid, key: key) }
    }

    public func eraseAll() async throws {
        data = FinanceData()
        secrets = [:]
    }

    /// A bank account with a few entries this month, added through the write rules.
    public static func sample() -> PreviewFinanceStore {
        let store = PreviewFinanceStore()
        store.apply(AccountRules.add(AccountDraft(kind: .bank, name: "HDFC Savings", last4: "4821", openingMinor: 14_500_000), in: store.data))
        guard let bank = store.data.moneyAccounts.first?.uid else { return store }
        let entries = [
            TransactionDraft(type: .income, amountMinor: 9_500_000, accountUid: bank, categoryUid: BuiltInCategories.salary.uid, merchant: "Acme Corp"),
            TransactionDraft(type: .expense, amountMinor: 245_000, accountUid: bank, categoryUid: BuiltInCategories.food.uid, merchant: "Swiggy"),
            TransactionDraft(type: .expense, amountMinor: 1_200_000, accountUid: bank, categoryUid: BuiltInCategories.travel.uid, merchant: "IndiGo"),
            TransactionDraft(type: .expense, amountMinor: 389_900, accountUid: bank, categoryUid: BuiltInCategories.utilities.uid, merchant: "Tata Power"),
        ]
        for draft in entries { store.apply(EntryRules.add(draft, in: store.data)) }
        store.changes = []
        return store
    }
}
