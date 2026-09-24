import Foundation

/// Daily calorie adjustment per pound of body-weight change per week (~3,500 kcal per lb).
private let kcalPerLbPerWeek: Double = 3500.0 / 7.0

struct DietGuidance: Equatable {
    let title: String
    let summary: String
    /// Short coaching lines. Not medical advice.
    let points: [String]
}

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

    /// Diet pattern that matches the calorie model already used for the plan.
    static func dietGuidance(for goalType: GoalType, plan: FitnessPlan) -> DietGuidance {
        let calories = Int(plan.targetCalories)
        let protein = Int(plan.macros.proteinG)
        let carbs = Int(plan.macros.carbsG)
        let fat = Int(plan.macros.fatG)
        let delta = Int(plan.dailyCalorieDelta.rounded())

        switch goalType {
        case .gain:
            let surplus = delta > 0 ? "about \(delta) kcal above maintenance" : "a modest surplus over maintenance"
            return DietGuidance(
                title: "Gains diet",
                summary: "Protein-forward lean surplus. Coaching guidance, not medical advice.",
                points: [
                    "Eat about \(calories) kcal — \(surplus) — so training has fuel without a dirty bulk.",
                    "Protein around \(protein) g. Build meals on meat, fish, eggs, Greek yogurt, or a shake.",
                    "Carbs around training (about \(carbs) g): rice, potatoes, oats, fruit.",
                    "Keep fats moderate (about \(fat) g) from olive oil, nuts, and avocado. Don't spend the surplus on junk.",
                ]
            )
        case .lose:
            let deficit = delta < 0 ? "about \(abs(delta)) kcal under maintenance" : "under maintenance"
            return DietGuidance(
                title: "Cut diet",
                summary: "High protein, mostly whole foods. Coaching guidance, not medical advice.",
                points: [
                    "Eat about \(calories) kcal — \(deficit). Don't crash below the plan.",
                    "Protein around \(protein) g from meat, fish, eggs, and Greek yogurt.",
                    "Vegetables on the plate. Carbs (about \(carbs) g) around training, not from junk.",
                    "Fats around \(fat) g. Skip liquid calories.",
                ]
            )
        case .maintain:
            return DietGuidance(
                title: "Maintenance diet",
                summary: "Protein-forward, eat to the plan. Coaching guidance, not medical advice.",
                points: [
                    "Eat about \(calories) kcal — that's maintenance for this setup.",
                    "Protein around \(protein) g. Same foods: meat, fish, eggs, Greek yogurt.",
                    "Carbs about \(carbs) g and fats about \(fat) g. Adjust portions before you overhaul the menu.",
                ]
            )
        }
    }

    /// Larry-voiced answer for "what diet should I follow?"
    /// `topic` is what they asked about. `current` is the plan already saved in setup.
    static func dietCoachingReply(
        topic: GoalType,
        current: GoalType,
        calories: Double?,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        weightKg: Double,
        prefersPlants: Bool
    ) -> String {
        let proteinPerLb = Int((max(weightKg, 40) * kgToLb).rounded())
        var lines: [String] = []

        if topic == .gain && current != .gain {
            lines.append("You want gains. Your saved plan is still \(currentPhrase(current)). A gains diet is a modest surplus, not a dirty bulk and not a medical prescription.")
            lines.append("Protein around \(proteinPerLb) g (about 1 g per lb), carbs around training — rice, potatoes, oats, fruit — and fats from olive oil, nuts, avocado.")
            lines.append("Say \"set my plan for gains\" and I'll lock today's targets to that surplus.")
        } else if let calories, let proteinG, let carbsG, let fatG {
            let plan = provisionalPlan(
                goalType: topic,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG
            )
            lines.append(openingLine(for: topic))
            lines.append(contentsOf: dietGuidance(for: topic, plan: plan).points)
        } else {
            lines.append(openingLine(for: topic))
            lines.append("Finish setup so I can pin real numbers. Protein stays near \(proteinPerLb) g. Surplus only if you're training to add size.")
        }

        if prefersPlants {
            lines.append("No meat? Eggs, dairy, tofu, or a shake can cover the same protein target.")
        }
        if topic != .gain || current == .gain {
            lines.append("Say \"set my plan for gains\" if you want the surplus locked in.")
        }
        lines.append("Coaching guidance, not medical advice.")
        return lines.joined(separator: " ")
    }

    private static func openingLine(for goalType: GoalType) -> String {
        switch goalType {
        case .gain:
            return "You want gains? Fine. Protein first, modest surplus, carbs around the workout. Not a dirty bulk, and not a doctor's note."
        case .lose:
            return "You want the cut. High protein, eat the deficit on the plan, and don't slash it further because you're impatient."
        case .maintain:
            return "Maintenance. Hit the protein, eat to the calorie target, and stop reinventing breakfast every Monday."
        }
    }

    private static func currentPhrase(_ goalType: GoalType) -> String {
        switch goalType {
        case .gain: return "a gains surplus"
        case .lose: return "a cut"
        case .maintain: return "maintenance"
        }
    }

    /// Numbers-only plan so diet copy can quote today's targets without rebuilding TDEE.
    private static func provisionalPlan(
        goalType: GoalType,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double
    ) -> FitnessPlan {
        FitnessPlan(
            goalType: goalType,
            weeklyLbChange: goalType == .gain ? 0.5 : (goalType == .lose ? -0.5 : 0),
            weeksToGoal: nil,
            maintenanceCalories: calories,
            targetCalories: calories,
            dailyCalorieDelta: 0,
            macros: MacroGoalPayload(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG),
            coachStyleName: LarryMcQuade.name,
            coachSummary: "",
            macroAdvice: ""
        )
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
