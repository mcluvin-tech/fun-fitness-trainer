import Foundation

/// How a logged meal landed against what's still left in the day.
/// This is a context score, not a verdict on the food itself.
enum LarryReactionCategory: String, Equatable, CaseIterable {
    case great
    case good
    case neutral
    case questionable
    case bad
    case disaster
}

/// Scores a logged item against the calorie and macro room that was left.
/// The meal name is not an input. The same ice cream can be neutral at noon
/// and a disaster when the day is already spent.
enum LarryNutritionJudge {
    static func category(
        delta: MacroTotals,
        previous: MacroTotals,
        goal: MacroGoalPayload?
    ) -> LarryReactionCategory {
        guard let goal, goal.calories > 1 else {
            return categoryWithoutGoal(delta)
        }

        let afterCalories = previous.calories + delta.calories
        let afterProtein = previous.proteinG + delta.proteinG
        let remainingCalories = goal.calories - previous.calories
        let remainingProtein = goal.proteinG - previous.proteinG
        let overBy = afterCalories - goal.calories
        let proteinPer100 = gramsPer100Calories(protein: delta.proteinG, calories: delta.calories)
        let proteinCoverage = remainingProtein > 8 ? delta.proteinG / remainingProtein : 0
        let mealVsRemaining = remainingCalories > 1 ? delta.calories / remainingCalories : 0

        if isDisaster(
            deltaCalories: delta.calories,
            remainingCalories: remainingCalories,
            overBy: overBy,
            dailyCalories: goal.calories
        ) {
            return .disaster
        }

        if isBad(
            deltaCalories: delta.calories,
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            overBy: overBy,
            proteinPer100: proteinPer100
        ) {
            return .bad
        }

        if overBy <= 30, isGreatProtein(
            delta: delta,
            previousProtein: previous.proteinG,
            afterProtein: afterProtein,
            goalProtein: goal.proteinG,
            remainingProtein: remainingProtein,
            proteinPer100: proteinPer100,
            proteinCoverage: proteinCoverage
        ) {
            return .great
        }

        if overBy <= 90, isHelpful(
            delta: delta,
            proteinPer100: proteinPer100,
            proteinCoverage: proteinCoverage,
            mealVsRemaining: mealVsRemaining
        ) {
            return .good
        }

        if landsOnTarget(
            afterCalories: afterCalories,
            goalCalories: goal.calories,
            remainingCalories: remainingCalories,
            delta: delta,
            proteinPer100: proteinPer100,
            overBy: overBy
        ) {
            return .good
        }

        if isQuestionable(
            delta: delta,
            previous: previous,
            goal: goal,
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            overBy: overBy,
            proteinPer100: proteinPer100,
            mealVsRemaining: mealVsRemaining
        ) {
            return .questionable
        }

        return .neutral
    }

    // MARK: - Bands

    private static func isDisaster(
        deltaCalories: Double,
        remainingCalories: Double,
        overBy: Double,
        dailyCalories: Double
    ) -> Bool {
        let substantial = deltaCalories >= 350
        let multiple = remainingCalories > 0 ? deltaCalories / remainingCalories : 0

        // Ate far past the calories that were actually left.
        if substantial, remainingCalories > 0, multiple >= 2.2, overBy >= 300 {
            return true
        }

        // This meal is most of a large daily overshoot.
        if overBy >= dailyCalories * 0.18, deltaCalories >= overBy * 0.5 {
            return true
        }

        if remainingCalories <= 0, deltaCalories >= 500 {
            return true
        }

        let almostNoRoom = remainingCalories <= dailyCalories * 0.12
        if almostNoRoom, substantial, multiple >= 2, overBy >= 320 {
            return true
        }

        return false
    }

    private static func isBad(
        deltaCalories: Double,
        remainingCalories: Double,
        remainingProtein: Double,
        overBy: Double,
        proteinPer100: Double
    ) -> Bool {
        if remainingCalories <= 0, deltaCalories >= 160 {
            return true
        }

        if overBy >= 150, deltaCalories >= 120, deltaCalories > max(remainingCalories, 0) {
            return true
        }

        // Spent the rest of the calorie budget and missed the protein that was still owed.
        if remainingCalories > 0,
           overBy >= 120,
           proteinPer100 < 4.5,
           remainingProtein > 20,
           deltaCalories > remainingCalories {
            return true
        }

        return false
    }

