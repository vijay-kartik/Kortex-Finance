import CryptoKit
import Foundation

/// The signed-in user's data key from the `financeKey` function: one 256-bit key per user, the same
/// on every device, and the version that seals with it.
public struct DataKey: Sendable, Equatable {
    public let userUid: String
    public let bytes: Data
    public let version: Int

    /// Nil unless `bytes` is a 256-bit key.
    public init?(userUid: String, bytes: Data, version: Int) {
        guard bytes.count == 32 else { return nil }
        self.userUid = userUid
        self.bytes = bytes
        self.version = version
    }
}

/// A full card or account number as stored and synced in finSecrets: cipher text only.
public struct SealedSecret: Sendable, Equatable {
    public let cipherText: String
    public let keyVersion: Int

    public init(cipherText: String, keyVersion: Int) {
        self.cipherText = cipherText
        self.keyVersion = keyVersion
    }
}

/// kortex's KeystoreSecretBox: AES-256-GCM under the user's data key, bound to the account's uid as
/// associated data so one account's number can't be moved onto another. Tink's AesGcmJce lays the
/// sealed bytes out as CryptoKit's `combined` does (12-byte nonce, cipher text, 16-byte tag), so
/// the phone and the Mac read each other's.
public enum SecretBox {
    public static func seal(_ plain: String, accountUid: String, key: DataKey) -> SealedSecret? {
        guard let box = try? AES.GCM.seal(Data(plain.utf8), using: SymmetricKey(data: key.bytes), authenticating: associatedData(accountUid)),
              let combined = box.combined else { return nil }
        return SealedSecret(cipherText: combined.base64EncodedString(), keyVersion: key.version)
    }

    /// Nil when it can't be read with this key: another version, another account, or tampered.
    public static func open(_ sealed: SealedSecret, accountUid: String, key: DataKey) -> String? {
        guard sealed.keyVersion == key.version,
              let data = Data(base64Encoded: sealed.cipherText),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key.bytes), authenticating: associatedData(accountUid))
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    static func associatedData(_ accountUid: String) -> Data {
        Data("kortex.finance.secret:\(accountUid)".utf8)
    }
}

/// kortex's AccountNumbers.
public enum AccountNumbers {
    /// Digits only, spaces and dashes dropped; nil when not given; refused when it can't be a card
    /// or account number (8 to 19 digits).
    public static func clean(_ raw: String?) -> Result<String?, FinanceError> {
        let digits = (raw ?? "").filter { !$0.isWhitespace && $0 != "-" }
        if digits.isEmpty { return .success(nil) }
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), (8...19).contains(digits.count) else { return .failure(.invalidNumber) }
        return .success(digits)
    }

    /// "4111 1111 1111 1111": groups of four, for showing a revealed number.
    public static func grouped(_ number: String) -> String {
        stride(from: 0, to: number.count, by: 4).map { i in
            let start = number.index(number.startIndex, offsetBy: i)
            return String(number[start..<(number.index(start, offsetBy: 4, limitedBy: number.endIndex) ?? number.endIndex)])
        }.joined(separator: " ")
    }
}
