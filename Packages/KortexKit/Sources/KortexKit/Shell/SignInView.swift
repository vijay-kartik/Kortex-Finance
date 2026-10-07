import KortexCloud
import SwiftUI

/// Shown whenever no one is signed in: Kortex has no signed-out mode.
struct SignInView: View {
    let session: CloudSession

    var body: some View {
        ZStack {
            Color.kVoid.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Kortex")
                    .font(.grotesk(40, .bold))
                    .foregroundStyle(Color.kInk)
                Text("Sign in with the Google account you use on your phone.\nYour finances sync here as you add them there.")
                    .font(.grotesk(14))
                    .foregroundStyle(Color.kMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                Button {
                    Task { await session.signIn() }
                } label: {
                    HStack(spacing: 8) {
                        if session.state == .signingIn {
                            ProgressView().controlSize(.small).tint(Color.kVoid)
                        }
                        Text(session.state == .signingIn ? "Waiting for Google…" : "Continue with Google")
                            .font(.grotesk(14, .medium))
                    }
                    .foregroundStyle(Color.kVoid)
                    .padding(.horizontal, 22)
                    .frame(height: 38)
                    .background(Color.kSynapse, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(session.state == .signingIn)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)

                if let error = session.signInError {
                    Text(error)
                        .font(.grotesk(12))
                        .foregroundStyle(Color.kAlarm)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(40)
        }
    }
}
