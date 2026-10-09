import FirebaseFirestore
import KortexFinance
import Observation

/// Read-only finance sync: a live listener on each `users/{uid}/fin*` collection, folded into one
/// `FinanceData`. Firestore's persistent cache is the local store, so the last synced data shows
/// straight away (and offline) and the phone's writes arrive as they happen.
///
/// finSecrets isn't listened to: a full number is read only when asked for (`revealNumber`).
@MainActor
@Observable
public final class FinanceSync: FinanceStore {
    public typealias Status = FinanceStatus

    public private(set) var data = FinanceData()
    public private(set) var status: Status = .idle

    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]
    /// Re-attaches waiting out their backoff, per collection.
    @ObservationIgnored private var retries: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var userUid: String?
    @ObservationIgnored private var health = SyncHealth(collections: FinanceSync.collections)

    private static let collections = ["finCategories", "finAccounts", "finStatements", "finRecurring", "finMerchants", "finTransactions"]

    public init() {}

    public func start(userUid uid: String) {
        guard uid != userUid else { return }
        stop()
        userUid = uid
        status = .loading
        for name in Self.collections {
            listen(to: name, uid: uid)
        }
    }

    private func listen(to name: String, uid: String) {
        let collection = Firestore.firestore().collection("users").document(uid).collection(name)
        listeners[name] = collection.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            // Firestore calls back on the main queue.
            MainActor.assumeIsolated {
                guard let self, self.userUid == uid else { return }
                if let error {
                    self.listenerFailed(name, uid: uid, error: error)
                    return
                }
                if let snapshot { self.received(snapshot, collection: name) }
            }
        }
    }

    /// Firestore ends a listener for good once it reports an error, so drop it and attach a new one
    /// after a backoff. The collection counts as failed until the new one delivers a snapshot.
    private func listenerFailed(_ name: String, uid: String, error: Error) {
        listeners.removeValue(forKey: name)?.remove()
        health.failed(name, message: error.localizedDescription)
        updateStatus()
        let delay = health.retryDelay(for: name)
        retries[name]?.cancel()
        retries[name] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.userUid == uid else { return }
            self.retries[name] = nil
            self.listen(to: name, uid: uid)
        }
    }

    /// Why the last write didn't reach Firestore, for the window to show. Writes made offline wait
    /// in Firestore's queue rather than failing, so this is for real refusals (rules, quota).
    public private(set) var writeError: String?

    /// Commits a change as one batch. It shows here straight away, through the listeners; the server
    /// gets it when it can, and the phone pulls it from there.
    @discardableResult
    public func apply(_ result: Result<Change, FinanceError>) -> FinanceError? {
        switch result {
        case .failure(let error):
            return error
        case .success(let change):
            write(change)
            return nil
        }
    }

    public func write(_ change: Change) {
        guard let uid = userUid, !change.writes.isEmpty else { return }
        let db = Firestore.firestore()
        let user = db.collection("users").document(uid)
        // Firestore caps a batch at 500 writes; deleting a big category can move more entries than that.
        for chunk in stride(from: 0, to: change.writes.count, by: 450).map({ Array(change.writes[$0..<min($0 + 450, change.writes.count)]) }) {
            let batch = db.batch()
            for write in chunk {
                let doc = FinanceDocWriter.document(write, serverTime: FieldValue.serverTimestamp())
                batch.setData(doc.fields, forDocument: user.collection(doc.collection.rawValue).document(doc.uid), merge: true)
            }
            batch.commit { [weak self] error in
                guard let error else { return }
                MainActor.assumeIsolated { self?.writeError = error.localizedDescription }
            }
        }
        writeError = nil
    }

    /// The key that seals full numbers, for `AccountRules.add` / `update` with a full number.
    public func dataKey() async throws -> DataKey {
        guard let uid = userUid else { throw FinanceKeyError.signedOut }
        return try await FinanceKeys.key(for: uid)
    }

    /// An account's full number, read from finSecrets and opened here. Nil when none is kept.
    public func revealNumber(of accountUid: String) async throws -> String? {
        guard let uid = userUid else { throw FinanceKeyError.signedOut }
        let doc = Firestore.firestore().collection("users").document(uid).collection(FinCollection.secrets.rawValue).document(accountUid)
        let snapshot = try await doc.getDocument()
        guard let fields = snapshot.data(), case .live(let sealed)? = FinanceDocs.secret(uid: accountUid, fields) else { return nil }
        guard let number = SecretBox.open(sealed, accountUid: accountUid, key: try await dataKey()) else { throw FinanceKeyError.unreadable }
        return number
    }

    /// Reset data: marks every finance document deleted, finSecrets and finBudgets included (which
    /// aren't listened to), so the phone erases them too on its next sync. Reads from the server when it can be reached.
    public func eraseAll() async throws {
        guard let uid = userUid else { return }
        let user = Firestore.firestore().collection("users").document(uid)
        var live: [(collection: FinCollection, uid: String)] = []
        for collection in FinCollection.allCases {
            let snapshot = try await user.collection(collection.rawValue).getDocuments()
            for doc in snapshot.documents where doc.get("deleted") as? Bool != true {
                live.append((collection, doc.documentID))
            }
        }
        guard userUid == uid else { return }
        write(ResetRules.eraseAll(live))
    }

    public func stop() {
        retries.values.forEach { $0.cancel() }
        retries = [:]
        listeners.values.forEach { $0.remove() }
        listeners = [:]
        userUid = nil
        health = SyncHealth(collections: Self.collections)
        data = FinanceData()
        status = .idle
    }

    private func received(_ snapshot: QuerySnapshot, collection: String) {
        let changes = snapshot.documentChanges
        if !changes.isEmpty {
            apply(changes, collection: collection)
        }
        health.received(collection, fromCache: snapshot.metadata.isFromCache)
        updateStatus()
    }

    private func updateStatus() {
        // @Observable invalidates readers on every set, even of the same value.
        let next = health.status
        if status != next { status = next }
    }

    private func apply(_ changes: [DocumentChange], collection: String) {
        func rows<Row>(_ read: (String, [String: Any]) -> RemoteRow<Row>?) -> [RemoteRow<Row>] {
            changes.compactMap { change in
                // Android never removes finance documents (deletes are markers), but treat a removal as one.
                if change.type == .removed { return .deleted(uid: change.document.documentID) }
                return read(change.document.documentID, change.document.data())
            }
        }
        switch collection {
        case "finCategories": data.apply(rows(FinanceDocs.category))
        case "finAccounts": data.apply(rows(FinanceDocs.account))
        case "finStatements": data.apply(rows(FinanceDocs.statement))
        case "finRecurring": data.apply(rows(FinanceDocs.recurring))
        case "finMerchants": data.apply(rows(FinanceDocs.merchant))
        case "finTransactions": data.apply(rows(FinanceDocs.transaction))
        default: break
        }
    }
}
