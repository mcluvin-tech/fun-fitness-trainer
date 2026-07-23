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
        self.trainerVoice = trainerVoice
        self.lastMorningRitualDate = lastMorningRitualDate
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
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var goalType: GoalType {
        get { GoalType(rawValue: goalTypeRaw) ?? .maintain }
        set { goalTypeRaw = newValue.rawValue }
    }
}
