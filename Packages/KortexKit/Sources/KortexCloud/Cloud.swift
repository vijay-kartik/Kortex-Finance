import AppKit
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

/// One-time Firebase setup. The app's `GoogleService-Info.plist` (registered for dev.kortex.mac in the
/// same Firebase project as Android) supplies the project and the Google OAuth client.
public enum Cloud {
    @MainActor public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        // App Check, which the `financeKey` function enforces. App Attest needs a paid Apple Developer
        // membership, so this Mac proves itself with a debug token registered in the Firebase console
        // (Settings › Account Numbers shows it). Switch to AppAttestProviderFactory for a shared build.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        FirebaseApp.configure()

        let settings = Firestore.firestore().settings
        // Firestore's on-disk cache is the Mac's local copy: it shows the last synced data offline.
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    /// This Mac's App Check debug token, made on first launch and kept in its defaults. Registered in
    /// Firebase › App Check › Apps › dev.kortex.mac › Manage debug tokens, it lets this Mac call `financeKey`.
    @MainActor public static var appCheckDebugToken: String? {
        FirebaseApp.app().flatMap(AppCheckDebugProvider.init(app:))?.currentDebugToken()
    }

    /// Hands the Google sign-in redirect back to GoogleSignIn. Call from `.onOpenURL`.
    @MainActor public static func handle(_ url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }
}
