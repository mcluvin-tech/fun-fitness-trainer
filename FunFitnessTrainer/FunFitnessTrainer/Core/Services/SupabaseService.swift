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
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Refusing the redirect completes the task with "The network connection was lost."
            // A 3xx means Google is enabled; the browser session performs the real sign-in.
            if let status = delegate.redirectStatus, (300...399).contains(status) {
                return
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Enabled providers redirect to Google/Apple; disabled ones return 400 JSON.
        if (300...399).contains(http.statusCode) || delegate.redirectStatus != nil { return }

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
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "B",
                location: "SupabaseService.sendPhoneOTP",
                message: "missing configuration",
                data: [
                    "hasURL": AppConfig.supabaseURL != nil,
                    "hasAnonKey": AppConfig.supabaseAnonKey != nil,
                ]
            )
            // #endregion
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
        let hasAuthorization = request.value(forHTTPHeaderField: "Authorization") != nil
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "C",
            location: "SupabaseService.sendPhoneOTP",
            message: "about to POST otp",
            data: [
                "host": url.host ?? "",
                "path": url.path,
                "scheme": url.scheme ?? "",
                "phoneLength": phone.count,
                "phonePrefix": String(phone.prefix(2)),
                "hasAuthorization": hasAuthorization,
                "anonKeyLength": anon.count,
                "bodyBytes": request.httpBody?.count ?? 0,
            ]
        )
        // #endregion

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let ns = error as NSError
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "D",
                location: "SupabaseService.sendPhoneOTP",
                message: "otp URLSession error",
                data: [
                    "errorDomain": ns.domain,
                    "errorCode": ns.code,
                    "errorDescription": error.localizedDescription,
                    "hasAuthorization": hasAuthorization,
                    "anonKeyLength": anon.count,
                    "host": url.host ?? "",
                    "path": url.path,
                ]
            )
            // #endregion
            throw Self.networkAuthError(ns, host: url.host)
        }

        guard let http = response as? HTTPURLResponse else {
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "D",
                location: "SupabaseService.sendPhoneOTP",
                message: "non-HTTP response",
                data: ["responseType": String(describing: type(of: response))]
            )
            // #endregion
            throw APIError.invalidResponse
        }
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "D",
            location: "SupabaseService.sendPhoneOTP",
            message: "otp HTTP response",
            data: [
                "statusCode": http.statusCode,
                "bytes": data.count,
                "hasAuthorization": hasAuthorization,
                "anonKeyLength": anon.count,
            ]
        )
        // #endregion
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

    /// Maps URLSession failures so a dead/paused project URL isn't shown as a vague "network lost".
    private static func networkAuthError(_ error: NSError, host: String?) -> Error {
        guard error.domain == NSURLErrorDomain else { return error }
        let hostLabel = host ?? "your Supabase URL"
        switch error.code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return APIError.serverMessage(
                "Can't find Supabase host \(hostLabel). Check SUPABASE_URL in Secrets.plist — the project may be deleted or the URL mistyped."
            )
        case NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet:
            return APIError.serverMessage(
                "Can't reach \(hostLabel). Confirm the Supabase project is active (not paused/deleted), Phone auth is enabled, and this phone is online. [\(error.domain):\(error.code)]"
            )
        default:
            return error
        }
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

    /// - Parameter retries: Extra attempts after the first on transient network failures (lost connection, timeout, DNS).
    func invokeFunction(
        name: String,
        body: [String: Any],
        timeout: TimeInterval = 60,
        retries: Int = 0
    ) async throws -> Data {
        var lastError: Error?
        let attempts = max(retries, 0) + 1
        for attempt in 1...attempts {
            do {
                return try await invokeFunctionOnce(name: name, body: body, timeout: timeout)
            } catch where Self.isTransientNetworkFailure(error) {
                lastError = error
                if attempt < attempts {
                    let delayNs = UInt64(attempt) * 700_000_000
                    try? await Task.sleep(nanoseconds: delayNs)
                    continue
                }
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private static func isTransientNetworkFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isTransientNetworkError(urlError)
        }
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorDataNotAllowed,
        ].contains(ns.code)
    }

    private func invokeFunctionOnce(
        name: String,
        body: [String: Any],
        timeout: TimeInterval
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

    private static func isTransientNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .timedOut, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
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
/// Cancelling the redirect makes `data(for:)` throw `NSURLErrorNetworkConnectionLost`;
/// `redirectStatus` lets the caller treat that as "provider is enabled."
private final class OAuthRedirectProbeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirectStatusCode: Int?

    var redirectStatus: Int? {
        lock.lock()
        defer { lock.unlock() }
        return redirectStatusCode
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirectStatusCode = response.statusCode
        lock.unlock()
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
