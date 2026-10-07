import Foundation

/// A pulled document: either a live record or a delete marker. Android merges `deleted: true` over a
/// record's document rather than removing it, so deletes arrive as ordinary documents.
public enum RemoteRow<Row: Sendable>: Sendable {
    case live(Row)
    case deleted(uid: String)
}

/// Reads the finance documents under `users/{uid}/fin*`, field for field as kortex's
/// sync/finance/FinanceDocs.kt reads them. Each returns nil for a document it can't apply (no
/// `updatedAt`, or a live record missing what it needs, or an enum value only a newer app knows).
public enum FinanceDocs {
    public typealias Fields = [String: Any]

    public static func account(uid: String, _ d: Fields) -> RemoteRow<Account>? {
        read(uid, d) { updatedAt in
            guard let kind = d.enumValue("kind", AccountKind.self), let name = d.text("name") else { return nil }
            return Account(
                uid: uid,
                kind: kind,
                name: name,
                institution: d.text("institution"),
                last4: d.text("last4"),
                hasSecret: d.bool("hasSecret"),
                bankType: d.enumValue("bankType", BankType.self),
                ifsc: d.text("ifsc"),
                linkedAccountUid: d.text("linkedAccountUid"),
                network: d.text("network"),
                expiry: d.text("expiry"),
                holder: d.text("holder"),
                creditLimitMinor: d.long("creditLimitMinor"),
                statementDay: d.long("statementDay").map(Int.init),
                dueDay: d.long("dueDay").map(Int.init),
                colorToken: d.text("colorToken"),
                archived: d.bool("archived"),
                createdAtMillis: d.long("createdAt") ?? updatedAt,
                updatedAtMillis: updatedAt
            )
        }
    }

    public static func transaction(uid: String, _ d: Fields) -> RemoteRow<Transaction>? {
        read(uid, d) { updatedAt in
            guard let type = d.enumValue("type", TransactionType.self),
                  let amount = d.long("amountMinor"), amount > 0,
                  let occurredAt = d.long("occurredAt"),
                  let occurredOn = d.day("occurredOn"),
                  let accountUid = d.text("accountUid")
            else { return nil }
            return Transaction(
                uid: uid,
                type: type,
                amountMinor: amount,
                currency: d.text("currency") ?? "INR",
                occurredAtMillis: occurredAt,
                occurredOn: occurredOn,
                accountUid: accountUid,
                toAccountUid: d.text("toAccountUid"),
                categoryUid: d.text("categoryUid"),
                merchant: d.text("merchant"),
                payeeKey: d.text("payeeKey"),
                note: d.text("note"),
                source: d.enumValue("source", TransactionSource.self) ?? .manual,
                sourceRef: d.text("sourceRef"),
                recurringUid: d.text("recurringUid"),
                dueOn: d.day("dueOn"),
                statementUid: d.text("statementUid"),
                receipt: receipt(d["receipt"] as? Fields),
                createdAtMillis: d.long("createdAt") ?? updatedAt,
                updatedAtMillis: updatedAt
            )
        }
    }

    public static func category(uid: String, _ d: Fields) -> RemoteRow<Category>? {
        read(uid, d) { updatedAt in
            guard let name = d.text("name"), let kind = d.enumValue("kind", CategoryKind.self) else { return nil }
            return Category(
                uid: uid,
                name: name,
                kind: kind,
                colorToken: d.text("colorToken") ?? "Synapse",
                builtIn: false,
                sortOrder: d.long("sortOrder").map(Int.init) ?? 0,
                createdAtMillis: d.long("createdAt") ?? updatedAt,
                updatedAtMillis: updatedAt
            )
        }
    }

