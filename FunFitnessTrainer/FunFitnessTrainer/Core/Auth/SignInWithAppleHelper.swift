import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class SignInWithAppleHelper: NSObject, ObservableObject {
    @Published var errorMessage: String?
    @Published var isLoading = false
    private var currentNonce: String?
    /// `ASAuthorizationController` must be retained until the delegate fires.
    private var authorizationController: ASAuthorizationController?

    func signIn() {
        errorMessage = nil
        let nonce = randomNonceString()
        currentNonce = nonce
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller
        controller.performRequests()
    }

    /// Used by SwiftUI `SignInWithAppleButton`.
    func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            errorMessage = "Apple sign-in failed."
            return
        }
        exchangeAppleToken(idToken: idToken, nonce: nonce)
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func finishAuthorizationFlow() {
        authorizationController = nil
    }

    private func exchangeAppleToken(idToken: String, nonce: String) {
        guard AppConfig.hasBackend else {
            errorMessage = "Add Supabase keys in Secrets.plist to sync with Apple ID."
            return
        }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await SupabaseService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension SignInWithAppleHelper: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { finishAuthorizationFlow() }
        handleAuthorization(authorization)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finishAuthorizationFlow()
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return
        }
        if !AppConfig.supportsSignInWithApple {
            errorMessage =
                "Enable Sign in with Apple on your App ID in the Apple Developer portal, " +
                "then rebuild the app."
            return
        }
        errorMessage = error.localizedDescription
    }
}

extension SignInWithAppleHelper: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.activePresentationAnchor
    }
}

/// Native Apple button — use inside a `VStack` list row (not as its own `List` `Button` row).
struct AppleSignInButton: View {
    @ObservedObject var helper: SignInWithAppleHelper
    var height: CGFloat = 50

    var body: some View {
        ZStack {
            SignInWithAppleButton(.signIn) { request in
                helper.prepareAppleRequest(request)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    helper.handleAuthorization(authorization)
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == ASAuthorizationError.errorDomain,
                       nsError.code == ASAuthorizationError.canceled.rawValue {
                        return
                    }
                    helper.errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: height)
            .allowsHitTesting(!helper.isLoading)

            if helper.isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Sign in with Apple")
    }
}

extension UIApplication {
    /// Key window for `ASAuthorizationController` / `ASWebAuthenticationSession` sheets.
    static var activePresentationAnchor: UIWindow {
        let scenes = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let key = windows.first(where: \.isKeyWindow) {
            return key
        }
        if let first = windows.first {
            return first
        }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            let window = UIWindow(windowScene: scene)
            window.makeKeyAndVisible()
            return window
        }
        return UIWindow()
    }
}
