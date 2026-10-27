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
    var quantity: Double?
    var unit: String?
    var preparationState: String?
    var brand: String?
    var nutritionSource: String?
    var nutritionConfidence: String?

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
        barcode: String? = nil,
        quantity: Double = 1,
        unit: String = "serving",
        preparationState: String? = nil,
        brand: String? = nil,
        nutritionSource: String = "generic_estimate",
        nutritionConfidence: String = "medium"
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
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.brand = brand
        self.nutritionSource = nutritionSource
        self.nutritionConfidence = nutritionConfidence
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

    var storedMacros: MacroTotals {
        MacroTotals(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    var sourceKind: MacroTrackingEngine.NutritionSource {
        if let nutritionSource, let parsed = MacroTrackingEngine.NutritionSource(rawValue: nutritionSource) {
            return parsed
        }
        return isEstimate ? .genericEstimate : .database
    }

    var confidenceKind: MacroTrackingEngine.NutritionConfidence {
        if let nutritionConfidence, let parsed = MacroTrackingEngine.NutritionConfidence(rawValue: nutritionConfidence) {
            return parsed
        }
        return isEstimate ? .medium : .high
    }

    func apply(_ payload: MealPayload) {
        name = payload.name
        calories = payload.calories
        proteinG = payload.proteinG
        carbsG = payload.carbsG
        fatG = payload.fatG
        barcode = payload.barcode ?? barcode
        quantity = payload.quantity
        unit = payload.unit
        preparationState = payload.preparationState
        brand = payload.brand
        nutritionSource = payload.source.rawValue
        nutritionConfidence = payload.confidence.rawValue
        isEstimate = payload.confidence != .high
        if !payload.assumptions.isEmpty {
            assumptionsJSON = (try? JSONEncoder().encode(payload.assumptions)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

struct MacroTotals: Equatable, Sendable {
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

    static func - (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: lhs.calories - rhs.calories,
            proteinG: lhs.proteinG - rhs.proteinG,
            carbsG: lhs.carbsG - rhs.carbsG,
            fatG: lhs.fatG - rhs.fatG
        )
    }
}
