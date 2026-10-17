import Foundation
import Observation

/// The signed-in Google account.
public struct SessionUser: Sendable, Equatable {
    public let uid: String
    public let displayName: String?
    public let email: String?

    public init(uid: String, displayName: String?, email: String?) {
        self.uid = uid
        self.displayName = displayName
        self.email = email
    }

    /// "AM" for Aarav Mehta; the email's first letter without a name.
    public var initials: String {
        let words = (displayName ?? "").split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(email?.first ?? "?").uppercased() : letters.uppercased()
    }
}

public enum SessionState: Equatable, Sendable {
    /// It isn't known yet whether a user is restored from the keychain.
    case starting
    case signedOut
    case signingIn
    case signedIn(SessionUser)
}

/// Sign-in state for the whole app, and the store that's synced while someone is signed in. The
/// window and Settings only see this; `KortexCloud.CloudSession` is the real one, on Firebase, and
/// `PreviewSession` keeps everything in memory, for previews and tests.
@MainActor
public protocol Session: AnyObject, Observable {
    var state: SessionState { get }
    /// Why the last sign-in failed, in words for the sign-in screen. Cleared on the next attempt.
    var signInError: String? { get }
    var finance: any FinanceStore { get }

    func signIn() async
    func signOut()
    /// This Mac's App Check debug token, for Settings › Account Numbers. Nil before Firebase is set up.
    var appCheckToken: String? { get }
    /// Fetches the signed-in user's data key from the server even when one is kept, to check this
    /// Mac passes App Check.
    func checkFinanceKey() async throws
}

extension Session {
    public var user: SessionUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }
}

/// A `Session` in memory: signing in signs `previewUser` in straight away.
@MainActor
@Observable
public final class PreviewSession: Session {
    public var state: SessionState
    public var signInError: String?
    public var appCheckToken: String?
    /// What Check throws; nil passes.
    public var checkFailure: (any Error)?
    /// Checks made, for tests.
    public private(set) var checks = 0
    @ObservationIgnored public let finance: any FinanceStore

    nonisolated public static let previewUser = SessionUser(uid: "preview", displayName: "Aarav Mehta", email: "aarav@example.com")

    public init(_ state: SessionState = .signedIn(PreviewSession.previewUser), finance: any FinanceStore,
                appCheckToken: String? = "00000000-0000-0000-0000-000000000000") {
        self.state = state
        self.finance = finance
        self.appCheckToken = appCheckToken
    }

    public func signIn() async {
        signInError = nil
        state = .signedIn(Self.previewUser)
    }

    public func signOut() {
        state = .signedOut
    }

    public func checkFinanceKey() async throws {
        checks += 1
        if let checkFailure { throw checkFailure }
    }
}
