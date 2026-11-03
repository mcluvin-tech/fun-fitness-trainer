import Foundation
import SwiftData
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()
    private let stepGoalIdentifierPrefix = "larry.stepGoal."
    private let mealLogIdentifierPrefix = "larry.mealLog."

    private init() {
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Fires a one-shot Larry notification when the user hits their daily step goal (once per day).
    func notifyStepGoalIfNeeded(steps: Double, goal: Int = HealthActivityPreferences.stepGoal) async {
        guard HealthActivityPreferences.stepNotificationsEnabled else { return }
        guard steps >= Double(goal) else { return }
        guard !HealthActivityPreferences.hasNotifiedStepGoalToday else { return }

        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else { return }
        }

        let content = UNMutableNotificationContent()
        content.title = "Larry McQuade"
        content.body = Self.stepGoalMessage(steps: Int(steps), goal: goal)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(stepGoalIdentifierPrefix)\(HealthActivityPreferences.todayDayKey)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            HealthActivityPreferences.markStepGoalNotifiedToday()
        } catch {
            // Best-effort; next refresh can retry if the day key wasn't marked.
        }
    }

    static func stepGoalMessage(steps: Int, goal: Int) -> String {
        let lines = [
            "\(goal.formatted()) steps. Fine. Don't expect a parade.",
            "You hit \(goal.formatted()). Try not to eat it all back at the drive thru.",
            "\(steps.formatted()) steps logged. I guess your legs still work. Macros next.",
            "\(goal.formatted()) steps? Acceptable. Now stop being a little bitch about your protein.",
            "Step goal done. Discipline tastes better than regret, baby. Log your food.",
        ]
        return lines.randomElement() ?? lines[0]
    }

    /// Schedules the next week of breakfast, lunch, and dinner reminders.
    /// A slot is skipped once that meal is already logged today.
    func refreshMealReminders(now: Date = Date()) async {
        await refreshAuthorizationStatus()
        let pending = await center.pendingNotificationRequests()
        let existing = pending.map(\.identifier).filter { $0.hasPrefix(mealLogIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        guard HealthActivityPreferences.mealLogRemindersEnabled else { return }
        guard appHasFinishedOnboarding else { return }

        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else { return }
        }

        let rivalName = await refreshedRivalName()
        let loggedAt = todaysMealTimestamps()
        let reminders = MealReminderPlanner.reminders(now: now, loggedAt: loggedAt, rivalName: rivalName)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "Larry McQuade"
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let day = MealReminderPlanner.dayKey(reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: "\(mealLogIdentifierPrefix)\(reminder.slot.rawValue).\(day)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private var appHasFinishedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    private func todaysMealTimestamps() -> [Date] {
        let context = PersistenceController.shared.container.mainContext
        let meals = (try? context.fetch(FetchDescriptor<Meal>())) ?? []
        return meals.map(\.loggedAt)
    }

    private func refreshedRivalName() async -> String? {
        guard SupabaseService.shared.isSignedIn, AppConfig.hasBackend else {
            return HealthActivityPreferences.mealReminderRivalName
        }
        guard let challenges = try? await ChallengeService.shared.fetchMyChallenges() else {
            return HealthActivityPreferences.mealReminderRivalName
        }
        let current = FriendChallengeRules.preferredCardChallenge(challenges)
        let name = FriendChallengeRules.displayName(
            current?.opponentDisplayName ?? current?.inviterDisplayName
        )
        HealthActivityPreferences.mealReminderRivalName = name
        return name
    }
}

enum MealReminderSlot: String, CaseIterable {
    case breakfast
    case lunch
    case dinner

    var hour: Int {
        switch self {
        case .breakfast: return 9
        case .lunch: return 12
        case .dinner: return 18
        }
    }

    var minute: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 30
        case .dinner: return 30
        }
    }

    var label: String { rawValue }

    func covers(hour: Int) -> Bool {
        switch self {
        case .breakfast: return (5..<11).contains(hour)
        case .lunch: return (11..<15).contains(hour)
        case .dinner: return (17..<22).contains(hour)
        }
    }
}

struct MealReminder: Equatable {
    let slot: MealReminderSlot
    let fireDate: Date
    let body: String
}

enum MealReminderPlanner {
    static let horizonDays = 14

    static func reminders(
        now: Date,
        loggedAt: [Date],
        rivalName: String?,
        calendar: Calendar = .current
    ) -> [MealReminder] {
        let name = FriendChallengeRules.displayName(rivalName)
        var planned: [MealReminder] = []
        for dayOffset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else {
                continue
            }
            for slot in MealReminderSlot.allCases {
                guard let fireDate = calendar.date(
                    bySettingHour: slot.hour,
                    minute: slot.minute,
                    second: 0,
                    of: day
                ), fireDate > now else { continue }
                if calendar.isDate(day, inSameDayAs: now), alreadyLogged(slot, on: day, loggedAt: loggedAt, calendar: calendar) {
                    continue
                }
                planned.append(MealReminder(
                    slot: slot,
                    fireDate: fireDate,
                    body: message(slot: slot, day: day, rivalName: name, calendar: calendar)
                ))
            }
        }
        return planned
    }

    static func message(slot: MealReminderSlot, day: Date, rivalName: String?, calendar: Calendar = .current) -> String {
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) ?? 1
        if let rivalName, mentionsRival(slot: slot, dayOfYear: dayOfYear) {
            let lines = rivalLines(name: rivalName, meal: slot.label)
            return lines[dayOfYear % lines.count]
        }
        let lines = generalLines(for: slot)
        return lines[dayOfYear % lines.count]
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func mentionsRival(slot: MealReminderSlot, dayOfYear: Int) -> Bool {
        let slotIndex = MealReminderSlot.allCases.firstIndex(of: slot) ?? 0
        return (dayOfYear + slotIndex) % 3 == 0
    }

    private static func alreadyLogged(
        _ slot: MealReminderSlot,
        on day: Date,
        loggedAt: [Date],
        calendar: Calendar
    ) -> Bool {
        loggedAt.contains { date in
            calendar.isDate(date, inSameDayAs: day)
                && slot.covers(hour: calendar.component(.hour, from: date))
        }
    }

    private static func generalLines(for slot: MealReminderSlot) -> [String] {
        switch slot {
        case .breakfast:
            return [
                "Breakfast happened or it didn't. The log should know.",
                "Morning. Protein doesn't count itself.",
                "You eat yet? Log breakfast before Larry starts guessing.",
            ]
        case .lunch:
            return [
                "Lunch o'clock. Log it, or I'm assuming a gas station burrito.",
                "Midday. Did you eat, or are we pretending?",
                "Lunch. Macros don't log themselves, brother.",
            ]
        case .dinner:
            return [
                "Dinner time. Log it before it turns into a mystery calorie.",
                "Evening. If that plate was real, it belongs in the log.",
                "Dinner. Don't make me hear about it from the fridge.",
            ]
        }
    }

    private static func rivalLines(name: String, meal: String) -> [String] {
        [
            "Don't tell me you're gonna eat less protein than that string bean.",
            "\(name)'s been hitting his protein. You logging \(meal), or just thinking about it?",
            "You gonna let that string bean take \(meal) more seriously than you?",
            "Log your \(meal). \(name) looks like a coat hanger and he's still eating.",
        ]
    }
}
