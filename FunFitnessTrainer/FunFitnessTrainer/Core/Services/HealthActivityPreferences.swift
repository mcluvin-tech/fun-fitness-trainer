import Foundation

/// UserDefaults-backed prefs for Apple Health / Watch integration (avoids SwiftData schema wipe).
enum HealthActivityPreferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let connected = "healthKitConnected"
        static let adjustCalories = "adjustCaloriesFromActivity"
        static let stepNotifications = "stepGoalNotificationsEnabled"
        static let stepGoal = "dailyStepGoal"
        static let lastStepGoalNotifiedDay = "lastStepGoalNotifiedDay"
        static let explicitlyDisconnected = "healthKitExplicitlyDisconnected"
        static let mealLogReminders = "mealLogRemindersEnabled"
        static let mealReminderRivalName = "mealReminderRivalName"
    }

    static var isConnected: Bool {
        get { defaults.bool(forKey: Key.connected) }
        set { defaults.set(newValue, forKey: Key.connected) }
    }

    /// True only after the user taps Disconnect — prevents auto-restore.
    static var hasExplicitlyDisconnected: Bool {
        get { defaults.bool(forKey: Key.explicitlyDisconnected) }
        set { defaults.set(newValue, forKey: Key.explicitlyDisconnected) }
    }

    /// When true (default), HealthKit active energy was previously added to today's
    /// food target. V1 no longer does that — TDEE already includes activity level.
    /// Kept so existing UserDefaults values are not rewritten.
    static var adjustCaloriesFromActivity: Bool {
        get {
            if defaults.object(forKey: Key.adjustCalories) == nil { return true }
            return defaults.bool(forKey: Key.adjustCalories)
        }
        set { defaults.set(newValue, forKey: Key.adjustCalories) }
    }

    /// When true (default), Larry notifies when you hit the step goal.
    static var stepNotificationsEnabled: Bool {
        get {
            if defaults.object(forKey: Key.stepNotifications) == nil { return true }
            return defaults.bool(forKey: Key.stepNotifications)
        }
        set { defaults.set(newValue, forKey: Key.stepNotifications) }
    }

    static var stepGoal: Int {
        get {
            let value = defaults.integer(forKey: Key.stepGoal)
            return value > 0 ? value : 10_000
        }
        set { defaults.set(max(1_000, newValue), forKey: Key.stepGoal) }
    }

    /// Calendar day key (yyyy-MM-dd) for which we already fired the step-goal notification.
    static var lastStepGoalNotifiedDay: String? {
        get { defaults.string(forKey: Key.lastStepGoalNotifiedDay) }
        set { defaults.set(newValue, forKey: Key.lastStepGoalNotifiedDay) }
    }

    static var todayDayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static var hasNotifiedStepGoalToday: Bool {
        lastStepGoalNotifiedDay == todayDayKey
    }

    static func markStepGoalNotifiedToday() {
        lastStepGoalNotifiedDay = todayDayKey
    }

    /// Larry nags at breakfast, lunch, and dinner until that meal is logged.
    static var mealLogRemindersEnabled: Bool {
        get {
            if defaults.object(forKey: Key.mealLogReminders) == nil { return true }
            return defaults.bool(forKey: Key.mealLogReminders)
        }
        set { defaults.set(newValue, forKey: Key.mealLogReminders) }
    }

    /// Last known challenge rival. Kept so reminders still work offline.
    static var mealReminderRivalName: String? {
        get { defaults.string(forKey: Key.mealReminderRivalName) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Key.mealReminderRivalName)
            } else {
                defaults.removeObject(forKey: Key.mealReminderRivalName)
            }
        }
    }
}
