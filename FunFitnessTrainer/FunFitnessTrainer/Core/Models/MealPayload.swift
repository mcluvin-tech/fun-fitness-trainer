import Foundation
import SwiftData

/// One food item with its own macro estimate.
struct MealLineItem: Codable, Equatable {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    enum CodingKeys: String, CodingKey {
        case name, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

/// Macro estimate returned by Larry when logging food via voice or text.
struct MealPayload: Codable, Equatable {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    /// Legacy string labels from the API (used to split one combined meal).
    var items: [String]
    /// Preferred: one entry per food with per-item macros.
    var lineItems: [MealLineItem]
    /// Set when macros come from Open Food Facts (barcode or name search).
    var barcode: String?
    var isLabelBacked: Bool
    var assumptions: [String]

    enum CodingKeys: String, CodingKey {
        case name, calories, items
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case lineItems = "line_items"
    }

    init(
        name: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        items: [String] = [],
        lineItems: [MealLineItem] = [],
        barcode: String? = nil,
        isLabelBacked: Bool = false,
        assumptions: [String] = []
    ) {
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.items = items
        self.lineItems = lineItems
        self.barcode = barcode
        self.isLabelBacked = isLabelBacked
        self.assumptions = assumptions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        calories = try c.decode(Double.self, forKey: .calories)
        proteinG = try c.decode(Double.self, forKey: .proteinG)
        carbsG = try c.decode(Double.self, forKey: .carbsG)
        fatG = try c.decode(Double.self, forKey: .fatG)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        lineItems = try c.decodeIfPresent([MealLineItem].self, forKey: .lineItems) ?? []
        barcode = nil
        isLabelBacked = false
        assumptions = []
    }

    /// Each element becomes one row in Today's log.
    func entriesForLogging() -> [MealPayload] {
        if !lineItems.isEmpty {
            return lineItems.map { item in
                let clean = FoodItemNaming.sanitizedLineItem(item)
                return MealPayload(
                    name: clean.name,
                    calories: clean.calories,
                    proteinG: clean.proteinG,
                    carbsG: clean.carbsG,
                    fatG: clean.fatG
                )
            }
        }

        let labels = items
            .map { FoodItemNaming.canonicalName(for: $0) }
            .filter { !$0.isEmpty }
        if labels.count > 1 {
            return distributeTotals(across: labels)
        }

        return [MealPayload(
            name: FoodItemNaming.canonicalName(for: name),
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG
        )]
    }
}

extension MealPayload {
    private func distributeTotals(across labels: [String]) -> [MealPayload] {
        let count = Double(labels.count)
        let share = max(count, 1)
        return labels.map { label in
            MealPayload(
                name: label,
                calories: calories / share,
                proteinG: proteinG / share,
                carbsG: carbsG / share,
                fatG: fatG / share
            )
        }
    }
}

enum MealLogging {
    static func insert(_ payload: MealPayload, into context: ModelContext) {
        _ = insertReturningMeals(payload, into: context)
    }

    @discardableResult
    static func insertReturningMeals(_ payload: MealPayload, into context: ModelContext) -> [Meal] {
        var inserted: [Meal] = []
        var shared: [(name: String, calories: Double, proteinG: Double, loggedAt: Date)] = []
        for entry in payload.entriesForLogging() {
            let name = FoodItemNaming.canonicalName(for: entry.name)
            let meal = Meal(
                name: name,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                assumptions: payload.assumptions,
                isEstimate: !payload.isLabelBacked,
                barcode: payload.barcode
            )
            context.insert(meal)
            inserted.append(meal)
            shared.append((name: name, calories: entry.calories, proteinG: entry.proteinG, loggedAt: meal.loggedAt))
        }
        try? context.save()

        shareToPack(shared)
        return inserted
    }

    /// Update one row in place so a label lookup doesn't duplicate the log or the pack post.
    static func applyLabelData(_ payload: MealPayload, to meal: Meal, in context: ModelContext) {
        let entry = payload.entriesForLogging().first ?? payload
        meal.name = FoodItemNaming.canonicalName(for: entry.name)
        meal.calories = entry.calories
        meal.proteinG = entry.proteinG
        meal.carbsG = entry.carbsG
        meal.fatG = entry.fatG
        meal.isEstimate = !payload.isLabelBacked
        if let barcode = payload.barcode {
            meal.barcode = barcode
        }
        if !payload.assumptions.isEmpty,
           let encoded = try? JSONEncoder().encode(payload.assumptions),
           let json = String(data: encoded, encoding: .utf8) {
            meal.assumptionsJSON = json
        }
        try? context.save()
    }

    /// Swap a just-logged estimate for label-backed Open Food Facts data without adding duplicate rows.
    static func replace(meals: [Meal], with payload: MealPayload, in context: ModelContext) {
        guard !meals.isEmpty else { return }
        for meal in meals {
            context.delete(meal)
        }
        insert(payload, into: context)
    }

    static func shareToPack(_ meals: [(name: String, calories: Double, proteinG: Double, loggedAt: Date)]) {
        // Still syncs every log for now; the feed only surfaces interesting weekly stats.
        Task {
            for item in meals {
                await PackService.shared.shareMeal(
                    name: item.name,
                    calories: item.calories,
                    proteinG: item.proteinG,
                    loggedAt: item.loggedAt
                )
            }
        }
    }

    static func shareToPack(meal: Meal) {
        shareToPack([(
            FoodItemNaming.displayTitle(for: meal.name),
            meal.calories,
            meal.proteinG,
            meal.loggedAt
        )])
    }
}
