/// Reset data: a clean slate for the signed-in user, on every device.
public enum ResetRules {
    /// Delete markers for every live finance document, rather than removing the documents: the phone
    /// pulls only what changed since its last sync, so it would never notice a removal (and would push
    /// its copy back). Built-in categories are fixed on every device and never erased.
    public static func eraseAll(_ live: [(collection: FinCollection, uid: String)], clock: FinanceClock = .system) -> Change {
        let builtIn = Set(BuiltInCategories.all.map(\.uid))
        let now = clock.nowMillis
        return Change(live.compactMap { doc in
            if doc.collection == .categories, builtIn.contains(doc.uid) { return nil }
            return .delete(doc.collection, uid: doc.uid, atMillis: now)
        })
    }
}
