import Foundation
import Network
import OSLog
import UIKit

struct FoodAnalysisResult: Codable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var items: [String]
    var confidence: Double
    var assumptions: [String]
    var labelDetected: Bool?
    /// Present when macros came from an on-device barcode → Open Food Facts lookup.
    var barcode: String?
    /// How macros were obtained (local barcode, local OCR, or cloud AI).
    var source: FoodAnalysisSource?
    /// Vision inventory. Preferred over top-level invented macros for plate photos.
    var lineItems: [MealLineItem]

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case items, confidence, assumptions
        case labelDetected = "label_detected"
        case barcode, source
        case lineItems = "line_items"
        case overallConfidence = "overall_confidence"
    }

    init(
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        items: [String],
        lineItems: [MealLineItem] = [],
        confidence: Double,
        assumptions: [String],
        labelDetected: Bool? = nil,
        barcode: String? = nil,
        source: FoodAnalysisSource? = nil
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.items = items
        self.confidence = confidence
        self.assumptions = assumptions
        self.labelDetected = labelDetected
        self.barcode = barcode
        self.source = source
        self.lineItems = lineItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = FlexibleJSONNumber.double(c, .calories)
        proteinG = FlexibleJSONNumber.double(c, .proteinG)
        carbsG = FlexibleJSONNumber.double(c, .carbsG)
        fatG = FlexibleJSONNumber.double(c, .fatG)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        lineItems = try c.decodeIfPresent([MealLineItem].self, forKey: .lineItems) ?? []
        if let overall = FlexibleJSONNumber.optionalDouble(c, .overallConfidence) {
            confidence = overall
        } else {
            confidence = FlexibleJSONNumber.optionalDouble(c, .confidence) ?? 0.5
        }
        assumptions = try c.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        labelDetected = try c.decodeIfPresent(Bool.self, forKey: .labelDetected)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        source = try c.decodeIfPresent(FoodAnalysisSource.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(calories, forKey: .calories)
        try c.encode(proteinG, forKey: .proteinG)
        try c.encode(carbsG, forKey: .carbsG)
        try c.encode(fatG, forKey: .fatG)
        try c.encode(items, forKey: .items)
        try c.encode(lineItems, forKey: .lineItems)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(confidence, forKey: .overallConfidence)
        try c.encode(assumptions, forKey: .assumptions)
        try c.encodeIfPresent(labelDetected, forKey: .labelDetected)
        try c.encodeIfPresent(barcode, forKey: .barcode)
        try c.encodeIfPresent(source, forKey: .source)
    }

    var aiFallbackTotals: MacroTotals {
        MacroTotals(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}

enum FoodAnalysisSource: String, Codable {
    case barcode
    case nutritionLabelOCR = "nutrition_label_ocr"
    case cloudAI = "cloud_ai"
    case offlineEstimate = "offline_estimate"
}

enum FoodAnalysisError: LocalizedError {
    case labelUnreadable
    case networkUnavailable
    case barcodeNeedsLookup(String)

    var errorDescription: String? {
        switch self {
        case .labelUnreadable:
            return "Couldn't read the nutrition label clearly. Enter values below, or scan the barcode."
        case .networkUnavailable:
            return "Confirm the numbers below. We used an on-device estimate."
        case .barcodeNeedsLookup:
            return "Found a barcode. Looking up the product."
        }
    }
}

enum FoodAnalysisService {
    static func analyze(image: UIImage, hint: String?) async throws -> FoodAnalysisResult {
        // Barcode first — cheap and avoids blocking the UI on full-page OCR.
        if let barcode = await FoodPhotoLocalAnalysis.detectBarcode(in: image) {
            do {
                return result(from: try await OpenFoodFactsService.lookup(barcode: barcode))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FoodAnalysisError.barcodeNeedsLookup(barcode)
            }
        }

        let ocrLines = await FoodPhotoLocalAnalysis.recognizedLines(from: image)
        if let label = FoodPhotoLocalAnalysis.parseNutritionFacts(from: ocrLines) {
            return label
        }
        if let digits = FoodPhotoLocalAnalysis.barcodeDigits(in: ocrLines) {
            do {
                return result(from: try await OpenFoodFactsService.lookup(barcode: digits))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FoodAnalysisError.barcodeNeedsLookup(digits)
            }
        }

        guard AppConfig.hasBackend else {
            return mockResult()
        }

        guard FoodAnalysisNetwork.isLikelyAvailable else {
            return offlineAnalysisResult(hint: hint)
        }

        guard let jpeg = image.jpegDataForFoodAnalysis(maxBytes: 420_000, maxEdge: 1600) else {
            throw APIError.invalidResponse
        }
        let base64 = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"

        var body: [String: Any] = ["image_base64": base64]
        if let hint, !hint.isEmpty { body["user_hint"] = hint }
        let ocrText = ocrLines.prefix(80).joined(separator: "\n")
        if !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["ocr_text"] = ocrText
        }

        do {
            let data = try await SupabaseService.shared.invokeFunction(
                name: "analyze-food",
                body: body,
                timeout: 18,
                retries: 0
            )
            if let err = try? JSONDecoder().decode([String: String].self, from: data), let message = err["error"] {
                throw APIError.serverMessage(message)
            }
            var decoded = try JSONDecoder().decode(FoodAnalysisResult.self, from: data)
            decoded.source = .cloudAI
            return decoded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return offlineAnalysisResult(hint: hint)
        }
    }

    private static func offlineAnalysisResult(hint: String?) -> FoodAnalysisResult {
        let payload = offlineEstimate(from: hint)
        let entry = payload.entriesForLogging().first
        return FoodAnalysisResult(
            calories: entry?.calories ?? payload.calories,
            proteinG: entry?.proteinG ?? payload.proteinG,
            carbsG: entry?.carbsG ?? payload.carbsG,
            fatG: entry?.fatG ?? payload.fatG,
            items: [entry?.name ?? payload.name],
            confidence: 0.35,
            assumptions: [
                "Didn't read a barcode or nutrition label. Hold the code in the frame until it locks, or enter numbers.",
            ],
            labelDetected: false,
            barcode: payload.barcode,
            source: .offlineEstimate
        )
    }

    static func isTransientNetworkFailure(_ error: Error) -> Bool {
        if error is FoodAnalysisError { return false }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .timedOut, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .dataNotAllowed, .internationalRoamingOff:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorDataNotAllowed,
            ].contains(ns.code)
        }
        return false
    }

    private static func result(from product: BarcodeProductResult) -> FoodAnalysisResult {
        var assumptions = ["Barcode \(product.barcode) · Open Food Facts"]
        if let serving = product.servingDescription, !serving.isEmpty {
            assumptions.append("Serving: \(serving)")
        }
        return FoodAnalysisResult(
            calories: product.perServing.calories,
            proteinG: product.perServing.proteinG,
            carbsG: product.perServing.carbsG,
            fatG: product.perServing.fatG,
            items: [product.name],
            confidence: 0.95,
            assumptions: assumptions,
            labelDetected: true,
            barcode: product.barcode,
            source: .barcode
        )
    }

    /// Voice/text logging. Each food in the phrase is resolved on its own:
    /// a covering staple, then a branded catalog match, then generic USDA / Open Food Facts.
    static func resolveMealForLogging(from description: String) async -> MealPayload {
        await resolveFoodLog(from: description).meal
    }

    /// Same lookup as `resolveMealForLogging`, plus other real products when the match is uncertain.
    static func resolveFoodLog(from description: String) async -> FoodLookupOutcome {
        let query = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return FoodLookupOutcome(meal: estimateOffline(from: description), choices: [], needsConfirmation: false)
        }

        let source = FoodItemNaming.extractFoodReference(from: query)
            ?? FoodItemNaming.loggedFoodDescription(from: query)
            ?? FoodItemNaming.foodListForEstimation(from: query)
        let segments = foodSegments(from: source)
        guard !segments.isEmpty else {
            return FoodLookupOutcome(meal: estimateOffline(from: description), choices: [], needsConfirmation: false)
        }

        var pieces: [SegmentLookup] = []
        for segment in segments {
            pieces.append(await resolveFoodSegment(segment))
        }
        return outcome(from: pieces)
    }

    /// A label-backed or higher-priority lookup should replace the first guess.
    static func lookupShouldReplace(original: MealPayload, resolved: MealPayload) -> Bool {
        if resolved.isLabelBacked || resolved.source.priority < original.source.priority {
            return true
        }
        return resolved.entriesForLogging().contains { entry in
            entry.isLabelBacked || entry.source.isExact || entry.source.priority < original.source.priority
        }
    }

    private struct SegmentLookup {
        var meal: MealPayload
        var alternatives: [MealPayload]
        var needsConfirmation: Bool
    }

    private static func resolveFoodSegment(_ segment: String) async -> SegmentLookup {
        let phrase = BrandedFoodResolver.correctedPhrase(segment)
        if BrandedFoodResolver.trustedStapleCovers(phrase) {
            return SegmentLookup(meal: estimateOffline(from: phrase), alternatives: [], needsConfirmation: false)
        }

        if BrandedFoodResolver.shouldSearchCatalog(phrase),
           let resolution = await BrandedFoodResolver.resolve(query: phrase) {
            let best = meal(from: resolution.best, userDescription: segment)
            let alternatives = resolution.alternatives.map { meal(from: $0, userDescription: segment) }
            return SegmentLookup(
                meal: best,
                alternatives: alternatives,
                needsConfirmation: resolution.needsConfirmation
            )
        }

        if !BrandedFoodResolver.shouldSearchCatalog(phrase) {
            if let food = await USDAFoodDataService.lookupGeneric(query: phrase) {
                let fromUSDA = mealPayload(from: food, userDescription: segment)
                // #region agent log
                AgentDebugLog.emit(
                    hypothesisId: "B",
                    location: "FoodAnalysisService.resolveFoodSegment",
                    message: "using USDA generic lookup",
                    data: [
                        "query": phrase,
                        "usdaName": food.name,
                        "calories": fromUSDA.calories,
                        "protein": fromUSDA.proteinG,
                    ]
                )
                // #endregion
                return SegmentLookup(meal: fromUSDA, alternatives: [], needsConfirmation: false)
            }

            let offline = estimateOffline(from: phrase)
            if let product = try? await OpenFoodFactsService.searchBestMatch(query: phrase) {
                let fromOFF = mealPayload(from: product, userDescription: segment)
                if !shouldPreferOffline(over: fromOFF, offline: offline, userDescription: segment) {
                    return SegmentLookup(meal: fromOFF, alternatives: [], needsConfirmation: false)
                }
            }
            return SegmentLookup(meal: offline, alternatives: [], needsConfirmation: false)
        }

        return SegmentLookup(meal: estimateOffline(from: phrase), alternatives: [], needsConfirmation: false)
    }

    private static func meal(from hit: BrandedFoodHit, userDescription: String) -> MealPayload {
        let product = BarcodeProductResult(
            barcode: hit.barcode ?? "",
            name: hit.name,
            brand: hit.brand,
            servingDescription: hit.servingDescription,
            imageURL: nil,
            perServing: hit.perServing,
            servingQuantityMl: nil
        )
        var meal = mealPayload(from: product, userDescription: userDescription)
        if meal.barcode?.isEmpty != false {
            meal.barcode = nil
        }
        meal.source = hit.source
        meal.isLabelBacked = true
        meal.confidence = hit.score >= 0.85 ? .high : .medium
        if let brand = hit.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            meal.brand = brand
            if !hit.name.lowercased().contains(brand.lowercased()) {
                meal.name = "\(brand) \(hit.name)"
            } else {
                meal.name = hit.name
            }
        } else {
            meal.name = hit.name
        }
        let origin = hit.source == .usda ? "USDA Branded" : "Open Food Facts"
        var assumption = "\(origin): \(hit.name)"
        if let serving = hit.servingDescription, !serving.isEmpty {
            assumption += " (\(serving))"
        }
        assumption += String(format: ". Match confidence %.0f%%.", hit.score * 100)
        meal.assumptions = [assumption]
        return meal
    }

    private static func outcome(from pieces: [SegmentLookup]) -> FoodLookupOutcome {
        let meals = pieces.map(\.meal)
        let combined = combineResolvedMeals(meals)
        var choices: [FoodLookupChoice] = []
        var needsConfirmation = false
        for (index, piece) in pieces.enumerated() {
            let options = piece.needsConfirmation ? [piece.meal] + piece.alternatives : piece.alternatives
            if piece.needsConfirmation, !options.isEmpty {
                needsConfirmation = true
            }
            for (offset, option) in options.enumerated() {
                var spliced = meals
                spliced[index] = option
                let meal = combineResolvedMeals(spliced)
                let title = option.entriesForLogging().first?.name ?? option.name
                let calories = MacroTrackingEngine.displayCalories(meal.calories)
                let protein = MacroTrackingEngine.displayGrams(meal.proteinG)
                let detail = meal.lineItems.count > 1
                    ? "\(calories) cal with the rest of this meal · \(protein)g protein"
                    : "\(calories) cal · \(protein)g protein"
                choices.append(FoodLookupChoice(
                    id: "\(index)-\(offset)-\(title)-\(calories)",
                    title: title,
                    detail: detail,
                    meal: meal
                ))
            }
        }
        if choices.isEmpty { needsConfirmation = false }
        return FoodLookupOutcome(meal: combined, choices: choices, needsConfirmation: needsConfirmation)
    }

    private static func combineResolvedMeals(_ meals: [MealPayload]) -> MealPayload {
        guard meals.count > 1 else {
            return meals.first ?? MealPayload(name: "Meal", calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
        }
        let items = meals.map { meal -> MealLineItem in
            let entry = meal.entriesForLogging().first ?? meal
            return MealLineItem(
                name: entry.name,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                quantity: entry.quantity,
                unit: entry.unit,
                preparationState: entry.preparationState,
                brand: entry.brand,
                source: entry.source.rawValue,
                confidence: entry.confidence.rawValue
            )
        }
        let totals = MacroTrackingEngine.recipeTotals(items.map {
            MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        })
        let worst = meals.map(\.source).max { $0.priority < $1.priority } ?? .genericEstimate
        let protected = meals.allSatisfy { $0.isLabelBacked || $0.source.isExact }
        let confidence: MacroTrackingEngine.NutritionConfidence = meals.contains { $0.confidence == .low } ? .low : .medium
        return MealPayload(
            name: "Meal",
            calories: totals.calories,
            proteinG: totals.proteinG,
            carbsG: totals.carbsG,
            fatG: totals.fatG,
            lineItems: items,
            isLabelBacked: protected,
            assumptions: meals.flatMap(\.assumptions),
            source: worst,
            confidence: confidence
        )
    }

    static func mealPayload(from food: USDAGenericFood, userDescription: String) -> MealPayload {
        let portion = FoodQuantity.parse(from: userDescription)
        let totals = food.per100g.scaled(by: food.grams / 100)
        var assumptions = [
            "USDA \(food.dataType): \(FoodItemNaming.stripDashes(food.name)), \(Int(food.per100g.calories.rounded())) kcal / \(String(format: "%.1f", food.per100g.proteinG)) g protein per 100 g.",
        ]
        if food.assumedPortion {
            assumptions.append("No amount given. Used \(food.portionLabel) (\(Int(food.grams.rounded())) g).")
        }
        return MealPayload(
            name: FoodItemNaming.canonicalName(for: userDescription),
            calories: totals.calories,
            proteinG: totals.proteinG,
            carbsG: totals.carbsG,
            fatG: totals.fatG,
            assumptions: assumptions,
            quantity: food.quantity,
            unit: food.unit,
            preparationState: portion.preparation == .unknown ? nil : portion.preparation.rawValue,
            source: .usda,
            confidence: .medium
        )
    }

    static func mealPayload(from product: BarcodeProductResult, userDescription: String) -> MealPayload {
        let portion = FoodQuantity.parse(from: userDescription)
        let multiplier = servingMultiplier(userDescription: userDescription, product: product)
        let scaled = product.perServing.scaled(by: multiplier)
        // Prefer the user's quantity-aware label ("3 Eggs") over a generic OFF product name.
        let userLabel = FoodItemNaming.canonicalName(for: userDescription)
        let displayName = hasKnownNutrition(for: userLabel)
            ? userLabel
            : FoodItemNaming.canonicalName(for: product.name)
        var assumption = "Open Food Facts: \(product.name)"
        if let serving = product.servingDescription, !serving.isEmpty {
            assumption += " (\(serving))"
        }
        if multiplier != 1 {
            assumption += String(format: ". Scaled ×%.2f for your portion", multiplier)
        }

        return MealPayload(
            name: displayName,
            calories: scaled.calories,
            proteinG: scaled.proteinG,
            carbsG: scaled.carbsG,
            fatG: scaled.fatG,
            barcode: product.barcode,
            isLabelBacked: true,
            assumptions: [assumption],
            quantity: portion.amount,
            unit: portion.unit.displayName.isEmpty ? "serving" : portion.unit.displayName,
            preparationState: portion.preparation == .unknown ? nil : portion.preparation.rawValue,
            brand: product.brand,
            source: .manufacturer,
            confidence: .high
        )
    }

    /// Scales OFF per-serving macros by the user's stated portion (oz, slices, counts).
    private static func servingMultiplier(userDescription: String, product: BarcodeProductResult) -> Double {
        let portion = FoodQuantity.parse(from: userDescription)

        if portion.unit == .fluidOunce || portion.unit == .milliliter || portion.unit == .cup {
            let productOz: Double
            if let ml = product.servingQuantityMl, ml > 0 {
                productOz = ml / FoodUnit.mlPerFluidOunce
            } else {
                productOz = 8
            }
            let userOz = portion.unit.toMilliliters(portion.amount).map { $0 / FoodUnit.mlPerFluidOunce } ?? portion.amount
            return max(userOz / max(productOz, 1), 0.05)
        }

        if portion.unit.isMass {
            let serving = (product.servingDescription ?? "").lowercased()
            if let grams = FoodQuantity.parseGrams(in: serving) ?? FoodQuantity.parseOunces(in: serving).map({ $0 * FoodUnit.gramsPerOunce }) {
                let consumedGrams = portion.unit.toGrams(portion.amount) ?? portion.amount
                return MacroTrackingEngine.multiplier(consumed: consumedGrams, reference: grams)
            }
        }

        guard abs(portion.amount - 1) > 0.001 else { return 1 }

        let serving = (product.servingDescription ?? "").lowercased()
        let productName = product.name.lowercased()
        let countableHints = ["slice", "egg", "piece", "unit", "each", "biscuit", "cookie", "bar"]
        let looksPerUnit = countableHints.contains { serving.contains($0) || productName.contains($0) }
            || hasKnownNutrition(for: userDescription)
            || serving.isEmpty
            || serving.contains("1 ")
            || serving.hasPrefix("1")
        return looksPerUnit ? portion.amount : 1
    }

    /// When OFF returns ~1 serving but the user said "3 eggs" / "2 slices", keep the scaled offline staple.
    private static func shouldPreferOffline(
        over off: MealPayload,
        offline: MealPayload,
        userDescription: String
    ) -> Bool {
        guard hasKnownNutrition(for: userDescription) else { return false }
        let qty = Double(FoodItemNaming.parseQuantity(in: userDescription.lowercased()))
        guard qty > 1 else { return false }
        let offlineEntry = offline.entriesForLogging().first ?? offline
        guard offlineEntry.calories > 0 else { return false }
        // OFF under-counted vs offline (common when multiplier stayed at 1).
        return off.calories < offlineEntry.calories * 0.7
    }

    /// Fix GPT / estimate rows so quantity in the name scales macros.
    /// Never overwrite user-provided or label/manufacturer data with a generic staple.
    static func reconcileEstimate(_ entry: MealPayload) -> MealPayload {
        let name = FoodItemNaming.canonicalName(for: entry.name)
        if entry.isLabelBacked || entry.source.isExact {
            var copy = entry
            copy.name = name
            return copy
        }

        if looksLikeMixedStapleDish(entry.name) || looksLikeMixedStapleDish(name) {
            if entry.calories > 0 {
                var copy = entry
                copy.name = name
                copy.confidence = .low
                return copy
            }
        }

        let query = FoodQuantity.queryForScaling(name: entry.name, quantity: entry.quantity, unit: entry.unit)
        if let scaled = StapleNutritionDatabase.scale(for: query)
            ?? StapleNutritionDatabase.scale(for: entry.name)
            ?? StapleNutritionDatabase.scale(for: name) {
            let labeled = FoodQuantity.queryForScaling(
                name: entry.name,
                quantity: scaled.portion.amount,
                unit: scaled.portion.unit.displayName.isEmpty ? nil : scaled.portion.unit.displayName
            )
            return payload(from: scaled, fallbackName: FoodItemNaming.canonicalName(for: labeled), barcode: entry.barcode)
        }
        guard hasKnownNutrition(for: name),
              let offline = estimateForStoredName(name) else {
            var copy = entry
            copy.name = name
            if !FoodEstimateGate.isPlausible(text: name, calories: copy.calories, proteinG: copy.proteinG) {
                let replacement = estimateOffline(from: name)
                var fixed = replacement.entriesForLogging().first ?? replacement
                fixed.assumptions.append("Rejected an implausible estimate for this food and used its own reference.")
                return fixed
            }
            return copy
        }
        return MealPayload(
            name: name,
            calories: offline.calories,
            proteinG: offline.proteinG,
            carbsG: offline.carbsG,
            fatG: offline.fatG,
            barcode: entry.barcode,
            isLabelBacked: false,
            assumptions: offline.assumptions.isEmpty ? entry.assumptions : offline.assumptions,
            quantity: offline.quantity,
            unit: offline.unit,
            preparationState: offline.preparationState,
            brand: offline.brand,
            source: offline.source,
            confidence: offline.confidence
        )
    }

    /// Reconcile a full GPT/offline payload (including multi-item line_items) before insert.
    static func reconcileMealPayload(_ payload: MealPayload) -> MealPayload {
        if !payload.lineItems.isEmpty {
            let reconciledItems = payload.lineItems.map { item -> MealLineItem in
                let asPayload = MealPayload(
                    name: item.name,
                    calories: item.calories,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG,
                    isLabelBacked: payload.isLabelBacked,
                    quantity: item.quantity ?? payload.quantity,
                    unit: item.unit ?? payload.unit,
                    preparationState: item.preparationState ?? payload.preparationState,
                    brand: item.brand ?? payload.brand,
                    source: item.source.flatMap(MacroTrackingEngine.NutritionSource.init) ?? payload.source,
                    confidence: item.confidence.flatMap(MacroTrackingEngine.NutritionConfidence.init)
                )
                let fixed = reconcileEstimate(asPayload)
                return MealLineItem(
                    name: fixed.name,
                    calories: fixed.calories,
                    proteinG: fixed.proteinG,
                    carbsG: fixed.carbsG,
                    fatG: fixed.fatG,
                    quantity: fixed.quantity,
                    unit: fixed.unit,
                    preparationState: fixed.preparationState,
                    brand: fixed.brand,
                    source: fixed.source.rawValue,
                    confidence: fixed.confidence.rawValue
                )
            }
            let totals = MacroTrackingEngine.recipeTotals(reconciledItems.map {
                MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
            })
            return MealPayload(
                name: payload.name,
                calories: totals.calories,
                proteinG: totals.proteinG,
                carbsG: totals.carbsG,
                fatG: totals.fatG,
                items: payload.items,
                lineItems: reconciledItems,
                barcode: payload.barcode,
                isLabelBacked: payload.isLabelBacked,
                assumptions: payload.assumptions,
                quantity: payload.quantity,
                unit: payload.unit,
                preparationState: payload.preparationState,
                brand: payload.brand,
                source: payload.source,
                confidence: payload.confidence
            )
        }

        return reconcileEstimate(payload)
    }

    /// "A pint of beer" must scale from the words the user said, even if the model logged plain "beer".
    static func applyingSpokenPortions(_ meal: MealPayload, utterance: String) -> MealPayload {
        let segments = foodSegments(from: utterance)
        guard !segments.isEmpty else { return meal }

        if meal.lineItems.isEmpty {
            guard segments.count == 1, let scaled = StapleNutritionDatabase.scale(for: segments[0]) else {
                return meal
            }
            let label = FoodItemNaming.logLabel(from: segments[0], quantity: scaled.portion.amount)
            return payload(from: scaled, fallbackName: label, barcode: meal.barcode)
        }

        let items = meal.lineItems.map { item -> MealLineItem in
            guard let segment = segments.first(where: { FoodItemNaming.refersToSameFood($0, item.name) }),
                  let scaled = StapleNutritionDatabase.scale(for: segment) else {
                return item
            }
            let label = FoodItemNaming.logLabel(from: segment, quantity: scaled.portion.amount)
            return lineItem(from: scaled, name: label)
        }
        let totals = MacroTrackingEngine.recipeTotals(items.map {
            MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        })
        return MealPayload(
            name: meal.name,
            calories: totals.calories,
            proteinG: totals.proteinG,
            carbsG: totals.carbsG,
            fatG: totals.fatG,
            items: meal.items,
            lineItems: items,
            barcode: meal.barcode,
            isLabelBacked: meal.isLabelBacked,
            assumptions: meal.assumptions,
            quantity: meal.quantity,
            unit: meal.unit,
            preparationState: meal.preparationState,
            brand: meal.brand,
            source: meal.source,
            confidence: meal.confidence
        )
    }

    /// Adds foods the user named that a partial model reply left out.
    /// "I had eggs, toast, clementines, and an apple" must not stop after eggs and toast.
    static func completingMissingFoods(_ payload: MealPayload, from utterance: String) -> MealPayload {
        let segments = foodSegments(from: utterance)
        guard segments.count > 1 else { return payload }

        let existing: [MealLineItem]
        if !payload.lineItems.isEmpty {
            existing = payload.lineItems
        } else {
            existing = payload.entriesForLogging().map { entry in
                MealLineItem(
                    name: entry.name,
                    calories: entry.calories,
                    proteinG: entry.proteinG,
                    carbsG: entry.carbsG,
                    fatG: entry.fatG,
                    quantity: entry.quantity,
                    unit: entry.unit,
                    preparationState: entry.preparationState,
                    brand: entry.brand,
                    source: entry.source.rawValue,
                    confidence: entry.confidence.rawValue
                )
            }
        }

        let missing = segments.filter { segment in
            !existing.contains { FoodItemNaming.refersToSameFood($0.name, segment) }
        }
        guard !missing.isEmpty else { return payload }

        let kept = existing.filter { item in
            segments.contains { FoodItemNaming.refersToSameFood(item.name, $0) }
        }
        let lineItems = kept + missing.map { estimateSegment($0) }
        let totals = MacroTrackingEngine.recipeTotals(lineItems.map {
            MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        })
        return MealPayload(
            name: lineItems.count == 1 ? lineItems[0].name : "Meal",
            calories: totals.calories,
            proteinG: totals.proteinG,
            carbsG: totals.carbsG,
            fatG: totals.fatG,
            items: payload.items,
            lineItems: lineItems,
            barcode: payload.barcode,
            isLabelBacked: payload.isLabelBacked,
            assumptions: payload.assumptions,
            quantity: payload.quantity,
            unit: payload.unit,
            preparationState: payload.preparationState,
            brand: payload.brand,
            source: payload.source,
            confidence: payload.confidence
        )
    }

    /// Stored values are the source of truth. Only repair the known plant-milk ×ounce bug.
    static func displayMacros(
        name: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double
    ) -> MacroTotals {
        if let repaired = repairedIceMacros(name: name, storedCalories: calories) {
            return repaired
        }
        if let repaired = repairedPlantMilkMacros(name: name, storedCalories: calories) {
            return repaired
        }
        if let repaired = repairedExplodedPortion(
            name: name,
            storedCalories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG
        ) {
            return repaired
        }
        return MacroTotals(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    /// "8 oz milk" and "8 fl oz milk" used to multiply the per-100 g row by 8. Rewrite only obvious multiples.
    private static func repairedExplodedPortion(
        name: String,
        storedCalories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double
    ) -> MacroTotals? {
        guard storedCalories >= 400 else { return nil }
        let lower = name.lowercased()
        // "8 fl oz" is not a weight-ounce match: the number is not sitting directly on "oz".
        let hasMeasure = FoodQuantity.parseOunces(in: lower) != nil
            || FoodQuantity.parseExplicitFluidOunces(in: lower) != nil
            || FoodQuantity.pintFluidOunces(in: lower) != nil
            || FoodQuantity.parseGrams(in: lower) != nil
            || FoodQuantity.parseMilliliters(in: lower) != nil
            || lower.contains("cup")
        guard hasMeasure else { return nil }
        guard let scaled = StapleNutritionDatabase.scale(for: name), scaled.totals.calories > 0 else { return nil }
        guard storedCalories / scaled.totals.calories >= 2.5 else { return nil }
        _ = proteinG
        _ = carbsG
        _ = fatG
        return scaled.totals
    }

    /// "Ice" logged as 200×N servings because "5 calories" was parsed as quantity 5.
    private static func repairedIceMacros(name: String, storedCalories: Double) -> MacroTotals? {
        guard StapleNutritionDatabase.looksLikePlainIce(name) else { return nil }
        guard storedCalories >= 20 else { return nil }
        return MacroTotals(calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }

    /// Fixes carton plant-milk rows, including the old 200×ounce bug (16 oz → 3200 cal).
    private static func repairedPlantMilkMacros(name: String, storedCalories: Double) -> MacroTotals? {
        let lower = name.lowercased()
        let isPlant =
            lower.contains("coconut milk") || lower.contains("almond milk")
            || lower.contains("oat milk") || lower.contains("soy milk") || lower.contains("soymilk")
        guard isPlant else { return nil }

        var query = name
        // Legacy bug: parseQuantity treated "16" from "16 oz" as a count → 200×16.
        if FoodItemNaming.parseFluidOunces(in: lower) == nil, storedCalories >= 400 {
            let presumedOz = Int((storedCalories / 200).rounded())
            if (2...64).contains(presumedOz) {
                let food = FoodItemNaming.sanitizeSegment(name)
                query = "\(presumedOz) oz \(food.isEmpty ? name : food)"
            }
        }

        guard let entry = estimateOffline(from: query).entriesForLogging().first else { return nil }
        return MacroTotals(
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG
        )
    }

    /// Rough offline macro estimate from a spoken or typed food description.
    static func estimateOffline(from description: String) -> MealPayload {
        let source = FoodItemNaming.extractFoodReference(from: description)
            ?? FoodItemNaming.loggedFoodDescription(from: description)
            ?? FoodItemNaming.foodListForEstimation(from: description)
        let segments = foodSegments(from: source)
        let lineItems = segments.map { estimateSegment($0) }

        if lineItems.count > 1 {
            let totals = MacroTrackingEngine.recipeTotals(lineItems.map {
                MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
            })
            let lowest = lineItems.compactMap { $0.confidence.flatMap(MacroTrackingEngine.NutritionConfidence.init) }
            let confidence: MacroTrackingEngine.NutritionConfidence = lowest.contains(.low) ? .low : (lowest.contains(.medium) ? .medium : .medium)
            return applyUserStatedMacros(
                MealPayload(
                    name: "Meal",
                    calories: totals.calories,
                    proteinG: totals.proteinG,
                    carbsG: totals.carbsG,
                    fatG: totals.fatG,
                    lineItems: lineItems,
                    source: .genericEstimate,
                    confidence: confidence
                ),
                from: description
            )
        }

        if let only = lineItems.first {
            return applyUserStatedMacros(payload(from: only), from: description)
        }

        return applyUserStatedMacros(
            MealPayload(
                name: "Meal",
                calories: 400,
                proteinG: 25,
                carbsG: 35,
                fatG: 12,
                source: .genericEstimate,
                confidence: .low
            ),
            from: description
        )
    }

    /// "ice for 5 calories" must log 5 calories, not a generic 200 × 5 servings.
    static func applyUserStatedMacros(_ payload: MealPayload, from utterance: String) -> MealPayload {
        let stated = MacroTrackingEngine.parseUserMacros(from: utterance)
        guard stated.hasAny else { return payload }

        var copy = payload
        func overlay(_ calories: Double, proteinG: Double, carbsG: Double, fatG: Double) -> (Double, Double, Double, Double) {
            var cal = calories
            var protein = proteinG
            var carbs = carbsG
            var fat = fatG
            if let statedCal = stated.calories {
                if stated.proteinG == nil, stated.carbsG == nil, stated.fatG == nil, calories > 1 {
                    let factor = statedCal / calories
                    protein *= factor
                    carbs *= factor
                    fat *= factor
                }
                cal = statedCal
            }
            if let value = stated.proteinG { protein = value }
            if let value = stated.carbsG { carbs = value }
            if let value = stated.fatG { fat = value }
            return (cal, protein, carbs, fat)
        }

        if copy.lineItems.count == 1, var item = copy.lineItems.first {
            let macros = overlay(item.calories, proteinG: item.proteinG, carbsG: item.carbsG, fatG: item.fatG)
            item.calories = macros.0
            item.proteinG = macros.1
            item.carbsG = macros.2
            item.fatG = macros.3
            item.source = MacroTrackingEngine.NutritionSource.userProvided.rawValue
            item.confidence = MacroTrackingEngine.NutritionConfidence.high.rawValue
            copy.lineItems = [item]
            copy.calories = item.calories
            copy.proteinG = item.proteinG
            copy.carbsG = item.carbsG
            copy.fatG = item.fatG
        } else {
            let macros = overlay(copy.calories, proteinG: copy.proteinG, carbsG: copy.carbsG, fatG: copy.fatG)
            copy.calories = macros.0
            copy.proteinG = macros.1
            copy.carbsG = macros.2
            copy.fatG = macros.3
        }
        copy.source = .userProvided
        copy.confidence = .high
        return copy
    }

    /// Re-estimate macros for a stored log label (USDA-based offline lookup).
    static func estimateForStoredName(_ name: String) -> MealPayload? {
        guard hasKnownNutrition(for: name) else { return nil }
        let estimate = estimateOffline(from: name)
        return estimate.entriesForLogging().first
    }

    /// Whether a local staple or USDA-style entry exists for this label.
    static func hasKnownNutrition(for name: String) -> Bool {
        if StapleNutritionDatabase.match(in: name) != nil { return true }
        let text = name.lowercased()
        let sanitized = FoodItemNaming.sanitizeSegment(name).lowercased()
        let known = [
            "sandwich", "salad", "burger", "pizza", "mcdonald",
            "power green", "powder green", "twix", "candy", "chocolate bar",
        ]
        return known.contains { text.contains($0) || sanitized.contains($0) }
    }

    /// Whole-token match so "chip" does not hit "chipotle".
    private static func matchesFoodToken(_ text: String, _ token: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b",
            options: .caseInsensitive
        ) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
    }

    /// Splits multi-food utterances joined by commas, "and", "plus", "+", or ";".
    private static func foodSegments(from description: String) -> [String] {
        let text = FoodItemNaming.foodListForEstimation(from: description)

        var normalized = text
        let replacements: [(String, String)] = [
            (#"\s*&\s*"#, ", "),
            (#"\s*\+\s*"#, ", "),
            (#"\s*;\s*"#, ", "),
            (#"\.\s+"#, ", "),
            (#"\s+plus\s+"#, ", "),
            (#"\s+and\s+"#, ", "),
            (#"\s+with\s+"#, ", "),
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: replacement)
        }

        let parts = normalized
            .split(separator: ",")
            .map { part -> String in
                var s = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".,!;:"))
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { part in
                !part.isEmpty && !FoodItemNaming.sanitizeSegment(part).isEmpty
            }

        return parts.isEmpty ? [text] : parts
    }

    private static func estimateSegment(_ segment: String) -> MealLineItem {
        let sourceLower = segment.lowercased()
        let portion = FoodQuantity.parse(from: segment)
        let name = FoodItemNaming.logLabel(from: segment, quantity: portion.amount)

        if sourceLower.contains("sandwich") {
            return genericItem(name: name, calories: 450, proteinG: 28, carbsG: 40, fatG: 18, quantity: loggedCount(portion), confidence: .low)
        }
        if let scaled = StapleNutritionDatabase.scale(for: segment) {
            let drinkKeys: Set<String> = [
                "regular_beer", "light_beer", "na_beer", "wine", "soda", "diet_soda", "spirits",
            ]
            if drinkKeys.contains(scaled.entry.key) {
                // #region agent log
                AgentDebugLog.emit(
                    hypothesisId: "A",
                    location: "FoodAnalysisService.estimateSegment",
                    message: "drink scaled from staple",
                    data: [
                        "segment": segment,
                        "key": scaled.entry.key,
                        "portion": FoodQuantity.describe(scaled.portion),
                        "multiplier": scaled.multiplier,
                        "calories": scaled.totals.calories,
                        "protein": scaled.totals.proteinG,
                        "carbs": scaled.totals.carbsG,
                        "fat": scaled.totals.fatG,
                        "runId": "post-fix",
                    ]
                )
                // #endregion
            }
            return lineItem(from: scaled, name: name)
        }
        if sourceLower.contains("salad") {
            let hearty = ["chicken", "tuna", "salmon", "steak", "shrimp", "egg"].contains { sourceLower.contains($0) }
            if hearty {
                return genericItem(name: name, calories: 420, proteinG: 32, carbsG: 16, fatG: 16, quantity: loggedCount(portion), confidence: .low)
            }
            return genericItem(name: name, calories: 150, proteinG: 4, carbsG: 12, fatG: 8, quantity: loggedCount(portion), confidence: .low)
        }
        if sourceLower.contains("burger") || sourceLower.contains("pizza") || sourceLower.contains("mcdonald") {
            return genericItem(
                name: name,
                calories: 650,
                proteinG: 28,
                carbsG: 55,
                fatG: 32,
                quantity: loggedCount(portion),
                confidence: .low
            )
        }
        if sourceLower.contains("power green") || sourceLower.contains("powder green") {
            return genericItem(name: name, calories: 450, proteinG: 28, carbsG: 45, fatG: 18, quantity: loggedCount(portion), confidence: .low)
        }
        if sourceLower.contains("twix") || sourceLower.contains("candy") || sourceLower.contains("chocolate bar") {
            return genericItem(name: name, calories: 250, proteinG: 2, carbsG: 34, fatG: 12, quantity: loggedCount(portion), confidence: .low)
        }
        if isCoffeeDrink(FoodItemNaming.sanitizeSegment(segment).lowercased()) || sourceLower.contains("starbucks") {
            let drinkQty = drinkServings(portion)
            let drink = estimateCoffeeDrink(name: name, text: sourceLower, sourceLower: sourceLower, quantity: drinkQty)
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "A",
                location: "FoodAnalysisService.estimateSegment",
                message: "beverage routed through coffee estimator",
                data: [
                    "segment": segment,
                    "isBeer": sourceLower.contains("beer"),
                    "isWine": sourceLower.contains("wine"),
                    "portionUnit": String(describing: portion.unit),
                    "portionAmount": portion.amount,
                    "drinkQty": drinkQty,
                    "calories": drink.calories,
                    "protein": drink.proteinG,
                    "carbs": drink.carbsG,
                    "fat": drink.fatG,
                ]
            )
            // #endregion
            return drink
        }

        return unidentifiedFoodItem(name: name, segment: segment, portion: portion)
    }

    /// Last resort after the food itself has no reference. Never copy another food's cup or pint.
    private static func unidentifiedFoodItem(name: String, segment: String, portion: FoodPortion) -> MealLineItem {
        let lower = segment.lowercased()
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "A",
            location: "FoodAnalysisService.unidentifiedFoodItem",
            message: "no food identity match",
            data: [
                "segment": segment,
                "portionUnit": String(describing: portion.unit),
                "portionAmount": portion.amount,
            ]
        )
        // #endregion
        let leafy = ["lettuce", "kale", "arugula", "cucumber", "zucchini", "asparagus", "greens"]
        if leafy.contains(where: { lower.contains($0) }) {
            let cups = portion.unit == .cup ? max(portion.amount, 0.5) : 1
            return genericItem(name: name, calories: 15, proteinG: 1.2, carbsG: 2.5, fatG: 0.2, quantity: cups, unit: "cup", confidence: .low)
        }
        if ["pork", "lamb", "brisket"].contains(where: { lower.contains($0) }) {
            let oz = portion.unit == .ounce ? portion.amount : 6
            return genericItem(name: name, calories: 60, proteinG: 7, carbsG: 0, fatG: 3.5, quantity: oz, unit: "oz", confidence: .low)
        }
        let protein = 8.0
        let carbs = 30.0
        let fat = 10.0
        return genericItem(
            name: name,
            calories: MacroTrackingEngine.caloriesFromMacros(proteinG: protein, carbsG: carbs, fatG: fat),
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            quantity: loggedCount(portion),
            unit: "serving",
            confidence: .low
        )
    }

    /// Ounces and grams are not a serving count. "8 oz burger" is one burger, not eight.
    private static func loggedCount(_ portion: FoodPortion) -> Double {
        guard portion.unit.isCountable else { return 1 }
        return max(portion.amount, 0.25)
    }

    private static func drinkServings(_ portion: FoodPortion) -> Double {
        switch portion.unit {
        case .fluidOunce:
            return max(portion.amount / 12, 0.5)
        case .milliliter:
            return max(portion.amount / 355, 0.5)
        case .cup:
            return max(portion.amount * 8 / 12, 0.5)
        default:
            return portion.unit.isCountable ? max(portion.amount, 0.25) : 1
        }
    }

    private static func payload(from scaled: StapleNutritionDatabase.ScaledResult, fallbackName: String, barcode: String?) -> MealPayload {
        MealPayload(
            name: fallbackName,
            calories: scaled.totals.calories,
            proteinG: scaled.totals.proteinG,
            carbsG: scaled.totals.carbsG,
            fatG: scaled.totals.fatG,
            barcode: barcode ?? scaled.entry.barcode,
            isLabelBacked: scaled.entry.source.isExact,
            assumptions: scaled.assumptions,
            quantity: scaled.portion.amount,
            unit: scaled.portion.unit.displayName.isEmpty ? scaled.entry.displayUnit : scaled.portion.unit.displayName,
            preparationState: scaled.portion.preparation == .unknown ? nil : scaled.portion.preparation.rawValue,
            brand: scaled.entry.brand,
            source: scaled.entry.source,
            confidence: scaled.usedDefaultPortion ? .low : (scaled.inferredPreparation ? .medium : scaled.entry.confidence)
        )
    }

    private static func payload(from item: MealLineItem) -> MealPayload {
        MealPayload(
            name: item.name,
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            quantity: item.quantity ?? 1,
            unit: item.unit ?? "serving",
            preparationState: item.preparationState,
            brand: item.brand,
            source: item.source.flatMap(MacroTrackingEngine.NutritionSource.init) ?? .genericEstimate,
            confidence: item.confidence.flatMap(MacroTrackingEngine.NutritionConfidence.init)
        )
    }

    private static func lineItem(from scaled: StapleNutritionDatabase.ScaledResult, name: String) -> MealLineItem {
        MealLineItem(
            name: name,
            calories: scaled.totals.calories,
            proteinG: scaled.totals.proteinG,
            carbsG: scaled.totals.carbsG,
            fatG: scaled.totals.fatG,
            quantity: scaled.portion.amount,
            unit: scaled.portion.unit.displayName.isEmpty ? scaled.entry.displayUnit : scaled.portion.unit.displayName,
            preparationState: scaled.portion.preparation == .unknown ? nil : scaled.portion.preparation.rawValue,
            brand: scaled.entry.brand,
            source: scaled.entry.source.rawValue,
            confidence: (scaled.usedDefaultPortion ? MacroTrackingEngine.NutritionConfidence.low : (scaled.inferredPreparation ? MacroTrackingEngine.NutritionConfidence.medium : scaled.entry.confidence)).rawValue
        )
    }

    private static func genericItem(
        name: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        quantity: Double,
        unit: String = "serving",
        confidence: MacroTrackingEngine.NutritionConfidence
    ) -> MealLineItem {
        let q = max(quantity, 0.05)
        return MealLineItem(
            name: name,
            calories: calories * q,
            proteinG: proteinG * q,
            carbsG: carbsG * q,
            fatG: fatG * q,
            quantity: q,
            unit: unit,
            source: MacroTrackingEngine.NutritionSource.genericEstimate.rawValue,
            confidence: confidence.rawValue
        )
    }

    /// Coffee only. Beer, wine, and soda used to land here and inherit a latte (8 g protein, 18 g carbs).
    private static func isCoffeeDrink(_ text: String) -> Bool {
        let coffee = [
            "latte", "coffee", "espresso", "cappuccino", "mocha", "frappuccino",
            "macchiato", "americano", "cold brew", "cortado",
        ]
        if coffee.contains(where: { text.contains($0) }) { return true }
        // Speech-to-text often hears "latte" as "late".
        if text.contains("late"), text.contains("vanilla") || text.contains("skinny") || text.contains("starbucks") {
            return !text.contains("chocolate")
        }
        return false
    }

    /// Starbucks-style drinks — sugar-free skinny vs full-fat specialty.
    private static func estimateCoffeeDrink(
        name: String,
        text: String,
        sourceLower: String,
        quantity: Double
    ) -> MealLineItem {
        let q = max(quantity, 0.25)
        let sugarFree = sourceLower.contains("sugar free") || sourceLower.contains("sugar-free")
            || sourceLower.contains("skinny") || sourceLower.contains("nonfat") || sourceLower.contains("non-fat")
        let fatty = sourceLower.contains("frappuccino") || sourceLower.contains("mocha")
            || sourceLower.contains("whip") || sourceLower.contains("breve") || sourceLower.contains("whole milk")
        let large = sourceLower.contains("large") || sourceLower.contains("venti") || sourceLower.contains("grande")

        let sizeMultiplier: Double = large ? 1.25 : 1.0
        let (cal, protein, carbs, fat): (Double, Double, Double, Double)
        if fatty {
            (cal, protein, carbs, fat) = (380, 6, 52, 16)
        } else if sugarFree {
            (cal, protein, carbs, fat) = (90, 0, 14, 0)
        } else {
            (cal, protein, carbs, fat) = (190, 8, 18, 7)
        }

        return MealLineItem(
            name: name,
            calories: cal * sizeMultiplier * q,
            proteinG: protein * sizeMultiplier * q,
            carbsG: carbs * sizeMultiplier * q,
            fatG: fat * sizeMultiplier * q,
            quantity: q,
            unit: "serving",
            source: MacroTrackingEngine.NutritionSource.genericEstimate.rawValue,
            confidence: MacroTrackingEngine.NutritionConfidence.low.rawValue
        )
    }

    /// Plate photo → structured inventory → staple/label math. GPT macros are fallback only.
    static func resolvedMeal(fromPhotoAnalysis result: FoodAnalysisResult) -> MealPayload {
        if isExactPhotoSource(result) {
            return labelBackedPhotoPayload(from: result)
        }

        let aiFallback = result.aiFallbackTotals
        var lineItems = result.lineItems
        if lineItems.isEmpty {
            lineItems = result.items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { name in
                    MealLineItem(
                        name: name,
                        calories: 0,
                        proteinG: 0,
                        carbsG: 0,
                        fatG: 0,
                        source: MacroTrackingEngine.NutritionSource.genericEstimate.rawValue,
                        confidence: MacroTrackingEngine.NutritionConfidence.low.rawValue
                    )
                }
        }
        if lineItemsRepeatedTheMealTotal(lineItems, mealCalories: result.calories) {
            lineItems = lineItems.map { item in
                var copy = item
                copy.calories = 0
                copy.proteinG = 0
                copy.carbsG = 0
                copy.fatG = 0
                return copy
            }
        }
        if lineItems.isEmpty {
            lineItems = [
                MealLineItem(
                    name: "Meal",
                    calories: result.calories,
                    proteinG: result.proteinG,
                    carbsG: result.carbsG,
                    fatG: result.fatG,
                    source: MacroTrackingEngine.NutritionSource.genericEstimate.rawValue,
                    confidence: MacroTrackingEngine.NutritionConfidence.low.rawValue
                ),
            ]
        }

        var assumptions = result.assumptions
        if aiFallback.calories > 0 || aiFallback.proteinG > 0 {
            assumptions.append(aiFallbackAssumption(aiFallback))
        }

        let payload = MealPayload(
            name: lineItems.count == 1 ? lineItems[0].name : "Meal",
            calories: result.calories,
            proteinG: result.proteinG,
            carbsG: result.carbsG,
            fatG: result.fatG,
            items: result.items,
            lineItems: lineItems,
            barcode: result.barcode,
            isLabelBacked: false,
            assumptions: assumptions,
            source: .genericEstimate,
            confidence: .low
        )
        var reconciled = reconcileMealPayload(payload)
        if reconciled.calories <= 0, aiFallback.calories > 0 {
            reconciled.calories = aiFallback.calories
            reconciled.proteinG = aiFallback.proteinG
            reconciled.carbsG = aiFallback.carbsG
            reconciled.fatG = aiFallback.fatG
            reconciled.assumptions.append("Used AI fallback macros because no staple matched.")
        }
        logNutritionResolution(reconciled, aiFallback: aiFallback)
        return reconciled
    }

    static func userFacingTotals(from payload: MealPayload) -> MacroTotals {
        totals(from: payload)
    }

    static func formatEstimateForDisplay(
        _ value: Double,
        isCalories: Bool,
        confidence: MacroTrackingEngine.NutritionConfidence
    ) -> String {
        _ = confidence
        if isCalories {
            return String(MacroTrackingEngine.displayCalories(value))
        }
        return String(MacroTrackingEngine.displayGrams(value))
    }

    /// The model sometimes copies the whole-meal total onto every line item.
    private static func lineItemsRepeatedTheMealTotal(_ items: [MealLineItem], mealCalories: Double) -> Bool {
        guard items.count > 1, mealCalories > 50 else { return false }
        return items.allSatisfy { item in
            item.calories > 0 && abs(item.calories - mealCalories) / mealCalories < 0.12
        }
    }

    private static func isExactPhotoSource(_ result: FoodAnalysisResult) -> Bool {
        if result.source == .barcode || result.source == .nutritionLabelOCR { return true }
        return result.labelDetected == true
    }

    private static func labelBackedPhotoPayload(from result: FoodAnalysisResult) -> MealPayload {
        let source: MacroTrackingEngine.NutritionSource = result.source == .barcode ? .manufacturer : .userLabel
        let rawName = result.items.first ?? "Packaged food"
        // "Potato Chips Jalapeño" must stay the product, not collapse to "1 serving chips".
        let name = result.barcode == nil ? FoodItemNaming.canonicalName(for: rawName) : rawName
        return MealPayload(
            name: name,
            calories: result.calories,
            proteinG: result.proteinG,
            carbsG: result.carbsG,
            fatG: result.fatG,
            items: result.items,
            barcode: result.barcode,
            isLabelBacked: true,
            assumptions: result.assumptions,
            source: source,
            confidence: .high
        )
    }

    private static func totals(from payload: MealPayload) -> MacroTotals {
        let entries = payload.entriesForLogging()
        return MacroTrackingEngine.recipeTotals(entries.map {
            MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        })
    }

    private static func aiFallbackAssumption(_ totals: MacroTotals) -> String {
        "AI fallback estimate: \(Int(totals.calories.rounded())) kcal / \(Int(totals.proteinG.rounded()))g protein (not used when a staple matched)."
    }

    private static func looksLikeMixedStapleDish(_ name: String) -> Bool {
        distinctStapleGroups(in: name).count >= 2
    }

    private static func distinctStapleGroups(in name: String) -> Set<String> {
        let lower = name.lowercased()
        var groups: Set<String> = []
        let mapping: [(String, [String])] = [
            ("chicken", ["chicken"]),
            ("rice", ["rice"]),
            ("egg", ["egg", "eggs"]),
            ("beef", ["ground beef", "beef"]),
            ("fish", ["salmon", "fish"]),
            ("oil", ["olive oil", "oil"]),
            ("butter", ["butter"]),
            ("yogurt", ["yogurt"]),
            ("banana", ["banana"]),
        ]
        for (group, tokens) in mapping {
            if tokens.contains(where: { token in
                guard let regex = try? NSRegularExpression(
                    pattern: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b",
                    options: .caseInsensitive
                ) else { return false }
                return regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
            }) {
                groups.insert(group)
            }
        }
        return groups
    }

    private static func logNutritionResolution(_ payload: MealPayload, aiFallback: MacroTotals) {
        #if DEBUG
        let entries = payload.entriesForLogging()
        var lines: [String] = ["Photo nutrition resolution"]
        for entry in entries {
            lines.append(
                """
                Food: \(entry.name)
                Vision portion: \(entry.quantity) \(entry.unit)
                Preparation: \(entry.preparationState ?? "unknown")
                Nutrition source: \(entry.source.rawValue)
                Calories: \(entry.calories)
                Protein: \(entry.proteinG) g
                Confidence: \(entry.confidence.rawValue)
                Assumptions: \(entry.assumptions.joined(separator: "; "))
                AI fallback estimate: \(aiFallback.calories) kcal / \(aiFallback.proteinG)g protein
                """
            )
        }
        Logger(subsystem: "FunFitnessTrainer", category: "nutrition").debug("\(lines.joined(separator: "\n---\n"), privacy: .public)")
        #endif
    }

    private static func mockResult() -> FoodAnalysisResult {
        FoodAnalysisResult(
            calories: 450,
            proteinG: 28,
            carbsG: 40,
            fatG: 18,
            items: ["sample meal"],
            confidence: 0.5,
            assumptions: ["Demo mode. Configure Supabase for real estimates"],
            labelDetected: false,
            barcode: nil,
            source: .offlineEstimate
        )
    }
}

extension FoodAnalysisService {
    /// Offline starting point so photo logs can be saved before AI finishes on slow links.
    static func offlineEstimate(from hint: String?) -> MealPayload {
        let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return estimateOffline(from: trimmed.isEmpty ? "Meal" : trimmed)
    }
}

enum FoodEstimateGate {
    /// Rejects numbers that cannot belong to this food, even if the serving word matches something else.
    static func isPlausible(text: String, calories: Double, proteinG: Double) -> Bool {
        let lower = text.lowercased()
        let portion = FoodQuantity.parse(from: lower)
        if isAlcohol(lower) {
            let ounces = FoodQuantity.pintFluidOunces(in: lower)
                ?? (portion.unit == .fluidOunce ? portion.amount : 12)
            if ounces >= 10, calories < 50 || proteinG > 6 { return false }
            if calories > 550 { return false }
        }
        if lower.contains("olive oil") || (lower.contains("butter") && !lower.contains("peanut") && !lower.contains("almond")) {
            let tablespoons = portion.unit == .tablespoon ? max(portion.amount, 1) : 1
            if calories < 70 * tablespoons * 0.6 { return false }
        }
        if lower.contains("salsa"), portion.unit == .tablespoon, calories > 25 * max(portion.amount, 1) {
            return false
        }
        if isLeafy(lower) {
            let cups = portion.unit == .cup ? max(portion.amount, 1) : 1
            if calories > 80 * cups { return false }
        }
        if isLeanMeat(lower) {
            let ounces: Double
            if portion.unit == .ounce { ounces = portion.amount }
            else if portion.unit == .gram { ounces = portion.amount / FoodUnit.gramsPerOunce }
            else { ounces = 0 }
            if ounces >= 3, proteinG < ounces * 4 { return false }
        }
        return calories > 0 || proteinG > 0 || lower.contains("water") || lower.contains("diet")
    }

    private static func isAlcohol(_ text: String) -> Bool {
        ["beer", "ale", "ipa", "lager", "wine", "whiskey", "whisky", "vodka", "tequila", "bourbon"].contains {
            text.contains($0)
        }
    }

    private static func isLeafy(_ text: String) -> Bool {
        ["spinach", "lettuce", "kale", "arugula"].contains { text.contains($0) }
    }

    private static func isLeanMeat(_ text: String) -> Bool {
        ["chicken", "turkey breast", "steak", "sirloin", "shrimp"].contains { text.contains($0) }
    }
}

enum AgentDebugLog {
    /// Leftover local debug session. Meal text must not be posted to a LAN ingest or a Mac path.
    static func emit(hypothesisId: String, location: String, message: String, data: [String: Any] = [:]) {
        _ = hypothesisId
        _ = location
        _ = message
        _ = data
    }

    static func flush() async {}
}

private enum FoodAnalysisNetwork {
    static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "funfitness.food.network"))
        return monitor
    }()

    static var isLikelyAvailable: Bool {
        monitor.currentPath.status != .unsatisfied
    }
}

extension UIImage {
    /// Pixel-aware resize + iterative JPEG compression for vision uploads / meal photo storage.
    func jpegDataForFoodAnalysis(maxBytes: Int = 250_000, maxEdge: CGFloat = 1024) -> Data? {
        var image = preparedForFoodAnalysis(maxEdge: maxEdge)
        var quality: CGFloat = 0.78

        for _ in 0..<6 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.08
            if quality < 0.38 {
                image = image.preparedForFoodAnalysis(maxEdge: max(image.pixelLongestEdge * 0.8, 720))
                quality = 0.62
            }
        }
        return image.jpegData(compressionQuality: 0.42)
    }

    /// Keeps label text legible for vision models without oversized uploads.
    fileprivate func preparedForFoodAnalysis(maxEdge: CGFloat = 1024) -> UIImage {
        let longest = pixelLongestEdge
        guard longest > maxEdge else {
            // Normalize orientation into a scale=1 bitmap so jpeg size matches expectations.
            guard imageOrientation != .up else { return self }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let drawSize = CGSize(width: size.width, height: size.height)
            return UIGraphicsImageRenderer(size: drawSize, format: format).image { _ in
                draw(in: CGRect(origin: .zero, size: drawSize))
            }
        }

        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * self.scale * scale, height: size.height * self.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    fileprivate var pixelLongestEdge: CGFloat {
        max(size.width * scale, size.height * scale)
    }
}
