import Foundation

enum AppConfig {
    static let bundleId = "com.lukeeidsvold.funfitnesstrainer"
    static let freeScansPerDay = 3

    /// This phone build. A Release App Store build keeps the daily free-scan cap.
    #if DEBUG
    static let isFoundersEdition = true
    #else
    static let isFoundersEdition = false
    #endif
    static let promptVersion = 3

    /// Must match Info.plist URL scheme and Supabase redirect allow-list.
    static let oauthCallbackScheme = "funfitnesstrainer"

    /// HTTPS host for challenge invites once Associated Domains are configured.
    /// Until this is a real host, invites use `funfitnesstrainer://challenge/{token}`.
    static var challengeUniversalLinkHost: String? {
        guard var host = Secrets.value(for: "CHALLENGE_LINK_HOST") else { return nil }
        host = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        host = host.split(separator: "/").first.map(String.init) ?? host
        if host.isEmpty || host.contains(" ") { return nil }
        return host
    }

    /// Public App Store product page. Used in challenge share text so friends
    /// without the app get a real download link before App Store launch.
    /// Prefer `APP_STORE_URL`, or set `APP_STORE_ID` (numeric) to build the URL.
    static var appStoreURL: URL? {
        if let raw = Secrets.value(for: "APP_STORE_URL")?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            return url
        }
        if let id = Secrets.value(for: "APP_STORE_ID")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty,
           id.allSatisfy(\.isNumber),
           let url = URL(string: "https://apps.apple.com/app/id\(id)") {
            return url
        }
        return nil
    }

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
