import Foundation
import SwiftData

/// One food item with its own macro estimate.
struct MealLineItem: Codable, Equatable {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var quantity: Double?
    var unit: String?
    var preparationState: String?
    var brand: String?
    var source: String?
    var confidence: String?
    /// 0–1 score from vision, when the model sent a number instead of high/medium/low.
    var visionConfidence: Double?

    enum CodingKeys: String, CodingKey {
        case name, calories, quantity, unit, brand, source, confidence
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case preparationState = "preparation_state"
        case preparation
        case visionConfidence = "vision_confidence"
    }

    init(
        name: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        quantity: Double? = nil,
        unit: String? = nil,
        preparationState: String? = nil,
        brand: String? = nil,
        source: String? = nil,
        confidence: String? = nil,
        visionConfidence: Double? = nil
    ) {
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.brand = brand
        self.source = source
        self.confidence = confidence
        self.visionConfidence = visionConfidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        calories = FlexibleJSONNumber.double(c, .calories)
        proteinG = FlexibleJSONNumber.double(c, .proteinG)
        carbsG = FlexibleJSONNumber.double(c, .carbsG)
        fatG = FlexibleJSONNumber.double(c, .fatG)
        quantity = FlexibleJSONNumber.optionalDouble(c, .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        preparationState = try c.decodeIfPresent(String.self, forKey: .preparationState)
            ?? c.decodeIfPresent(String.self, forKey: .preparation)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        if let text = try? c.decode(String.self, forKey: .confidence) {
            confidence = text
            visionConfidence = try c.decodeIfPresent(Double.self, forKey: .visionConfidence)
        } else if let score = try? c.decode(Double.self, forKey: .confidence) {
            visionConfidence = score
            confidence = MacroTrackingEngine.NutritionConfidence.fromVisionScore(score).rawValue
        } else {
            confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
            visionConfidence = try c.decodeIfPresent(Double.self, forKey: .visionConfidence)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(calories, forKey: .calories)
        try c.encode(proteinG, forKey: .proteinG)
        try c.encode(carbsG, forKey: .carbsG)
        try c.encode(fatG, forKey: .fatG)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(preparationState, forKey: .preparationState)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(visionConfidence, forKey: .visionConfidence)
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
    var quantity: Double
    var unit: String
    var preparationState: String?
    var brand: String?
    var source: MacroTrackingEngine.NutritionSource
    var confidence: MacroTrackingEngine.NutritionConfidence

    enum CodingKeys: String, CodingKey {
        case name, calories, items, quantity, unit, brand, source, confidence
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case lineItems = "line_items"
        case preparationState = "preparation_state"
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
        assumptions: [String] = [],
        quantity: Double = 1,
        unit: String = "serving",
        preparationState: String? = nil,
        brand: String? = nil,
        source: MacroTrackingEngine.NutritionSource = .genericEstimate,
        confidence: MacroTrackingEngine.NutritionConfidence? = nil
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
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.brand = brand
        self.source = source
        self.confidence = confidence ?? source.defaultConfidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        calories = FlexibleJSONNumber.double(c, .calories)
        proteinG = FlexibleJSONNumber.double(c, .proteinG)
        carbsG = FlexibleJSONNumber.double(c, .carbsG)
        fatG = FlexibleJSONNumber.double(c, .fatG)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        lineItems = try c.decodeIfPresent([MealLineItem].self, forKey: .lineItems) ?? []
        barcode = nil
        isLabelBacked = false
        assumptions = []
        quantity = FlexibleJSONNumber.optionalDouble(c, .quantity) ?? 1
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "serving"
        preparationState = try c.decodeIfPresent(String.self, forKey: .preparationState)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        if let raw = try c.decodeIfPresent(String.self, forKey: .source),
           let parsed = MacroTrackingEngine.NutritionSource(rawValue: raw) {
            source = parsed
        } else {
            source = .genericEstimate
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .confidence),
           let parsed = MacroTrackingEngine.NutritionConfidence(rawValue: raw) {
            confidence = parsed
        } else {
            confidence = source.defaultConfidence
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(calories, forKey: .calories)
        try c.encode(proteinG, forKey: .proteinG)
        try c.encode(carbsG, forKey: .carbsG)
        try c.encode(fatG, forKey: .fatG)
        try c.encode(items, forKey: .items)
        try c.encode(lineItems, forKey: .lineItems)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encodeIfPresent(preparationState, forKey: .preparationState)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encode(source.rawValue, forKey: .source)
        try c.encode(confidence.rawValue, forKey: .confidence)
    }

    /// Each element becomes one row in Today's log.
    func entriesForLogging() -> [MealPayload] {
        if !lineItems.isEmpty {
            let logged = lineItems.map { item in
                let clean = FoodItemNaming.sanitizedLineItem(item)
                let itemSource = item.source.flatMap(MacroTrackingEngine.NutritionSource.init) ?? source
                let itemConfidence = item.confidence.flatMap(MacroTrackingEngine.NutritionConfidence.init) ?? confidence
                return MealPayload(
                    name: clean.name,
                    calories: clean.calories,
                    proteinG: clean.proteinG,
                    carbsG: clean.carbsG,
                    fatG: clean.fatG,
                    barcode: barcode,
                    isLabelBacked: isLabelBacked,
                    assumptions: assumptions,
                    quantity: item.quantity ?? quantity,
                    unit: item.unit ?? unit,
                    preparationState: item.preparationState ?? preparationState,
                    brand: item.brand ?? brand,
                    source: itemSource,
                    confidence: itemConfidence
                )
            }
            let extras = items
                .map { FoodItemNaming.canonicalName(for: $0) }
                .filter { label in
                    !label.isEmpty
                        && !logged.contains { FoodItemNaming.refersToSameFood($0.name, label) }
                }
            if extras.isEmpty { return logged }
            return logged + estimateEachLabel(extras)
        }

        let labels = items
            .map { FoodItemNaming.canonicalName(for: $0) }
            .filter { !$0.isEmpty }
        if labels.count > 1 {
            return estimateEachLabel(labels)
        }

        let loggedName = FoodItemNaming.stripDashes(
            (barcode == nil) ? FoodItemNaming.canonicalName(for: name) : name
        )
        return [MealPayload(
            name: loggedName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            barcode: barcode,
            isLabelBacked: isLabelBacked,
            assumptions: assumptions,
            quantity: quantity,
            unit: unit,
            preparationState: preparationState,
            brand: brand,
            source: source,
            confidence: confidence
        )]
    }

    /// Split combined labels by estimating each food — never invent equal-share macros.
    private func estimateEachLabel(_ labels: [String]) -> [MealPayload] {
        labels.flatMap { label in
            let entries = FoodAnalysisService.estimateOffline(from: label).entriesForLogging()
            if !entries.isEmpty { return entries }
            return [MealPayload(
                name: label,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                source: .genericEstimate,
                confidence: .low
            )]
        }
    }
}

enum MealLogging {
    static func insert(_ payload: MealPayload, into context: ModelContext) {
        _ = insertReturningMeals(payload, into: context)
    }

    @discardableResult
    static func insertReturningMeals(
        _ payload: MealPayload,
        into context: ModelContext,
        photoData: Data? = nil,
        analysisConfidence: Double? = nil
    ) -> [Meal] {
        let reconciled = FoodAnalysisService.reconcileMealPayload(payload)
        var inserted: [Meal] = []
        var shared: [(name: String, calories: Double, proteinG: Double, loggedAt: Date)] = []
        for entry in reconciled.entriesForLogging() {
            let name = FoodItemNaming.canonicalName(for: entry.name)
            let meal = Meal(
                name: name,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                photoData: photoData,
                items: reconciled.items,
                assumptions: reconciled.assumptions.isEmpty ? entry.assumptions : reconciled.assumptions,
                confidence: analysisConfidence,
                isEstimate: entry.confidence != .high,
                barcode: entry.barcode ?? reconciled.barcode,
                quantity: entry.quantity,
                unit: entry.unit,
                preparationState: entry.preparationState,
                brand: entry.brand,
                nutritionSource: entry.source.rawValue,
                nutritionConfidence: entry.confidence.rawValue
            )
            context.insert(meal)
            inserted.append(meal)
            shared.append((name: name, calories: entry.calories, proteinG: entry.proteinG, loggedAt: meal.loggedAt))
        }
        try? context.save()

        shareToPack(shared)
        return inserted
    }

    /// Modify an existing row in place (quantity corrections). Do not insert a duplicate.
    static func update(_ meal: Meal, with payload: MealPayload, in context: ModelContext) {
        let reconciled = FoodAnalysisService.reconcileMealPayload(payload)
        let entry = reconciled.entriesForLogging().first ?? reconciled
        meal.apply(MealPayload(
            name: FoodItemNaming.canonicalName(for: entry.name),
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            barcode: entry.barcode ?? meal.barcode,
            isLabelBacked: entry.isLabelBacked,
            assumptions: entry.assumptions,
            quantity: entry.quantity,
            unit: entry.unit,
            preparationState: entry.preparationState,
            brand: entry.brand,
            source: entry.source,
            confidence: entry.confidence
        ))
        try? context.save()
        shareToPack(meal: meal)
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

/// Photo and chat models sometimes send calories as strings ("150") or integers.
enum FlexibleJSONNumber {
    static func double<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K,
        default defaultValue: Double = 0
    ) -> Double {
        optionalDouble(container, key) ?? defaultValue
    }

    static func optionalDouble<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        _ key: K
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let text = try? container.decode(String.self, forKey: key) {
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }
}
