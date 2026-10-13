import Foundation

enum FriendChallengeStatus: String, Codable, Equatable {
    case pending
    case accepted
    case expired
    case cancelled
}

/// Public challenge fields. Never includes weight, photos, or food logs.
struct FriendChallenge: Equatable, Identifiable {
    let id: UUID
    let inviteToken: String?
    var status: FriendChallengeStatus
    var inviterDisplayName: String?
    var opponentDisplayName: String?
    var isOwnInvite: Bool
    var isInvitee: Bool
    var isInviter: Bool
    var createdAt: Date?
    var acceptedAt: Date?
    var startsAt: Date?
    var endsAt: Date?
    var expiresAt: Date?
    var wasNewlyCreated: Bool
    var newlyAccepted: Bool
    var justExpired: Bool
}

struct CreatedFriendChallenge: Equatable {
    let challenge: FriendChallenge
    let expiredIds: [UUID]
}

enum IncomingChallengeState: Equatable {
    case canAccept
    case ownInvite
    case expired
    case alreadyAcceptedByYou
    case alreadyAcceptedBySomeoneElse
    case cancelled
    case invalid
}

enum ChallengeLink {
    static let tokenPattern = #"^[A-Za-z0-9]{16,80}$"#

    static func isValidToken(_ token: String) -> Bool {
        token.range(of: tokenPattern, options: .regularExpression) != nil
    }

    static func normalizeToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Custom-scheme links work today. HTTPS links are recognized for any host
    /// so a real domain can be turned on later without a parser change.
    static func token(from url: URL) -> String? {
        let host = url.host?.lowercased()
        let parts = url.path.split(separator: "/").map(String.init)
        let pathMarksChallenge = parts.contains { $0.lowercased() == "challenge" }
        let hostMarksChallenge = host == "challenge"
        guard hostMarksChallenge || pathMarksChallenge else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let query = components.queryItems?.first(where: { $0.name == "token" })?.value,
           let token = validated(query) {
            return token
        }

        if hostMarksChallenge, let first = parts.first, let token = validated(first) {
            return token
        }

        if let index = parts.firstIndex(where: { $0.lowercased() == "challenge" }),
           index + 1 < parts.count,
           let token = validated(parts[index + 1]) {
            return token
        }
        return nil
    }

    static func inviteURL(token: String) -> URL {
        let token = normalizeToken(token)
        // Production: HTTPS universal link (opens app, or your web page → App Store).
        if let host = AppConfig.challengeUniversalLinkHost,
           let url = URL(string: "https://\(host)/challenge/\(token)") {
            return url
        }
        // Dev / pre-domain: custom scheme only works if the app is already installed.
        return URL(string: "\(AppConfig.oauthCallbackScheme)://challenge/\(token)")!
    }

    static func shareMessage(link: URL) -> String {
        let isHTTPS = link.scheme?.lowercased() == "https"
        var lines = [
            "Larry McQuade has officially called you out. 🥊",
            "",
            "I'm challenging you to a 7-day fitness showdown.",
            "",
            "Accept the challenge:",
            link.absoluteString,
        ]

        // Custom-scheme invites can't install the app. Append the App Store page
        // once APP_STORE_URL / APP_STORE_ID is set for launch.
        if !isHTTPS, let store = AppConfig.appStoreURL {
            lines += [
                "",
                "Don't have the app yet? Grab it here, then open that challenge link again:",
                store.absoluteString,
            ]
        }

        lines += [
            "",
            "No spreadsheets. No excuses. Larry's watching.",
        ]
        return lines.joined(separator: "\n")
    }

    private static func validated(_ raw: String) -> String? {
        let token = normalizeToken(raw)
        return isValidToken(token) ? token : nil
    }
}

enum FriendChallengeRules {
    static let inviteLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let competitionLength: TimeInterval = 7 * 24 * 60 * 60

    static func inviteExpiresAt(createdAt: Date) -> Date {
        createdAt.addingTimeInterval(inviteLifetime)
    }

    static func competitionWindow(acceptedAt: Date) -> (start: Date, end: Date) {
        (acceptedAt, acceptedAt.addingTimeInterval(competitionLength))
    }

