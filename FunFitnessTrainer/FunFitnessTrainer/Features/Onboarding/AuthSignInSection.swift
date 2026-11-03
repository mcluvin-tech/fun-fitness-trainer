import SwiftUI

struct AuthSignInSection: View {
    @StateObject private var appleSignIn = SignInWithAppleHelper()
    @StateObject private var googleSignIn = OAuthSignInHelper()
    @StateObject private var phoneSignIn = PhoneSignInHelper()
    @StateObject private var supabase = SupabaseService.shared
    @State private var showSignInSheet = false
    @State private var openPhoneAfterSignIn = false

    var body: some View {
        VStack(spacing: 8) {
            if supabase.isSignedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .font(OnboardingType.font(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(minHeight: 44)
            } else {
                providerButtons
                statusMessages
                accountLink
            }

            if let err = appleSignIn.errorMessage ?? googleSignIn.errorMessage ?? phoneSignIn.errorMessage {
                Text(err)
                    .font(OnboardingType.font(13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $phoneSignIn.showSheet) {
            PhoneSignInSheet(helper: phoneSignIn)
        }
        .sheet(isPresented: $showSignInSheet, onDismiss: {
            guard openPhoneAfterSignIn else { return }
            openPhoneAfterSignIn = false
            phoneSignIn.present()
        }) {
            SignInMethodsSheet(
                appleSignIn: appleSignIn,
                onGoogle: {
                    showSignInSheet = false
                    googleSignIn.signInWithGoogle()
                },
                onPhone: {
                    openPhoneAfterSignIn = true
                    showSignInSheet = false
                }
            )
        }
        .onChange(of: supabase.isSignedIn) { _, signedIn in
            if signedIn { showSignInSheet = false }
        }
    }

    private var providerButtons: some View {
        VStack(spacing: 8) {
            if AppConfig.supportsSignInWithApple {
                AppleSignInButton(helper: appleSignIn, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            OnboardingSecondaryButton(
                title: "Continue with Google",
                isDisabled: !AppConfig.hasBackend || googleSignIn.isLoading || appleSignIn.isLoading
            ) {
                googleSignIn.signInWithGoogle()
            } icon: {
                GoogleMark()
            }

            OnboardingSecondaryButton(
                title: "Continue with Phone",
                isDisabled: !AppConfig.hasBackend || phoneSignIn.isLoading || appleSignIn.isLoading
            ) {
                phoneSignIn.present()
            } icon: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if googleSignIn.isLoading || phoneSignIn.isLoading || appleSignIn.isLoading {
            ProgressView()
                .tint(BrandTheme.homeSecondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }

        if !AppConfig.hasBackend {
            Text("Sign-in syncs when Supabase is configured. You can still build your plan.")
                .font(OnboardingType.font(13, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var accountLink: some View {
        Button {
            showSignInSheet = true
        } label: {
            (Text("Already have an account? ")
                .font(OnboardingType.font(15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(BrandTheme.homeSecondaryText)
            + Text("Sign in")
                .font(OnboardingType.font(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(BrandTheme.homePrimaryText)
                .underline())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

private struct SignInMethodsSheet: View {
    @ObservedObject var appleSignIn: SignInWithAppleHelper
    var onGoogle: () -> Void
    var onPhone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Use the Google account or phone number you already signed up with.")
                    .font(OnboardingType.font(15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)

                if AppConfig.supportsSignInWithApple {
                    AppleSignInButton(helper: appleSignIn, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                OnboardingSecondaryButton(title: "Continue with Google", isDisabled: !AppConfig.hasBackend || appleSignIn.isLoading) {
                    onGoogle()
                } icon: {
                    GoogleMark()
                }

                OnboardingSecondaryButton(title: "Continue with Phone", isDisabled: !AppConfig.hasBackend || appleSignIn.isLoading) {
                    onPhone()
                } icon: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { HomeDarkBackground() }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(BrandTheme.homePrimaryText)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

struct OnboardingSecondaryButton<Icon: View>: View {
    let title: String
    var isDisabled = false
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text(title)
                    .font(OnboardingType.font(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(
                BrandTheme.homeCardSolid,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Text("G")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.92, green: 0.26, blue: 0.21),
                            Color(red: 0.98, green: 0.74, blue: 0.02),
                            Color(red: 0.20, green: 0.66, blue: 0.33),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .accessibilityHidden(true)
    }
}

enum OnboardingType {
    static func font(_ size: CGFloat, weight: UIFont.Weight, relativeTo style: UIFont.TextStyle) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: font))
    }
}

struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
