import FirebaseAuth
import FirebaseFunctions
import Foundation
import KortexFinance
import Security

/// The signed-in user's data key, which seals full card and account numbers. Fetched once from the
/// `financeKey` function (signed-in users calling from the Kortex app only: App Check), then kept in
/// this Mac's Keychain, as the phone keeps it wrapped by its Keystore.
public enum FinanceKeys {
    /// From the Keychain, else the server.
    public static func key(for userUid: String) async throws -> DataKey {
        if let stored = stored(userUid) { return stored }
        let fetched = try await fetch(userUid)
        store(fetched)
        return fetched
    }

    /// Fetches from the server even when a key is kept, to check this Mac passes App Check.
    public static func check() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw FinanceKeyError.signedOut }
        store(try await fetch(uid))
    }

    private static func fetch(_ userUid: String) async throws -> DataKey {
        let result: HTTPSCallableResult
        do {
            // Next to Firestore, as every Kortex function is.
            result = try await Functions.functions(region: "asia-south1").httpsCallable("financeKey").call()
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated, .permissionDenied: throw FinanceKeyError.refused
            case .unavailable, .deadlineExceeded: throw FinanceKeyError.offline
            default: throw error
            }
        }
        guard let data = result.data as? [String: Any],
              let base64 = data["key"] as? String, let bytes = Data(base64Encoded: base64),
              let key = DataKey(userUid: userUid, bytes: bytes, version: (data["keyVersion"] as? NSNumber)?.intValue ?? 1)
        else { throw FinanceKeyError.unreadable }
        return key
    }

    // MARK: Keychain

    private static let service = "dev.kortex.mac.finance-key"

    /// "version:base64", one item per user.
    private static func stored(_ userUid: String) -> DataKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: userUid,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let version = Int(parts[0]), let bytes = Data(base64Encoded: String(parts[1])) else { return nil }
        return DataKey(userUid: userUid, bytes: bytes, version: version)
    }

    private static func store(_ key: DataKey) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key.userUid]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData] = Data("\(key.version):\(key.bytes.base64EncodedString())".utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

public enum FinanceKeyError: LocalizedError {
    case signedOut
    /// App Check or sign-in was refused: the usual cause is a debug token not registered yet.
    case refused
    case offline
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .signedOut: "Sign in to Kortex first."
        case .refused: "Firebase didn't accept this Mac. Register its App Check debug token in Settings › Account Numbers."
        case .offline: "Couldn't reach Kortex's server. Check your connection and try again."
        case .unreadable: "The server's answer couldn't be read."
        }
    }
}
