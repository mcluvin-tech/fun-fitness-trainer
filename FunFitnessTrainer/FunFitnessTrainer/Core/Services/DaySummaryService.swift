import Foundation
import SwiftData

enum DailyLogItem: Identifiable {
    case meal(Meal)
    case exercise(ExerciseLog)

    var id: UUID {
        switch self {
        case .meal(let meal): return meal.id
        case .exercise(let exercise): return exercise.id
        }
    }

    var loggedAt: Date {
        switch self {
        case .meal(let meal): return meal.loggedAt
        case .exercise(let exercise): return exercise.loggedAt
        }
    }
}

enum DaySummaryService {
    static func startOfDay(_ date: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func mealsToday(from meals: [Meal], date: Date = Date()) -> [Meal] {
        let start = startOfDay(date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return meals
            .filter { $0.loggedAt >= start && $0.loggedAt < end }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    static func exercisesToday(from exercises: [ExerciseLog], date: Date = Date()) -> [ExerciseLog] {
        let start = startOfDay(date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return exercises
            .filter { $0.loggedAt >= start && $0.loggedAt < end }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    static func exerciseCaloriesBurned(for exercises: [ExerciseLog]) -> Double {
        exercises.reduce(0) { $0 + $1.caloriesBurned }
    }

    /// Combines manual exercise logs with Apple Health active energy without double-counting.
    /// Display-only: V1 food targets do not include this value.
    static func activityCalorieBonus(
        manualExerciseCalories: Double,
        healthKitActiveEnergy: Double,
        useHealthKit: Bool
    ) -> Double {
        if useHealthKit {
            return max(manualExerciseCalories, healthKitActiveEnergy)
        }
        return manualExerciseCalories
    }

    /// Daily food target from current profile inputs. Ignores DailyGoal snapshots
    /// so a stale row cannot override newer UserSettings.
    static func foodTarget(from settings: UserSettings?) -> MacroGoalPayload? {
        guard let settings else { return nil }
        return GoalCalculator.recommendedMacros(for: settings)
    }

    static func combinedLog(meals: [Meal], exercises: [ExerciseLog]) -> [DailyLogItem] {
        let mealItems = meals
            .sorted { $0.loggedAt < $1.loggedAt }
            .map { DailyLogItem.meal($0) }
        let exerciseItems = exercises
            .sorted { $0.loggedAt < $1.loggedAt }
            .map { DailyLogItem.exercise($0) }
        return mealItems + exerciseItems
    }

    static func remaining(consumed: MacroTotals, goal: MacroGoalPayload) -> MacroTotals {
        MacroTrackingEngine.remaining(consumed: consumed, goal: goal)
    }

    static func totals(for meals: [Meal]) -> MacroTotals {
        MacroTrackingEngine.dailyTotals(meals.map(\.storedMacros))
    }

    static func goal(for date: Date, goals: [DailyGoal]) -> DailyGoal? {
        let start = startOfDay(date)
        return goals.first { Calendar.current.isDate($0.date, inSameDayAs: start) }
    }

    static func needsMorningRitual(settings: UserSettings?) -> Bool {
        guard let settings else { return true }
        guard let last = settings.lastMorningRitualDate else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    static func streakDays(meals: [Meal]) -> Int {
        let days = Set(meals.map { startOfDay($0.loggedAt) })
        var streak = 0
        var cursor = startOfDay()
        while days.contains(cursor) {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    static func pickLocalQuip(phrases: [TrainerPhrase], tag: PhraseTag) -> String? {
        let matches = phrases.filter { $0.tag == tag }
        return matches.randomElement()?.text ?? phrases.filter { $0.tag == .general }.randomElement()?.text
    }

    /// Random Larry line for dashboard greetings (avoids repeating the same tag-only quip).
    static func pickRandomDashboardQuip(phrases: [TrainerPhrase]) -> String {
        let fromDB = phrases.map(\.text)
        let pool = fromDB.isEmpty ? LarryMcQuade.dashboardGreetings : fromDB + LarryMcQuade.welcomeMessages
        let line = pool.randomElement() ?? LarryMcQuade.randomDashboardGreeting()
        return LarrySpeechStyle.clean(line)
    }

    /// One-line coach interpretation of the day for the home status story.
    static func dailyPaceLine(
        consumed: MacroTotals,
        goal: MacroGoalPayload,
        logIsEmpty: Bool,
        now: Date = Date()
    ) -> String {
        if logIsEmpty {
            return "Nothing logged yet. Larry’s waiting."
        }

        let calorieRatio = consumed.calories / max(goal.calories, 1)
        let proteinRatio = consumed.proteinG / max(goal.proteinG, 1)
        let hour = Calendar.current.component(.hour, from: now)
        let dayFraction = max(0.08, min(Double(hour) / 22.0, 1.0))

        if calorieRatio >= 1.05 {
            return "Over target. Adjust the rest of the day."
        }
        if hour >= 20 && calorieRatio < 0.55 {
            return "Way under calories this late. Fuel up or call it."
        }
        if hour >= 18 && proteinRatio < 0.65 {
            return "Protein still needs work tonight."
        }
        if calorieRatio <= dayFraction + 0.12 && calorieRatio >= dayFraction - 0.18 {
            return "You’re on pace today."
        }
        if calorieRatio < dayFraction - 0.18 {
            return "Room to work with. Keep logging."
        }
        return "A little ahead. Ease into the next meal."
    }

    static func contextualLarryLine(
        consumed: MacroTotals,
        goal: MacroGoalPayload,
        latestMealName: String?,
        streakDays: Int,
        focusedKind: MacroGoalKind?,
        phrases: [TrainerPhrase]
    ) -> (text: String, portrait: LarryPortrait, tag: PhraseTag) {
        let proteinRatio = consumed.proteinG / max(goal.proteinG, 1)
        let calorieRatio = consumed.calories / max(goal.calories, 1)
        let hour = Calendar.current.component(.hour, from: Date())

        let result: (text: String, portrait: LarryPortrait, tag: PhraseTag)
        if let name = latestMealName, LarryJunkFood.goesStraightToTheThighs(name) {
            result = (LarryJunkFood.thighLine, .donut, .cheatMeal)
        } else if let focusedKind, focusedKind == .protein, proteinRatio >= 1 {
            result = ("Protein locked. Don’t get soft on me now.", .happy, .crushedIt)
        } else if proteinRatio >= 1, calorieRatio < 1.05 {
            result = ("Protein hit. Fine. I guess that’s acceptable.", .happy, .crushedIt)
        } else if streakDays >= 3, calorieRatio < 0.95 {
            let line = pickLocalQuip(phrases: phrases, tag: .streak)
                ?? "Day \(streakDays). Consistency beats being a little bitch."
            result = (line, .intense, .streak)
        } else if hour >= 20, calorieRatio < 0.5 {
            result = ("It’s late and you’re coasting on fumes. Eat something real.", .intense, .underProtein)
        } else if let name = latestMealName?.lowercased(),
           name.contains("pancake") || name.contains("donut") || name.contains("pizza")
            || name.contains("burger") || name.contains("fries") || name.contains("cookie") {
            let line = pickLocalQuip(phrases: phrases, tag: .cheatMeal)
                ?? "That meal’s got more calories than your last three exes combined."
            result = (line, .donut, .cheatMeal)
        } else if proteinRatio < 0.7 {
            let line = pickLocalQuip(phrases: phrases, tag: .underProtein)
                ?? "Your grandma didn’t skip leg day. Neither should your protein."
            result = (line, .intense, .underProtein)
        } else if calorieRatio >= 0.9 {
            let line = pickLocalQuip(phrases: phrases, tag: .crushedIt)
                ?? "Fine. You’re not embarrassing me today."
            result = (line, .carrots, .crushedIt)
        } else {
            let line = pickRandomDashboardQuip(phrases: phrases)
            result = (line, LarryPortrait.forDashboard(proteinRatio: proteinRatio, calorieRatio: calorieRatio, logIsEmpty: false), .general)
        }
        return (LarrySpeechStyle.clean(result.text), result.portrait, result.tag)
    }
}