    static func isInviteExpired(status: FriendChallengeStatus, expiresAt: Date, now: Date = Date()) -> Bool {
        if status == .expired { return true }
        return status == .pending && expiresAt <= now
    }

    static func displayName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return nil }
        if trimmed.caseInsensitiveCompare("Athlete") == .orderedSame { return nil }
        return trimmed
    }

    static func waitingLine(opponentName: String?) -> String {
        if let name = displayName(opponentName) {
            return "Waiting for \(name) to accept"
        }
        return "Waiting for your opponent to accept"
    }

    static func calloutLine(inviterName: String?) -> String {
        if let name = displayName(inviterName) {
            return "\(name) challenged you to a 7-day Larry showdown."
        }
        return "A friend challenged you to a 7-day Larry showdown."
    }

    static func connectedLine(opponentName: String?) -> String {
        if let name = displayName(opponentName) {
            return "Challenge on with \(name). 7 days. One winner."
        }
        return "Challenge accepted. 7 days. One winner."
    }

    static func isCurrent(_ challenge: FriendChallenge, now: Date = Date()) -> Bool {
        switch challenge.status {
        case .pending:
            guard let expiresAt = challenge.expiresAt else { return true }
            return !isInviteExpired(status: .pending, expiresAt: expiresAt, now: now)
        case .accepted:
            guard let endsAt = challenge.endsAt else { return true }
            return endsAt > now
        case .expired, .cancelled:
            return false
        }
    }

    /// Prefer the open invite the inviter can still share. Otherwise the live accepted challenge.
    static func preferredCardChallenge(_ challenges: [FriendChallenge], now: Date = Date()) -> FriendChallenge? {
        let current = challenges.filter { isCurrent($0, now: now) }
        if let pending = current.first(where: { $0.status == .pending && $0.isInviter }) {
            return pending
        }
        return current.first { $0.status == .accepted }
    }

    static func incomingState(
        found: Bool,
        status: FriendChallengeStatus?,
        isOwnInvite: Bool,
        isInvitee: Bool,
        expiresAt: Date?,
        now: Date = Date()
    ) -> IncomingChallengeState {
        guard found, let status else { return .invalid }
        if isOwnInvite { return .ownInvite }
        if status == .cancelled { return .cancelled }
        if status == .expired { return .expired }
        if status == .pending, let expiresAt, isInviteExpired(status: .pending, expiresAt: expiresAt, now: now) {
            return .expired
        }
        if status == .accepted {
            return isInvitee ? .alreadyAcceptedByYou : .alreadyAcceptedBySomeoneElse
        }
        if status == .pending { return .canAccept }
        return .invalid
    }
}

/// Larry's challenge trash talk. Roasts the rival's vibe, habits, or a cartoon physique.
/// "Jake" in the source lines is the rival's display name when we know it.
enum LarryChallengeQuotes {
    enum Moment {
        case invite
        case calledOut
        case accepted
    }

    /// Held back until a real lead exists. Saying it now would invent a score.
    static let pointsLeadLine = "He's 20 points ahead. I've seen more muscle on a rotisserie chicken."

    static func line(moment: Moment, rivalName: String?, seed: Int = 0) -> String {
        switch moment {
        case .invite, .calledOut:
            return favorite(rivalName: rivalName)
        case .accepted:
            let pool = acceptedLines(rivalName: rivalName)
            let index = Int(seed.magnitude % UInt(pool.count))
            return pool[index]
        }
    }

    static func favorite(rivalName: String?) -> String {
        if let name = FriendChallengeRules.displayName(rivalName) {
            return "\(name)'s been hitting his protein. You gonna let that string bean outwork you?"
        }
        return "You gonna let that string bean outwork you?"
    }

    static func acceptedLines(rivalName: String?) -> [String] {
        let name = FriendChallengeRules.displayName(rivalName)
        var lines = [
            favorite(rivalName: rivalName),
            "You gonna let that string bean beat you?",
            "You're losing to a man built like a coat hanger.",
            "Your buddy's outworking you and he looks like he orders dressing on the side.",
            "That human breadstick just took the lead.",
            "You're really gonna let Captain Chicken Legs win this thing?",
            "Brother. The scarecrow is beating you.",
            "You have been overtaken by a guy with the wingspan of a pool noodle.",
            "That lanky son of a gun is actually doing it.",
        ]
        if let name {
            lines.insert("\(name)'s ahead. By \(name). Come on, brother.", at: 1)
        }
        return lines
    }
}

