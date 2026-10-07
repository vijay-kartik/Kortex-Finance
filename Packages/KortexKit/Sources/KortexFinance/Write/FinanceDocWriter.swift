import Foundation

/// Finance documents as kortex's sync/finance/FinanceDocs.kt writes them. Every field is written,
/// null or not, so a merge clears what a record no longer has; times are millis, dates `yyyy-MM-dd`.
/// `serverTime` is Firestore's server timestamp sentinel, a parameter so these stay testable.
public enum FinanceDocWriter {
    public struct Document {
        public let collection: FinCollection
        public let uid: String
        public let fields: [String: Any]
    }

    public static func document(_ write: RecordWrite, serverTime: Any) -> Document {
        switch write {
        case .account(let a): Document(collection: .accounts, uid: a.uid, fields: account(a, serverTime))
        case .transaction(let t): Document(collection: .transactions, uid: t.uid, fields: transaction(t, serverTime))
        case .category(let c): Document(collection: .categories, uid: c.uid, fields: category(c, serverTime))
        case .recurring(let r): Document(collection: .recurring, uid: r.uid, fields: recurring(r, serverTime))
        case .statement(let s): Document(collection: .statements, uid: s.uid, fields: statement(s, serverTime))
        case .merchant(let m): Document(collection: .merchants, uid: m.uid, fields: merchant(m, serverTime))
        case .secret(let uid, let sealed, let at): Document(collection: .secrets, uid: uid, fields: secret(sealed, at, serverTime))
        case .delete(let collection, let uid, let at):
            // Merged over the document; the rest of its fields stay for whoever still has it.
            Document(collection: collection, uid: uid, fields: ["updatedAt": at, "serverUpdatedAt": serverTime, "deleted": true])
        }
    }

    /// Cipher text and the key version that sealed it, nothing else: a separate collection, so lists
    /// and the browser extension never read it.
    static func secret(_ s: SealedSecret, _ updatedAt: Int64, _ serverTime: Any) -> [String: Any] {
        ["cipherText": s.cipherText, "keyVersion": s.keyVersion, "updatedAt": updatedAt, "serverUpdatedAt": serverTime, "deleted": false]
    }

    static func account(_ a: Account, _ serverTime: Any) -> [String: Any] {
        [
            "kind": a.kind.rawValue,
            "name": a.name,
            "institution": a.institution ?? NSNull(),
            "last4": a.last4 ?? NSNull(),
            "hasSecret": a.hasSecret,
            "bankType": a.bankType?.rawValue ?? NSNull(),
            "ifsc": a.ifsc ?? NSNull(),
            "linkedAccountUid": a.linkedAccountUid ?? NSNull(),
            "network": a.network ?? NSNull(),
            "expiry": a.expiry ?? NSNull(),
            "holder": a.holder ?? NSNull(),
            "creditLimitMinor": a.creditLimitMinor ?? NSNull(),
            "statementDay": a.statementDay ?? NSNull(),
            "dueDay": a.dueDay ?? NSNull(),
            "colorToken": a.colorToken ?? NSNull(),
            "archived": a.archived,
        ].merging(meta(a.createdAtMillis, a.updatedAtMillis, serverTime)) { $1 }
    }

    static func transaction(_ t: Transaction, _ serverTime: Any) -> [String: Any] {
        let receipt: Any = t.receipt.map { r -> [String: Any] in
            [
                "itemCount": r.itemCount,
                "items": r.items.map { ["name": $0.name, "qty": $0.quantity, "amountMinor": $0.amountMinor] as [String: Any] },
                "taxMinor": r.taxMinor ?? NSNull(),
                "photo": r.photoDevicePath.map { ["devicePath": $0, "mimeType": r.photoMimeType ?? NSNull()] as [String: Any] } ?? NSNull(),
            ]
        } ?? NSNull()
        return [
            "type": t.type.rawValue,
            "amountMinor": t.amountMinor,
            "currency": t.currency,
            "occurredAt": t.occurredAtMillis,
            "occurredOn": t.occurredOn.description,
            "accountUid": t.accountUid,
            "toAccountUid": t.toAccountUid ?? NSNull(),
            "categoryUid": t.categoryUid ?? NSNull(),
            "merchant": t.merchant ?? NSNull(),
            "payeeKey": t.payeeKey ?? NSNull(),
            "note": t.note ?? NSNull(),
            "source": t.source.rawValue,
            "sourceRef": t.sourceRef ?? NSNull(),
            "recurringUid": t.recurringUid ?? NSNull(),
            "dueOn": t.dueOn?.description ?? NSNull(),
            "statementUid": t.statementUid ?? NSNull(),
            "receipt": receipt,
        ].merging(meta(t.createdAtMillis, t.updatedAtMillis, serverTime)) { $1 }
    }

    static func category(_ c: Category, _ serverTime: Any) -> [String: Any] {
        ["name": c.name, "kind": c.kind.rawValue, "colorToken": c.colorToken, "sortOrder": c.sortOrder]
            .merging(meta(c.createdAtMillis, c.updatedAtMillis, serverTime)) { $1 }
    }

    static func recurring(_ r: Recurring, _ serverTime: Any) -> [String: Any] {
        [
            "name": r.name,
            "kind": r.kind.rawValue,
            "amountMinor": r.amountMinor,
            "currency": r.currency,
            "frequency": r.frequency.rawValue,
            "interval": r.interval,
            "anchorDay": r.anchorDay,
            "nextDueOn": r.nextDueOn.description,
            "accountUid": r.accountUid,
            "categoryUid": r.categoryUid ?? NSNull(),
            "remindDaysBefore": r.remindDaysBefore,
            "autoMarkPaid": r.autoMarkPaid,
            "paused": r.paused,
        ].merging(meta(r.createdAtMillis, r.updatedAtMillis, serverTime)) { $1 }
    }

    static func statement(_ s: CardStatement, _ serverTime: Any) -> [String: Any] {
        [
            "cardUid": s.cardUid,
            "periodStart": s.periodStart.description,
            "statementOn": s.statementOn.description,
            "dueOn": s.dueOn.description,
            "totalDueMinor": s.totalDueMinor,
            "minDueMinor": s.minDueMinor,
            "source": s.source.rawValue,
        ].merging(meta(s.createdAtMillis, s.updatedAtMillis, serverTime)) { $1 }
    }

    /// No createdAt: the phone's merchant rows don't have one.
    static func merchant(_ m: Merchant, _ serverTime: Any) -> [String: Any] {
        [
            "payeeKey": m.payeeKey,
            "displayName": m.displayName,
            "categoryUid": m.categoryUid ?? NSNull(),
            "updatedAt": m.updatedAtMillis,
            "serverUpdatedAt": serverTime,
            "deleted": false,
        ]
    }

    private static func meta(_ createdAt: Int64, _ updatedAt: Int64, _ serverTime: Any) -> [String: Any] {
        ["createdAt": createdAt, "updatedAt": updatedAt, "serverUpdatedAt": serverTime, "deleted": false]
    }
}
