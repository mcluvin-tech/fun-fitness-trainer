import Foundation
import SwiftData

enum PhraseTag: String, Codable, CaseIterable, Identifiable {
    case morning
    case underProtein = "under_protein"
    case crushedIt = "crushed_it"
    case cheatMeal = "cheat_meal"
    case streak
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .underProtein: return "Under protein"
        case .crushedIt: return "Crushed it"
        case .cheatMeal: return "Cheat meal"
        case .streak: return "Streak"
        case .general: return "General"
        }
    }
}

@Model
final class TrainerPhrase {
    var id: UUID
    var text: String
    var tagRaw: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, tag: PhraseTag, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.tagRaw = tag.rawValue
        self.createdAt = createdAt
    }

    var tag: PhraseTag {
        PhraseTag(rawValue: tagRaw) ?? .general
    }
}
