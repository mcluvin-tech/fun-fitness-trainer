import Foundation

/// Persists Larry chat bubbles per calendar day (survives closing the chat sheet).
enum CoachChatPersistence {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    struct StoredBubble: Codable, Identifiable {
        let id: UUID
        let text: String
        let isUser: Bool
        let createdAt: Date
    }

    static func dayKey(for date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    static func loadBubbles(for date: Date = Date()) -> [StoredBubble] {
        guard let data = UserDefaults.standard.data(forKey: messagesKey(for: date)),
              let decoded = try? JSONDecoder().decode([StoredBubble].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ bubbles: [StoredBubble], for date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(bubbles) else { return }
        UserDefaults.standard.set(data, forKey: messagesKey(for: date))
    }

    static func hasGreetedToday(for date: Date = Date()) -> Bool {
        UserDefaults.standard.bool(forKey: greetedKey(for: date))
    }

    static func markGreetedToday(for date: Date = Date()) {
        UserDefaults.standard.set(true, forKey: greetedKey(for: date))
    }

    private static func messagesKey(for date: Date) -> String {
        "coachChat.messages.\(dayKey(for: date))"
    }

    private static func greetedKey(for date: Date) -> String {
        "coachChat.greeted.\(dayKey(for: date))"
    }
}