struct ChallengeRPCObject: Decodable, Equatable {
    var found: Bool?
    var id: UUID?
    var inviteToken: String?
    var status: String?
    var created: Bool?
    var newlyAccepted: Bool?
    var inviterDisplayName: String?
    var opponentDisplayName: String?
    var isOwnInvite: Bool?
    var isInvitee: Bool?
    var isInviter: Bool?
    var createdAt: Date?
    var acceptedAt: Date?
    var startsAt: Date?
    var endsAt: Date?
    var expiresAt: Date?
    var justExpired: Bool?
    var expiredIds: [UUID]?

    var challengeStatus: FriendChallengeStatus? {
        guard let status else { return nil }
        return FriendChallengeStatus(rawValue: status)
    }

    func asChallenge() -> FriendChallenge? {
        guard let id, let challengeStatus else { return nil }
        return FriendChallenge(
            id: id,
            inviteToken: inviteToken,
            status: challengeStatus,
            inviterDisplayName: inviterDisplayName,
            opponentDisplayName: opponentDisplayName,
            isOwnInvite: isOwnInvite ?? false,
            isInvitee: isInvitee ?? false,
            isInviter: isInviter ?? false,
            createdAt: createdAt,
            acceptedAt: acceptedAt,
            startsAt: startsAt,
            endsAt: endsAt,
            expiresAt: expiresAt,
            wasNewlyCreated: created ?? false,
            newlyAccepted: newlyAccepted ?? false,
            justExpired: justExpired ?? false
        )
    }
}

extension ChallengeRPCObject {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        found = try container.decodeIfPresent(Bool.self, forKey: .found)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        inviteToken = try container.decodeIfPresent(String.self, forKey: .inviteToken)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        created = try container.decodeIfPresent(Bool.self, forKey: .created)
        newlyAccepted = try container.decodeIfPresent(Bool.self, forKey: .newlyAccepted)
        inviterDisplayName = try container.decodeIfPresent(String.self, forKey: .inviterDisplayName)
        opponentDisplayName = try container.decodeIfPresent(String.self, forKey: .opponentDisplayName)
        isOwnInvite = try container.decodeIfPresent(Bool.self, forKey: .isOwnInvite)
        isInvitee = try container.decodeIfPresent(Bool.self, forKey: .isInvitee)
        isInviter = try container.decodeIfPresent(Bool.self, forKey: .isInviter)
        createdAt = ChallengeDateParser.parse(try container.decodeIfPresent(String.self, forKey: .createdAt))
        acceptedAt = ChallengeDateParser.parse(try container.decodeIfPresent(String.self, forKey: .acceptedAt))
        startsAt = ChallengeDateParser.parse(try container.decodeIfPresent(String.self, forKey: .startsAt))
        endsAt = ChallengeDateParser.parse(try container.decodeIfPresent(String.self, forKey: .endsAt))
        expiresAt = ChallengeDateParser.parse(try container.decodeIfPresent(String.self, forKey: .expiresAt))
        justExpired = try container.decodeIfPresent(Bool.self, forKey: .justExpired)
        expiredIds = try container.decodeIfPresent([UUID].self, forKey: .expiredIds)
    }

    private enum CodingKeys: String, CodingKey {
        case found
        case id
        case inviteToken = "invite_token"
        case status
        case created
        case newlyAccepted = "newly_accepted"
        case inviterDisplayName = "inviter_display_name"
        case opponentDisplayName = "opponent_display_name"
        case isOwnInvite = "is_own_invite"
        case isInvitee = "is_invitee"
        case isInviter = "is_inviter"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case expiresAt = "expires_at"
        case justExpired = "just_expired"
        case expiredIds = "expired_ids"
    }
}

enum ChallengeDateParser {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: trimmed) { return date }
        return nil
    }
}
