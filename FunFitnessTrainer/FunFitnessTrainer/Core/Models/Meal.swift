import Foundation
import SwiftData

@Model
final class Meal {
    var id: UUID
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var loggedAt: Date
    var photoData: Data?
    var itemsJSON: String?
    var assumptionsJSON: String?
    var confidence: Double?
    var isEstimate: Bool
    var barcode: String?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        loggedAt: Date = Date(),
        photoData: Data? = nil,
        items: [String] = [],
        assumptions: [String] = [],
        confidence: Double? = nil,
        isEstimate: Bool = false,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.loggedAt = loggedAt
        self.photoData = photoData
        self.itemsJSON = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) }
        self.assumptionsJSON = (try? JSONEncoder().encode(assumptions)).flatMap { String(data: $0, encoding: .utf8) }
        self.confidence = confidence
        self.isEstimate = isEstimate
        self.barcode = barcode
    }

    var items: [String] {
        guard let itemsJSON,
              let data = itemsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }

    var assumptions: [String] {
        guard let assumptionsJSON,
              let data = assumptionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }
}

struct MacroTotals: Equatable {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG
        )
    }
}
