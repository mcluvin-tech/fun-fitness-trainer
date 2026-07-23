import Foundation

enum AppConfig {
    static let bundleId = "com.lukeeidsvold.funfitnesstrainer"
    static let freeScansPerDay = 3
    static let promptVersion = 3

    /// Must match Info.plist URL scheme and Supabase redirect allow-list.
    static let oauthCallbackScheme = "funfitnesstrainer"
    static var oauthRedirectURL: String {
        "\(oauthCallbackScheme)://auth-callback"
    }

    /// Sign in with Apple requires a paid Apple Developer Program membership and production entitlements.
    /// Set to `true` after enrolling and switching Release to `FunFitnessTrainer.entitlements` in Xcode.
    static let supportsSignInWithApple = false

    static var supabaseURL: URL? {
        guard let s = Secrets.value(for: "SUPABASE_URL") else { return nil }
        return URL(string: s)
    }

    static var supabaseAnonKey: String? {
        Secrets.value(for: "SUPABASE_ANON_KEY")
            ?? Secrets.value(for: "SUPABASE_PUBLISHABLE_KEY")
    }

    static var revenueCatAPIKey: String? {
        Secrets.value(for: "REVENUECAT_API_KEY")
    }

    static var hasBackend: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }
}

enum Secrets {
    static func value(for key: String) -> String? {
        for url in candidateURLs() {
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any],
                  let value = dict[key] as? String,
                  !value.isEmpty,
                  !value.contains("YOUR_") else { continue }
            return value
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist") {
            urls.append(URL(fileURLWithPath: path))
        }
        #if DEBUG
        let dev = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Secrets.plist")
        urls.append(dev)
        #endif
        return urls
    }
}
