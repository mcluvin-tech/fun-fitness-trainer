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

    init(name: String, caloriesBurned: Double, durationMinutes: Double? = nil) {
        self.name = name
        self.caloriesBurned = caloriesBurned
        self.durationMinutes = durationMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        caloriesBurned = FlexibleJSONNumber.double(c, .caloriesBurned)
        durationMinutes = FlexibleJSONNumber.optionalDouble(c, .durationMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(caloriesBurned, forKey: .caloriesBurned)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
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
