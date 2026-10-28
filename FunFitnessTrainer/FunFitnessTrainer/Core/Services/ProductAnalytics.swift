import Foundation
import os

/// Lightweight event log. There is no analytics SDK in the app yet.
/// Nutrition, body weight, and invite tokens are dropped if a caller includes them.
enum ProductAnalytics {
    enum Event: String {
        case challengeInviteViewed = "challenge_invite_viewed"
        case challengeInviteCreated = "challenge_invite_created"
        case challengeShareOpened = "challenge_share_opened"
        case challengeLinkOpened = "challenge_link_opened"
        case challengeAccepted = "challenge_accepted"
        case challengeInviteExpired = "challenge_invite_expired"
    }

    private static let logger = Logger(subsystem: AppConfig.bundleId, category: "analytics")
    private static let blockedKeys: Set<String> = [
        "token", "invite_token", "calories", "protein", "carbs", "fat",
        "weight", "bodyweight", "email", "phone", "photo",
    ]

    /// Test hook. Production callers leave this nil.
    static var sink: ((Event, [String: String]) -> Void)?

    static func track(_ event: Event, metadata: [String: String] = [:]) {
        var safe: [String: String] = [:]
        for (key, value) in metadata where !blockedKeys.contains(key.lowercased()) {
            safe[key] = String(value.prefix(80))
        }
        let detail = safe
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.info("\(event.rawValue, privacy: .public) \(detail, privacy: .public)")
        sink?(event, safe)
    }
}
