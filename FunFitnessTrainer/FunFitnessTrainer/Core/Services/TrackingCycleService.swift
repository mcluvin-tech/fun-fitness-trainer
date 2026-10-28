import Foundation

/// Three-week calibration cycle for macro tracking.
/// Week 1–3: eat to the plan so Larry can see how your body actually responds.
enum TrackingCycleService {
    static let cycleLengthDays = 21
    static let weeksPerCycle = 3

    private static let defaults = UserDefaults.standard
    private static let startedAtKey = "trackingCycleStartedAt"

    static var startedAt: Date? {
        get { defaults.object(forKey: startedAtKey) as? Date }
        set { defaults.set(newValue, forKey: startedAtKey) }
    }

    struct Snapshot: Equatable {
        let startedAt: Date
        /// 1-based cycle number (1, 2, …).
        let cycleNumber: Int
        /// 1...3
        let weekInCycle: Int
        /// 1...21
        let dayInCycle: Int
        let progress: Double
        let cycleLengthDays: Int
    }

    /// Starts the first cycle if one hasn't been recorded yet.
    static func ensureStarted(at date: Date = Date()) {
        guard startedAt == nil else { return }
        startedAt = Calendar.current.startOfDay(for: date)
    }

    /// Begins a fresh 3-week cycle from today.
    static func startNewCycle(at date: Date = Date()) {
        startedAt = Calendar.current.startOfDay(for: date)
    }

    static func snapshot(now: Date = Date()) -> Snapshot? {
        ensureStarted(at: now)
        guard let start = startedAt else { return nil }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        let rawDays = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        let daysElapsed = max(0, rawDays)
        let cycleIndex = daysElapsed / cycleLengthDays
        let dayInCycle = (daysElapsed % cycleLengthDays) + 1
        let weekInCycle = ((dayInCycle - 1) / 7) + 1
        let progress = Double(dayInCycle) / Double(cycleLengthDays)

        return Snapshot(
            startedAt: startDay,
            cycleNumber: cycleIndex + 1,
            weekInCycle: min(weeksPerCycle, weekInCycle),
            dayInCycle: dayInCycle,
            progress: min(1, progress),
            cycleLengthDays: cycleLengthDays
        )
    }
}
