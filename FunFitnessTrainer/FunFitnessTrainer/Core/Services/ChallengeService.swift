import Foundation

enum ChallengeFailure: LocalizedError, Equatable {
    case notSignedIn
    case missingBackend
    case invalidInvite
    case ownInvite
    case expiredInvite
    case alreadyAccepted
    case cancelledInvite
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in so Larry knows who threw the challenge."
        case .missingBackend:
            return "Add Secrets.plist with Supabase URL and anon key."
        case .invalidInvite:
            return "This challenge link isn't valid."
        case .ownInvite:
            return "This is your challenge. Your opponent has to accept it."
        case .expiredInvite:
            return "This challenge expired. Ask them to send a new one."
        case .alreadyAccepted:
            return "This challenge has already been accepted."
        case .cancelledInvite:
            return "This challenge was cancelled."
        case .unavailable:
            return "Couldn't reach Larry's server. Check your connection and try again."
        }
    }
}

/// Invite, share, and accept. The rivalry itself is a later phase.
@MainActor
final class ChallengeService {
    static let shared = ChallengeService()

    private let supabase = SupabaseService.shared

    private init() {}

    func createChallenge() async throws -> CreatedFriendChallenge {
        guard AppConfig.hasBackend else { throw ChallengeFailure.missingBackend }
        guard supabase.isSignedIn else { throw ChallengeFailure.notSignedIn }

        let object: ChallengeRPCObject = try await rpc(function: "create_friend_challenge", body: [:])
        guard let challenge = object.asChallenge() else { throw ChallengeFailure.unavailable }
        if challenge.wasNewlyCreated {
            ProductAnalytics.track(.challengeInviteCreated, metadata: [
                "challenge_id": challenge.id.uuidString,
                "status": challenge.status.rawValue,
            ])
        }
        for id in object.expiredIds ?? [] {
            ProductAnalytics.track(.challengeInviteExpired, metadata: [
                "challenge_id": id.uuidString,
                "status": FriendChallengeStatus.expired.rawValue,
            ])
        }
        return CreatedFriendChallenge(challenge: challenge, expiredIds: object.expiredIds ?? [])
    }

    func fetchChallenge(inviteToken: String) async throws -> FriendChallenge? {
        guard AppConfig.hasBackend else { throw ChallengeFailure.missingBackend }
        let token = ChallengeLink.normalizeToken(inviteToken)
        guard ChallengeLink.isValidToken(token) else { throw ChallengeFailure.invalidInvite }

        let object: ChallengeRPCObject = try await rpc(
            function: "get_friend_challenge",
            body: ["token": token]
        )
        if object.found == false { return nil }
        guard let challenge = object.asChallenge() else { throw ChallengeFailure.unavailable }
        if challenge.justExpired {
            ProductAnalytics.track(.challengeInviteExpired, metadata: [
                "challenge_id": challenge.id.uuidString,
                "status": FriendChallengeStatus.expired.rawValue,
            ])
        }
        return challenge
    }

    func acceptChallenge(inviteToken: String) async throws -> FriendChallenge {
        guard AppConfig.hasBackend else { throw ChallengeFailure.missingBackend }
        guard supabase.isSignedIn else { throw ChallengeFailure.notSignedIn }
        let token = ChallengeLink.normalizeToken(inviteToken)
        guard ChallengeLink.isValidToken(token) else { throw ChallengeFailure.invalidInvite }

        let object: ChallengeRPCObject = try await rpc(
            function: "accept_friend_challenge",
            body: ["token": token]
        )
        guard let challenge = object.asChallenge() else { throw ChallengeFailure.unavailable }
        if challenge.newlyAccepted {
            ProductAnalytics.track(.challengeAccepted, metadata: [
                "challenge_id": challenge.id.uuidString,
                "status": challenge.status.rawValue,
            ])
        }
        return challenge
    }

    func fetchMyChallenges() async throws -> [FriendChallenge] {
        guard AppConfig.hasBackend, supabase.isSignedIn else { return [] }
        let rows: [ChallengeRPCObject] = try await rpc(function: "list_my_friend_challenges", body: [:])
        return rows.compactMap { object in
            guard let challenge = object.asChallenge() else { return nil }
            if challenge.justExpired {
                ProductAnalytics.track(.challengeInviteExpired, metadata: [
                    "challenge_id": challenge.id.uuidString,
                    "status": FriendChallengeStatus.expired.rawValue,
                ])
            }
            return challenge
        }
    }

    private func rpc<T: Decodable>(function: String, body: [String: Any]) async throws -> T {
        guard let base = AppConfig.supabaseURL else { throw ChallengeFailure.missingBackend }
        let url = base.appendingPathComponent("rest/v1/rpc/\(function)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let anon = AppConfig.supabaseAnonKey {
            request.setValue(anon, forHTTPHeaderField: "apikey")
        }
        if let token = supabase.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let anon = AppConfig.supabaseAnonKey {
            request.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ChallengeFailure.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw ChallengeFailure.unavailable }
        guard (200...299).contains(http.statusCode) else {
            throw failure(from: data, statusCode: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ChallengeFailure.unavailable
        }
    }

    private func failure(from data: Data, statusCode: Int) -> ChallengeFailure {
        let message = serverMessage(from: data).lowercased()
        if message.contains("own_invite") { return .ownInvite }
        if message.contains("expired_invite") { return .expiredInvite }
        if message.contains("already_accepted") { return .alreadyAccepted }
        if message.contains("invalid_invite") { return .invalidInvite }
        if message.contains("cancelled_invite") { return .cancelledInvite }
        if message.contains("not_authenticated") || statusCode == 401 { return .notSignedIn }
        return .unavailable
    }

    private func serverMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String { return message }
            if let msg = json["msg"] as? String { return msg }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