    private static func isGreatProtein(
        delta: MacroTotals,
        previousProtein: Double,
        afterProtein: Double,
        goalProtein: Double,
        remainingProtein: Double,
        proteinPer100: Double,
        proteinCoverage: Double
    ) -> Bool {
        guard remainingProtein > 8 else { return false }
        let efficient = proteinPer100 >= 6 || delta.proteinG >= 35
        let strong = (delta.proteinG >= 30 && proteinCoverage >= 0.22)
            || proteinCoverage >= 0.4
            || delta.proteinG >= 40
        let closesProtein = afterProtein >= goalProtein
            && previousProtein < goalProtein
            && delta.proteinG >= 18
        return efficient && (strong || closesProtein)
    }

    private static func isHelpful(
        delta: MacroTotals,
        proteinPer100: Double,
        proteinCoverage: Double,
        mealVsRemaining: Double
    ) -> Bool {
        let helpfulProtein = delta.proteinG >= 18 && proteinPer100 >= 4
        let meaningfulCoverage = proteinCoverage >= 0.18 && delta.proteinG >= 15
        let roomLeft = mealVsRemaining < 0.95
        return (helpfulProtein || meaningfulCoverage) && roomLeft
    }

    private static func landsOnTarget(
        afterCalories: Double,
        goalCalories: Double,
        remainingCalories: Double,
        delta: MacroTotals,
        proteinPer100: Double,
        overBy: Double
    ) -> Bool {
        let ratio = afterCalories / goalCalories
        let wasClosingTheDay = remainingCalories < goalCalories * 0.5
        return wasClosingTheDay
            && ratio >= 0.9
            && ratio <= 1.015
            && overBy <= 30
            && delta.proteinG >= 12
            && proteinPer100 >= 3.5
    }

    private static func isQuestionable(
        delta: MacroTotals,
        previous: MacroTotals,
        goal: MacroGoalPayload,
        remainingCalories: Double,
        remainingProtein: Double,
        overBy: Double,
        proteinPer100: Double,
        mealVsRemaining: Double
    ) -> Bool {
        let mealCausedTheOvershoot = overBy > 30 && (delta.calories >= 120 || overBy - delta.calories <= 30)
        if mealCausedTheOvershoot {
            return true
        }

        if remainingCalories <= 0, delta.calories >= 80 {
            return true
        }

        let poorProteinPayoff = proteinPer100 < 5 && remainingProtein > 25
        if remainingCalories > 0,
           mealVsRemaining >= 0.55,
           poorProteinPayoff,
           delta.calories >= 280 {
            return true
        }

        return strainsLeftoverFatOrCarbs(
            delta: delta,
            previous: previous,
            goal: goal,
            remainingProtein: remainingProtein,
            proteinPer100: proteinPer100
        )
    }

    /// A meal that spends the last of the fat or carb budget while protein is still behind.
    private static func strainsLeftoverFatOrCarbs(
        delta: MacroTotals,
        previous: MacroTotals,
        goal: MacroGoalPayload,
        remainingProtein: Double,
        proteinPer100: Double
    ) -> Bool {
        guard remainingProtein > 20, proteinPer100 < 4, delta.calories >= 250 else { return false }

        let remainingFat = goal.fatG - previous.fatG
        let remainingCarbs = goal.carbsG - previous.carbsG
        let blowsFat = goal.fatG > 1
            && remainingFat > 0
            && remainingFat < goal.fatG * 0.35
            && delta.fatG >= max(12, remainingFat * 0.85)
        let blowsCarbs = goal.carbsG > 1
            && remainingCarbs > 0
            && remainingCarbs < goal.carbsG * 0.35
            && delta.carbsG >= max(30, remainingCarbs * 0.85)
        return blowsFat || blowsCarbs
    }

    private static func categoryWithoutGoal(_ delta: MacroTotals) -> LarryReactionCategory {
        let proteinPer100 = gramsPer100Calories(protein: delta.proteinG, calories: delta.calories)
        if delta.calories >= 1400, proteinPer100 < 5 { return .disaster }
        if delta.calories >= 900, proteinPer100 < 4 { return .bad }
        if delta.proteinG >= 40, proteinPer100 >= 7, delta.calories <= 750 { return .great }
        if delta.proteinG >= 20, proteinPer100 >= 5, delta.calories <= 800 { return .good }
        if delta.calories >= 450, proteinPer100 < 3.5 { return .questionable }
        return .neutral
    }

    private static func gramsPer100Calories(protein: Double, calories: Double) -> Double {
        guard calories > 1 else { return protein > 0 ? 40 : 0 }
        return (protein / calories) * 100
    }
}
