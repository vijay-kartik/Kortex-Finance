import AppKit
import FirebaseAuth
import GoogleSignIn
import Observation

/// The signed-in Google account, as Firebase Auth reports it.
public struct CloudUser: Sendable, Equatable {
    public let uid: String
    public let displayName: String?
    public let email: String?

    /// "AM" for Aarav Mehta; the email's first letter without a name.
    public var initials: String {
        let words = (displayName ?? "").split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(email?.first ?? "?").uppercased() : letters.uppercased()
    }
}

/// Sign-in state for the whole app, plus the finance sync that runs while someone is signed in.
/// Kortex can't be used signed out, so the window shows sign-in until `user` is set.
@MainActor
@Observable
public final class CloudSession {
    public enum State: Equatable {
        /// Firebase hasn't said yet whether a user is restored from the keychain.
        case starting
        case signedOut
        case signingIn
        case signedIn(CloudUser)
    }

    public private(set) var state: State = .starting
    /// Why the last sign-in failed, in words for the sign-in screen. Cleared on the next attempt.
    public private(set) var signInError: String?
    public let finance = FinanceSync()

    @ObservationIgnored private var authListener: AuthStateDidChangeListenerHandle?

    public init() {}

    /// Starts following Firebase Auth. Call once, after `Cloud.configure()`.
    public func start() {
        guard authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.authChanged(user) }
        }
    }

    public var user: CloudUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    /// Google sign-in in a browser sheet, then Firebase sign-in with the Google credential.
    public func signIn() async {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        signInError = nil
        state = .signingIn
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            guard let idToken = result.user.idToken?.tokenString else {
                throw SignInFailure.noIdToken
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            // The auth listener moves state to signed in.
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            state = .signedOut
            if (error as NSError).domain == kGIDSignInErrorDomain, (error as NSError).code == GIDSignInError.canceled.rawValue {
                return
            }
            signInError = error.localizedDescription
        }
    }

    public func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    private func authChanged(_ firebaseUser: User?) {
        guard let firebaseUser else {
            finance.stop()
            // Keep the sign-in sheet's own state while a sign-in is under way.
            if state != .signingIn { state = .signedOut }
            return
        }
        let user = CloudUser(uid: firebaseUser.uid, displayName: firebaseUser.displayName, email: firebaseUser.email)
        state = .signedIn(user)
        finance.start(userUid: user.uid)
    }

    private enum SignInFailure: LocalizedError {
        case noIdToken
        var errorDescription: String? { "Google didn't return an ID token. Try again." }
    }
}
