import Foundation
import SwiftData

@Model
final class ExerciseLog {
    var id: UUID
    var name: String
    var caloriesBurned: Double
    var durationMinutes: Double?
    var loggedAt: Date
    var isEstimate: Bool

    init(
        id: UUID = UUID(),
        name: String,
        caloriesBurned: Double,
        durationMinutes: Double? = nil,
        loggedAt: Date = Date(),
        isEstimate: Bool = true
    ) {
        self.id = id
        self.name = name
        self.caloriesBurned = caloriesBurned
        self.durationMinutes = durationMinutes
        self.loggedAt = loggedAt
        self.isEstimate = isEstimate
    }
}

struct ExercisePayload: Codable, Equatable {
    var name: String
    var caloriesBurned: Double
    var durationMinutes: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case caloriesBurned = "calories_burned"
        case durationMinutes = "duration_minutes"
    }
}

enum ExerciseLogging {
    static func insert(_ payload: ExercisePayload, into context: ModelContext) {
        let log = ExerciseLog(
            name: payload.name,
            caloriesBurned: payload.caloriesBurned,
            durationMinutes: payload.durationMinutes,
            isEstimate: true
        )
        context.insert(log)
        try? context.save()
    }
}
