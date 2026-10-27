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

    init(calories: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = FlexibleJSONNumber.double(c, .calories)
        proteinG = FlexibleJSONNumber.double(c, .proteinG)
        carbsG = FlexibleJSONNumber.double(c, .carbsG)
        fatG = FlexibleJSONNumber.double(c, .fatG)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(calories, forKey: .calories)
        try c.encode(proteinG, forKey: .proteinG)
        try c.encode(carbsG, forKey: .carbsG)
        try c.encode(fatG, forKey: .fatG)
    }
}
