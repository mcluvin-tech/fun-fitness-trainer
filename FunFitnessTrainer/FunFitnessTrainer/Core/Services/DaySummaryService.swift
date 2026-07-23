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

    static func effectiveGoal(base: MacroGoalPayload, exerciseCalorieBonus: Double) -> MacroGoalPayload {
        MacroGoalPayload(
            calories: base.calories + exerciseCalorieBonus,
            proteinG: base.proteinG,
            carbsG: base.carbsG,
            fatG: base.fatG
        )
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
        MacroTotals(
            calories: max(0, goal.calories - consumed.calories),
            proteinG: max(0, goal.proteinG - consumed.proteinG),
            carbsG: max(0, goal.carbsG - consumed.carbsG),
            fatG: max(0, goal.fatG - consumed.fatG)
        )
    }

    static func totals(for meals: [Meal]) -> MacroTotals {
        meals.reduce(MacroTotals()) { acc, meal in
            MacroTotals(
                calories: acc.calories + meal.calories,
                proteinG: acc.proteinG + meal.proteinG,
                carbsG: acc.carbsG + meal.carbsG,
                fatG: acc.fatG + meal.fatG
            )
        }
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
        return pool.randomElement() ?? LarryMcQuade.randomDashboardGreeting()
    }
}
