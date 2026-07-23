import Foundation
import SwiftData

@Model
final class DailyGoal {
    var id: UUID
    var date: Date
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    init(
        id: UUID = UUID(),
        date: Date,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

struct MacroGoalPayload: Codable, Equatable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}
