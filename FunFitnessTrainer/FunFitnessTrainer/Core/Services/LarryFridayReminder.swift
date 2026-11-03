import Foundation
import UserNotifications

/// Friday 7:13 PM local reminders. Date math stays pure so tests do not touch the notification center.
enum LarryFridayReminder {
    static let title = "Larry"
    static let weekday = 6
    static let hour = 19
    static let minute = 13
    static let weeksToSchedule = 8
    static let identifierPrefix = "larry.friday."
    static let destination = "larry"

    static let messages = [
        "Thinking 'bout drinking this weekend and getting bloated like a little bitch?",
        "Are you just gonna blow all your gains on booze this weekend? Okay, little buddy!",
        "Friday. The bar is not a macro plan. You know that, right?",
        "Weekend drinks turn into a Monday you hate. Don't be cute about it.",
        "Booze bloat is not a personality. Water exists.",
        "You can have a drink. You cannot have the whole weekend. Pick.",
        "Larry checking in before you 'just have a couple.' Liar.",
        "Abs do not come in a can. Put the beer down for a minute.",
    ]

    struct Slot: Equatable {
        var fireDate: Date
        var identifier: String
        var body: String
    }

    /// The next Friday at 7:13 PM, then one per week. If that moment has already passed, start next week.
    static func upcomingFridays(from now: Date, calendar: Calendar = .current, count: Int = weeksToSchedule) -> [Date] {
        guard count > 0 else { return [] }
        let first = nextFriday713(from: now, calendar: calendar)
        return (0..<count).compactMap { week in
            calendar.date(byAdding: .day, value: week * 7, to: first)
        }
    }

    static func slots(from now: Date, calendar: Calendar = .current, count: Int = weeksToSchedule) -> [Slot] {
        upcomingFridays(from: now, calendar: calendar, count: count).enumerated().map { index, date in
            Slot(
                fireDate: date,
                identifier: identifier(for: date, calendar: calendar),
                body: messages[index % messages.count]
            )
        }
    }

    static func identifier(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%@%04d-%02d-%02d", identifierPrefix, year, month, day)
    }

    static func nextFriday713(from now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let weekdayNow = calendar.component(.weekday, from: now)
        let daysAhead = (weekday - weekdayNow + 7) % 7
        let day = calendar.date(byAdding: .day, value: daysAhead, to: start) ?? start
        let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        if fire > now { return fire }
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: day) ?? day
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: nextWeek) ?? nextWeek
    }
}

extension LarryFridayReminder {
    /// Asks once. A denial does nothing. An approval schedules the next Fridays.
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await reschedule()
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if granted { await reschedule() }
        case .denied:
            break
        @unknown default:
            break
        }
    }

    /// Moves the next Fridays forward. Does not ask for permission again.
    static func refreshScheduleIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await reschedule()
        default:
            break
        }
    }

    static func reschedule(now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let planned = slots(from: now, calendar: calendar)
        center.removePendingNotificationRequests(withIdentifiers: planned.map(\.identifier))
        for slot in planned {
            var parts = calendar.dateComponents([.year, .month, .day], from: slot.fireDate)
            parts.hour = hour
            parts.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = slot.body
            content.sound = .default
            content.userInfo = ["destination": destination]
            let request = UNNotificationRequest(identifier: slot.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    #if DEBUG
    /// Scheme argument `-larryFridayPreview` fires one banner in 10 seconds. Debug builds only.
    static func schedulePreview(in seconds: TimeInterval = 10) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = messages[0]
        content.sound = .default
        content.userInfo = ["destination": destination]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(identifier: "larry.friday.preview", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    #endif
}

final class LarryNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LarryNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        guard destination == LarryFridayReminder.destination else { return }
        NotificationCenter.default.post(name: .openLarryFromReminder, object: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension Notification.Name {
    static let openLarryFromReminder = Notification.Name("openLarryFromReminder")
}
