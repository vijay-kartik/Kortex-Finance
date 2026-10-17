import AppKit
import FirebaseAuth
import GoogleSignIn
import KortexFinance
import Observation

/// Sign-in state for the whole app, plus the finance sync that runs while someone is signed in.
/// Kortex can't be used signed out, so the window shows sign-in until `user` is set.
@MainActor
@Observable
public final class CloudSession: Session {
    /// `.starting` until Firebase says whether a user is restored from the keychain.
    public private(set) var state: SessionState = .starting
    public private(set) var signInError: String?
    private let sync = FinanceSync()
    public var finance: any FinanceStore { sync }

    @ObservationIgnored private var authListener: AuthStateDidChangeListenerHandle?

    public init() {}

    /// Starts following Firebase Auth. Call once, after `Cloud.configure()`.
    public func start() {
        guard authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.authChanged(user) }
        }
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

    public var appCheckToken: String? { Cloud.appCheckDebugToken }

    /// Against this session's user, the one `finance` syncs.
    public func checkFinanceKey() async throws {
        guard let uid = user?.uid else { throw FinanceKeyError.signedOut }
        try await FinanceKeys.check(userUid: uid)
    }

    private func authChanged(_ firebaseUser: User?) {
        guard let firebaseUser else {
            sync.stop()
            // Keep the sign-in sheet's own state while a sign-in is under way.
            if state != .signingIn { state = .signedOut }
            return
        }
        let user = SessionUser(uid: firebaseUser.uid, displayName: firebaseUser.displayName, email: firebaseUser.email)
        state = .signedIn(user)
        sync.start(userUid: user.uid)
    }

    private enum SignInFailure: LocalizedError {
        case noIdToken
        var errorDescription: String? { "Google didn't return an ID token. Try again." }
    }
}
