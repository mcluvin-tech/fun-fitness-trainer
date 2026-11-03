import Foundation
import SwiftData

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
}

enum GoalType: String, Codable, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lose: return "Lose weight"
        case .maintain: return "Maintain"
        case .gain: return "Gain muscle"
        }
    }
}

/// How calories are split. Does not change the calorie formula itself.
enum DietStyle: String, Codable, CaseIterable, Identifiable {
    case balanced
    case keto
    case paleo
    case carnivore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .keto: return "Keto"
        case .paleo: return "Paleo"
        case .carnivore: return "Carnivore"
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            return "High protein, carbs for training, fat in moderation. Larry's default."
        case .keto:
            return "Very low carb. After protein, fat covers most of the calories."
        case .paleo:
            return "Whole-food split: high protein, more fat, carbs from what's left."
        case .carnivore:
            return "Meat, eggs, and fat. Carbs stay at zero."
        }
    }

    var macroHint: String {
        switch self {
        case .balanced:
            return "About 1 g protein per lb · fat ~25–28% · carbs fill the rest"
        case .keto:
            return "About 30 g carbs · protein stays high · fat fills the rest"
        case .paleo:
            return "About 1 g protein per lb · fat closer to 40% · carbs from the remainder"
        case .carnivore:
            return "0 g carbs · about 1 g protein per lb · fat fills the rest"
        }
    }

    var symbolName: String {
        switch self {
        case .balanced: return "chart.pie.fill"
        case .keto: return "flame.fill"
        case .paleo: return "leaf.fill"
        case .carnivore: return "fork.knife"
        }
    }
}

enum ActivityLevel: Double, CaseIterable, Identifiable {
    case sedentary = 1.2
    case light = 1.375
    case moderate = 1.55
    case active = 1.725
    case veryActive = 1.9

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }
}

@Model
final class UserSettings {
    var id: UUID
    var sexRaw: String
    /// Integer age captured at onboarding. Not derived from date of birth — adding DOB
    /// would require a SwiftData schema change we are not doing in V1. Age does not
    /// increment automatically.
    var age: Int
    var heightCm: Double
    var weightKg: Double
    /// Target body weight in kg; nil = same as current weight at onboarding.
    var goalWeightKg: Double?
    /// Signed lb/week: negative = loss, positive = gain; nil = auto from goal gap.
    var weeklyLbChangeTarget: Double?
    var usesImperialUnits: Bool
    var activityRaw: Double
    var goalTypeRaw: String
    /// Nil until the person picks a style. Existing profiles stay on Balanced until they choose.
    var dietStyleRaw: String?
    /// Calories pulled off the calculated target. Nil or 0 means the plan number.
    var calorieNudgeKcal: Double?
    var trainerVoice: String
    var lastMorningRitualDate: Date?

    init(
        id: UUID = UUID(),
        sex: Sex = .male,
        age: Int = 30,
        heightCm: Double = 175,
        weightKg: Double = 75,
        goalWeightKg: Double? = nil,
        weeklyLbChangeTarget: Double? = nil,
        usesImperialUnits: Bool = true,
        activity: ActivityLevel = .moderate,
        goalType: GoalType = .maintain,
        dietStyle: DietStyle = .balanced,
        calorieNudgeKcal: Double? = nil,
        trainerVoice: String = "",
        lastMorningRitualDate: Date? = nil
    ) {
        self.id = id
        self.sexRaw = sex.rawValue
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.goalWeightKg = goalWeightKg
        self.weeklyLbChangeTarget = weeklyLbChangeTarget
        self.usesImperialUnits = usesImperialUnits
        self.activityRaw = activity.rawValue
        self.goalTypeRaw = goalType.rawValue
        self.dietStyleRaw = dietStyle.rawValue
        self.calorieNudgeKcal = calorieNudgeKcal
        self.trainerVoice = trainerVoice
        self.lastMorningRitualDate = lastMorningRitualDate
    }

    var hasChosenDiet: Bool {
        dietStyleRaw != nil
    }

    var effectiveGoalWeightKg: Double {
        goalWeightKg ?? weightKg
    }

    var resolvedGoalType: GoalType {
        let diff = effectiveGoalWeightKg - weightKg
        if diff < -0.5 { return .lose }
        if diff > 0.5 { return .gain }
        return goalType
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get {
            if let exact = ActivityLevel(rawValue: activityRaw) {
                return exact
            }
            return ActivityLevel.allCases.min {
                abs($0.rawValue - activityRaw) < abs($1.rawValue - activityRaw)
            } ?? .moderate
        }
        set { activityRaw = newValue.rawValue }
    }

    var goalType: GoalType {
        get { GoalType(rawValue: goalTypeRaw) ?? .maintain }
        set { goalTypeRaw = newValue.rawValue }
    }

    var dietStyle: DietStyle {
        get { DietStyle(rawValue: dietStyleRaw ?? "") ?? .balanced }
        set { dietStyleRaw = newValue.rawValue }
    }

    /// How far under the calculated calorie target the person asked to sit.
    var resolvedCalorieNudge: Double {
        max(0, calorieNudgeKcal ?? 0)
    }
}