    public static func recurring(uid: String, _ d: Fields) -> RemoteRow<Recurring>? {
        read(uid, d) { updatedAt in
            guard let name = d.text("name"),
                  let kind = d.enumValue("kind", RecurringKind.self),
                  let amount = d.long("amountMinor"), amount > 0,
                  let frequency = d.enumValue("frequency", Frequency.self),
                  let anchorDay = d.long("anchorDay"),
                  let nextDueOn = d.day("nextDueOn"),
                  let accountUid = d.text("accountUid")
            else { return nil }
            return Recurring(
                uid: uid,
                name: name,
                kind: kind,
                amountMinor: amount,
                currency: d.text("currency") ?? "INR",
                frequency: frequency,
                interval: max(1, d.long("interval").map(Int.init) ?? 1),
                anchorDay: Int(anchorDay),
                nextDueOn: nextDueOn,
                accountUid: accountUid,
                categoryUid: d.text("categoryUid"),
                remindDaysBefore: d.long("remindDaysBefore").map(Int.init) ?? -1,
                autoMarkPaid: d.bool("autoMarkPaid"),
                paused: d.bool("paused"),
                createdAtMillis: d.long("createdAt") ?? updatedAt,
                updatedAtMillis: updatedAt
            )
        }
    }

    public static func statement(uid: String, _ d: Fields) -> RemoteRow<CardStatement>? {
        read(uid, d) { updatedAt in
            guard let cardUid = d.text("cardUid"),
                  let periodStart = d.day("periodStart"),
                  let statementOn = d.day("statementOn"),
                  let dueOn = d.day("dueOn"),
                  let total = d.long("totalDueMinor")
            else { return nil }
            return CardStatement(
                uid: uid,
                cardUid: cardUid,
                periodStart: periodStart,
                statementOn: statementOn,
                dueOn: dueOn,
                totalDueMinor: total,
                minDueMinor: d.long("minDueMinor") ?? 0,
                source: d.enumValue("source", StatementSource.self) ?? .auto,
                createdAtMillis: d.long("createdAt") ?? updatedAt,
                updatedAtMillis: updatedAt
            )
        }
    }

    public static func merchant(uid: String, _ d: Fields) -> RemoteRow<Merchant>? {
        read(uid, d) { updatedAt in
            guard let payeeKey = d.text("payeeKey"), let displayName = d.text("displayName") else { return nil }
            return Merchant(uid: uid, payeeKey: payeeKey, displayName: displayName, categoryUid: d.text("categoryUid"), updatedAtMillis: updatedAt)
        }
    }

    /// finSecrets: read only to show a number, never listened to.
    public static func secret(uid: String, _ d: Fields) -> RemoteRow<SealedSecret>? {
        read(uid, d) { _ in
            guard let cipherText = d.text("cipherText"), let version = d.long("keyVersion") else { return nil }
            return SealedSecret(cipherText: cipherText, keyVersion: Int(version))
        }
    }

    /// A delete needs nothing but `updatedAt`; a live record is built by `build`, nil when malformed.
    private static func read<Row>(_ uid: String, _ d: Fields, build: (Int64) -> Row?) -> RemoteRow<Row>? {
        guard let updatedAt = d.long("updatedAt") else { return nil }
        if d["deleted"] as? Bool == true { return .deleted(uid: uid) }
        return build(updatedAt).map(RemoteRow.live)
    }

    private static func receipt(_ r: Fields?) -> Receipt? {
        guard let r, let count = r.long("itemCount") else { return nil }
        let items = (r["items"] as? [Any] ?? []).compactMap { $0 as? Fields }.map { item in
            ReceiptItem(
                name: item["name"] as? String ?? "",
                quantity: item.long("qty").map(Int.init) ?? 1,
                amountMinor: item.long("amountMinor") ?? 0
            )
        }
        let photo = r["photo"] as? Fields
        return Receipt(
            itemCount: Int(count),
            items: items,
            taxMinor: r.long("taxMinor"),
            photoDevicePath: photo?.text("devicePath"),
            photoMimeType: photo?.text("mimeType")
        )
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// Numbers written from JavaScript can arrive as doubles.
    func long(_ key: String) -> Int64? {
        switch self[key] {
        case let n as NSNumber where !(n === kCFBooleanTrue || n === kCFBooleanFalse): n.int64Value
        case let n as Int64: n
        case let n as Int: Int64(n)
        case let n as Double: Int64(n)
        default: nil
        }
    }

    func text(_ key: String) -> String? {
        guard let s = self[key] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    func bool(_ key: String) -> Bool { self[key] as? Bool ?? false }

    func enumValue<E: RawRepresentable>(_ key: String, _: E.Type) -> E? where E.RawValue == String {
        text(key).flatMap(E.init(rawValue:))
    }

    func day(_ key: String) -> LocalDay? { text(key).flatMap(LocalDay.init) }
}
