import Foundation

/// Daily calorie adjustment per pound of body-weight change per week (~3,500 kcal per lb).
private let kcalPerLbPerWeek: Double = 3500.0 / 7.0

struct FitnessPlan: Equatable {
    let goalType: GoalType
    /// Signed: negative = losing lb/week, positive = gaining, zero = maintain.
    let weeklyLbChange: Double
    let weeksToGoal: Double?
    let maintenanceCalories: Double
    let targetCalories: Double
    let dailyCalorieDelta: Double
    let macros: MacroGoalPayload
    let coachStyleName: String
    let coachSummary: String
    let macroAdvice: String
}

enum GoalCalculator {
    /// Lean-eating philosophy inspired by coaches like Patrick Murphy & Duffy Gaver.
    static let leanCoachPhilosophy = """
    Stay lean with high protein (~1 g per lb bodyweight), mostly whole foods, plenty of vegetables, \
    lean meats, fish, eggs, and Greek yogurt. Skip junk, liquid calories, and oversized portions. \
    Carbs around training; fats from olive oil, nuts, avocado in moderation. Simple, disciplined, repeatable.
    """

    // MARK: - Public

    static func recommendedMacros(for settings: UserSettings) -> MacroGoalPayload {
        buildPlan(for: settings).macros
    }

    static func buildPlan(for settings: UserSettings) -> FitnessPlan {
        let currentLb = settings.weightKg * kgToLb
        let goalLb = settings.effectiveGoalWeightKg * kgToLb
        let goalType = settings.resolvedGoalType
        let weeklyLb = settings.weeklyLbChangeTarget ?? recommendedWeeklyLbChange(
            currentLb: currentLb,
            goalLb: goalLb,
            goalType: goalType
        )

        let maintenance = maintenanceCalories(for: settings)
        let dailyDelta = weeklyLb * kcalPerLbPerWeek
        var target = maintenance + dailyDelta

        let floor = settings.sex == .female ? 1400.0 : 1600.0
        let ceiling = maintenance + 750
        target = min(max(target, floor), ceiling)

        let macros = celebrityTrainerMacros(
            settings: settings,
            targetCalories: target,
            goalType: goalType
        )

        let weeks: Double? = {
            guard goalType != .maintain, abs(weeklyLb) > 0.05 else { return nil }
            let diffLb = abs(goalLb - currentLb)
            guard diffLb >= 1 else { return nil }
            return diffLb / abs(weeklyLb)
        }()

        let style = coachStyle(for: goalType)

        return FitnessPlan(
            goalType: goalType,
            weeklyLbChange: weeklyLb,
            weeksToGoal: weeks,
            maintenanceCalories: maintenance.rounded(),
            targetCalories: target.rounded(),
            dailyCalorieDelta: dailyDelta.rounded(),
            macros: macros,
            coachStyleName: style.name,
            coachSummary: style.summary,
            macroAdvice: style.macroAdvice(goalType)
        )
    }

    /// Suggested lb/week toward goal (negative = loss, positive = gain).
    static func recommendedWeeklyLbChange(
        currentLb: Double,
        goalLb: Double,
        goalType: GoalType
    ) -> Double {
        let diff = goalLb - currentLb
        if abs(diff) < 1 { return 0 }

        switch goalType {
        case .maintain:
            return 0
        case .lose:
            let maxSafe = min(2.0, max(0.5, currentLb * 0.01))
            let pace = min(maxSafe, max(0.5, abs(diff) / 12))
            return -pace
        case .gain:
            let pace = min(0.75, max(0.25, abs(diff) / 16))
            return pace
        }
    }

    // MARK: - TDEE

    private static func maintenanceCalories(for settings: UserSettings) -> Double {
        let bmr: Double
        switch settings.sex {
        case .male:
            bmr = 10 * settings.weightKg + 6.25 * settings.heightCm - 5 * Double(settings.age) + 5
        case .female:
            bmr = 10 * settings.weightKg + 6.25 * settings.heightCm - 5 * Double(settings.age) - 161
        }
        return bmr * settings.activity.rawValue
    }

    // MARK: - Celebrity-trainer style macros (Murphy / Gaver inspired)

    /// High-protein, whole-food emphasis — similar to coaches like Patrick Murphy & Duffy Gaver.
    private static func celebrityTrainerMacros(
        settings: UserSettings,
        targetCalories: Double,
        goalType: GoalType
    ) -> MacroGoalPayload {
        let referenceLb = max(settings.weightKg, settings.effectiveGoalWeightKg) * kgToLb

        let proteinPerLb: Double
        let fatPercent: Double
        switch goalType {
        case .lose:
            proteinPerLb = 1.1
            fatPercent = 0.28
        case .gain:
            proteinPerLb = 1.0
            fatPercent = 0.25
        case .maintain:
            proteinPerLb = 1.0
            fatPercent = 0.27
        }

        let proteinG = (referenceLb * proteinPerLb).rounded()
        let fatG = (targetCalories * fatPercent / 9).rounded()
        let proteinKcal = proteinG * 4
        let fatKcal = fatG * 9
        let carbsG = max(50, (targetCalories - proteinKcal - fatKcal) / 4).rounded()

        return MacroGoalPayload(
            calories: targetCalories.rounded(),
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG
        )
    }

    private static func coachStyle(for goalType: GoalType) -> CoachStyle {
        CoachStyle(
            name: LarryMcQuade.name,
            summary: """
            \(LarryMcQuade.title): count your macros, eat real food, hit your protein, and stop making excuses.
            """,
            macroAdvice: { type in
                switch type {
                case .lose:
                    return "Larry says: protein at ~1.1 g per lb, veggies on lock, and don't slash calories below your plan. Macros don't lie — people do."
                case .gain:
                    return "Larry says: ~1 g protein per lb, quality carbs for recovery, healthy fats. Lean gains beat dirty bulking every time, baby."
                case .maintain:
                    return "Larry says: balanced protein-forward meals, mostly whole foods. Adjust portions before you overhaul everything."
                }
            }
        )
    }

    private struct CoachStyle {
        let name: String
        let summary: String
        let macroAdvice: (GoalType) -> String
    }

    static let kgToLb = 2.2046226218
    static let lbToKg = 1.0 / kgToLb
}
