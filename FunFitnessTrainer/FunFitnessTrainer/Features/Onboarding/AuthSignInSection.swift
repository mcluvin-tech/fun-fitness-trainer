import SwiftUI

struct AuthSignInSection: View {
    @StateObject private var appleSignIn = SignInWithAppleHelper()
    @StateObject private var googleSignIn = OAuthSignInHelper()
    @StateObject private var phoneSignIn = PhoneSignInHelper()
    @StateObject private var supabase = SupabaseService.shared

    var body: some View {
        VStack(spacing: 14) {
            if supabase.isSignedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if AppConfig.supportsSignInWithApple {
                    AppleSignInButton(helper: appleSignIn)
                        .cornerRadius(10)
                }

                Button {
                    googleSignIn.signInWithGoogle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                        Text("Continue with Gmail")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .disabled(!AppConfig.hasBackend || googleSignIn.isLoading || appleSignIn.isLoading)

                Button {
                    phoneSignIn.present()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                        Text("Continue with Phone Number")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .disabled(!AppConfig.hasBackend || phoneSignIn.isLoading || appleSignIn.isLoading)

                if googleSignIn.isLoading || phoneSignIn.isLoading || appleSignIn.isLoading {
                    ProgressView()
                }

                if !AppConfig.hasBackend {
                    Text("Sign-in syncs when Supabase is configured. You can still build your plan below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let err = appleSignIn.errorMessage ?? googleSignIn.errorMessage ?? phoneSignIn.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $phoneSignIn.showSheet) {
            PhoneSignInSheet(helper: phoneSignIn)
        }
    }
}
