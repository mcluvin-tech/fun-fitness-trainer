import Foundation
import AuthenticationServices

struct SupabaseSession: Codable {
    let access_token: String
    let refresh_token: String?
    let user: SupabaseUser?
}

struct SupabaseUser: Codable {
    let id: String
    let email: String?
}

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    @Published var accessToken: String?
    @Published var userId: String?
    @Published var isSignedIn = false

    private let sessionKey = "supabaseAccessToken"
    private let userIdKey = "supabaseUserId"

    init() {
        accessToken = UserDefaults.standard.string(forKey: sessionKey)
        userId = UserDefaults.standard.string(forKey: userIdKey)
        isSignedIn = accessToken != nil
    }

    func clearSession() {
        accessToken = nil
        userId = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
    }

    func saveSession(token: String, userId: String?) {
        accessToken = token
        self.userId = userId
        isSignedIn = true
        UserDefaults.standard.set(token, forKey: sessionKey)
        if let userId { UserDefaults.standard.set(userId, forKey: userIdKey) }
    }

    func oauthAuthorizeURL(provider: String) -> URL? {
        guard let base = AppConfig.supabaseURL,
              var components = URLComponents(
                url: base.appendingPathComponent("auth/v1/authorize"),
                resolvingAgainstBaseURL: false
              ) else { return nil }
        var items = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: AppConfig.oauthRedirectURL),
        ]
        if let anon = AppConfig.supabaseAnonKey {
            items.append(URLQueryItem(name: "apikey", value: anon))
        }
        components.queryItems = items
        return components.url
    }

    /// Returns nil when the provider is ready; throws with a user-facing message otherwise.
    func verifyOAuthProvider(_ provider: String) async throws {
        guard let url = oauthAuthorizeURL(provider: provider) else {
            throw APIError.missingConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let anon = AppConfig.supabaseAnonKey {
            request.setValue(anon, forHTTPHeaderField: "apikey")
        }

        let delegate = OAuthRedirectProbeDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Enabled providers redirect to Google/Apple; disabled ones return 400 JSON.
        if (300...399).contains(http.statusCode) { return }

        if http.statusCode == 400,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["msg"] as? String {
            if msg.localizedCaseInsensitiveContains("not enabled") {
                throw APIError.serverMessage(
                    "Gmail sign-in isn’t turned on in Supabase yet. Enable Google under Authentication → Providers, then add your Google OAuth Client ID and Secret. See docs/GOOGLE_SIGNIN.md in the project."
                )
            }
            throw APIError.serverMessage(msg)
        }

        throw APIError.serverMessage("Could not start Gmail sign-in (HTTP \(http.statusCode)).")
    }

    func handleOAuthCallback(url: URL) async throws {
        let raw = [url.fragment, url.query].compactMap { $0 }.joined(separator: "&")
        guard !raw.isEmpty else {
            throw APIError.serverMessage("Missing auth tokens in callback.")
        }
        let params = parseAuthParameters(from: raw)

        if let error = params["error"] {
            let description = params["error_description"]?.replacingOccurrences(of: "+", with: " ")
            throw APIError.serverMessage(description ?? error)
        }

        guard let token = params["access_token"] else {
            throw APIError.serverMessage("Sign-in did not return an access token.")
        }
        saveSession(token: token, userId: nil)
        if let refresh = params["refresh_token"] {
            UserDefaults.standard.set(refresh, forKey: "supabaseRefreshToken")
        }
        try await refreshCurrentUserId()
    }

    func refreshCurrentUserId() async throws {
        guard let token = accessToken,
              let base = AppConfig.supabaseURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("auth/v1/user"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let anon = AppConfig.supabaseAnonKey {
            request.setValue(anon, forHTTPHeaderField: "apikey")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return
        }
        if let user = try? JSONDecoder().decode(SupabaseUser.self, from: data) {
            userId = user.id
            UserDefaults.standard.set(user.id, forKey: userIdKey)
        }
    }

    private func parseAuthParameters(from fragment: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = fragment.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                result[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return result
    }

    func sendPhoneOTP(phone: String) async throws {
        guard let url = AppConfig.supabaseURL?.appendingPathComponent("auth/v1/otp"),
              let anon = AppConfig.supabaseAnonKey else {
            throw APIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anon, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phone": phone,
            "create_user": true,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.authAPIError(data: data, statusCode: http.statusCode, fallback: "Could not send verification code.")
        }
    }

    func verifyPhoneOTP(phone: String, token: String) async throws {
        guard let url = AppConfig.supabaseURL?.appendingPathComponent("auth/v1/verify"),
              let anon = AppConfig.supabaseAnonKey else {
            throw APIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anon, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phone": phone,
            "token": token,
            "type": "sms",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.authAPIError(data: data, statusCode: http.statusCode, fallback: "Invalid verification code.")
        }

        let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
        saveSession(token: session.access_token, userId: session.user?.id)
        if let refresh = session.refresh_token {
            UserDefaults.standard.set(refresh, forKey: "supabaseRefreshToken")
        }
        try await refreshCurrentUserId()
    }

    private static func authAPIError(data: Data, statusCode: Int, fallback: String) -> APIError {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = (json["msg"] as? String)
                ?? (json["error_description"] as? String)
                ?? (json["message"] as? String)
                ?? (json["error"] as? String)
            if let message, !message.isEmpty {
                if message.localizedCaseInsensitiveContains("phone") &&
                    message.localizedCaseInsensitiveContains("not enabled") {
                    return .serverMessage(
                        "Phone sign-in isn’t turned on in Supabase yet. Enable Phone under Authentication → Providers and configure an SMS provider (e.g. Twilio)."
                    )
                }
                if message.localizedCaseInsensitiveContains("nonce") {
                    return .serverMessage(
                        "Apple sign-in nonce mismatch. In Supabase → Authentication → Providers → Apple, enable “Skip nonce check”, or update Supabase Auth to the latest version."
                    )
                }
                return .serverMessage(message)
            }
        }
        return .serverMessage("\(fallback) (HTTP \(statusCode)).")
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        guard let url = AppConfig.supabaseURL?.appendingPathComponent("auth/v1/token"),
              let anon = AppConfig.supabaseAnonKey else {
            throw APIError.missingConfiguration
        }

        var request = URLRequest(url: url.appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "id_token"),
        ]))
        request.httpMethod = "POST"
        request.setValue(anon, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken,
            "nonce": nonce,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.authAPIError(data: data, statusCode: http.statusCode, fallback: "Apple sign-in failed.")
        }

        let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
        saveSession(token: session.access_token, userId: session.user?.id)
        if let refresh = session.refresh_token {
            UserDefaults.standard.set(refresh, forKey: "supabaseRefreshToken")
        }
        try await refreshCurrentUserId()
    }

    func invokeFunction(
        name: String,
        body: [String: Any],
        timeout: TimeInterval = 60
    ) async throws -> Data {
        guard let base = AppConfig.supabaseURL else { throw APIError.missingConfiguration }
        let url = base.appendingPathComponent("functions/v1/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let anon = AppConfig.supabaseAnonKey {
            request.setValue(anon, forHTTPHeaderField: "apikey")
        }
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let anon = AppConfig.supabaseAnonKey {
            request.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Error"
            throw APIError.serverMessage(message)
        }
        return data
    }

    func syncTrainerVoice(_ voice: String) async throws {
        guard let userId, isSignedIn else { return }
        guard let base = AppConfig.supabaseURL else { throw APIError.missingConfiguration }
        let url = base.appendingPathComponent("rest/v1/profiles")
        var request = URLRequest(url: url.appending(queryItems: [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
        ]))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        if let anon = AppConfig.supabaseAnonKey { request.setValue(anon, forHTTPHeaderField: "apikey") }
        if let token = accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "trainer_voice": voice,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchTrainerVoice() async throws -> String? {
        guard let userId, isSignedIn else { return nil }
        guard let base = AppConfig.supabaseURL else { throw APIError.missingConfiguration }
        let url = base.appendingPathComponent("rest/v1/profiles").appending(queryItems: [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "trainer_voice"),
        ])
        var request = URLRequest(url: url)
        if let anon = AppConfig.supabaseAnonKey { request.setValue(anon, forHTTPHeaderField: "apikey") }
        if let token = accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Row: Decodable { let trainer_voice: String? }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.first?.trainer_voice
    }

    func deleteAccount() async throws {
        // Client clears local session; full user deletion requires service role or dashboard workflow.
        clearSession()
    }
}

/// Stops URLSession from following OAuth redirects so we can probe provider status.
private final class OAuthRedirectProbeDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum APIError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case httpError(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Add Secrets.plist with Supabase URL and anon key."
        case .invalidResponse: return "Invalid server response."
        case .httpError(let code): return "Server error (\(code))."
        case .serverMessage(let msg): return msg
        }
    }
}
