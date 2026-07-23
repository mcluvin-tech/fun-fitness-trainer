import AuthenticationServices
import Foundation

/// Google (and other Supabase OAuth providers) via in-app browser + deep link callback.
@MainActor
final class OAuthSignInHelper: NSObject, ObservableObject {
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var session: ASWebAuthenticationSession?

    func signInWithGoogle() {
        guard AppConfig.hasBackend else {
            errorMessage = "Connect Supabase in Secrets.plist to sign in with Google."
            return
        }
        Task { await performGoogleSignIn() }
    }

    private func performGoogleSignIn() async {
        errorMessage = nil
        isLoading = true
        defer { if session == nil { isLoading = false } }

        do {
            try await SupabaseService.shared.verifyOAuthProvider("google")
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        startOAuth(provider: "google")
    }

    private func startOAuth(provider: String) {
        guard let authURL = SupabaseService.shared.oauthAuthorizeURL(provider: provider) else {
            errorMessage = "Could not build sign-in URL."
            return
        }

        errorMessage = nil
        isLoading = true

        session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: AppConfig.oauthCallbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.isLoading = false
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    return
                }
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                guard let callbackURL else {
                    self?.errorMessage = "Sign-in was cancelled."
                    return
                }
                do {
                    try await SupabaseService.shared.handleOAuthCallback(url: callbackURL)
                } catch {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
        session?.prefersEphemeralWebBrowserSession = false
        session?.presentationContextProvider = self
        session?.start()
    }
}

extension OAuthSignInHelper: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.activePresentationAnchor
    }
}
