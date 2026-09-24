import Foundation
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

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case items, confidence, assumptions
        case labelDetected = "label_detected"
    }
}

enum FoodAnalysisService {
    static func analyze(image: UIImage, hint: String?) async throws -> FoodAnalysisResult {
        guard AppConfig.hasBackend else {
            return mockResult()
        }

        let prepared = image.preparedForFoodAnalysis()
        guard let jpeg = prepared.jpegData(compressionQuality: 0.6) else {
            throw APIError.invalidResponse
        }
        let base64 = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"

        var body: [String: Any] = ["image_base64": base64]
        if let hint, !hint.isEmpty { body["user_hint"] = hint }

        // Slow cellular / satellite links need a smaller upload and a longer wait.
        let data = try await SupabaseService.shared.invokeFunction(
            name: "analyze-food",
            body: body,
            timeout: 120
        )
        if let err = try? JSONDecoder().decode([String: String].self, from: data), let message = err["error"] {
            throw APIError.serverMessage(message)
        }
        return try JSONDecoder().decode(FoodAnalysisResult.self, from: data)
    }

    /// Voice/text logging: try Open Food Facts, then offline rules. Runs off the chat hot path.
    static func resolveMealForLogging(from description: String, searchTimeout: TimeInterval = 4) async -> MealPayload {
        let query = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return estimateOffline(from: description) }

        if let product = try? await OpenFoodFactsService.searchBestMatch(query: query, timeout: searchTimeout) {
            return mealPayload(from: product, userDescription: description)
        }
        return estimateOffline(from: description)
    }

    /// Start this when the user sends a food log so label lookup overlaps Larry's reply.
    static func shouldPrefetchNutrition(for text: String) -> Bool {
        let lower = text.lowercased()
        let triggers = ["i had", "i ate", "i drank", "just had", "just ate", "just drank", "log my", "log this"]
        return triggers.contains { lower.contains($0) }
    }

    /// Label matches keyed by canonical food name. Empty when Open Food Facts misses.
    static func prefetchedLabelMatches(for utterance: String) async -> [String: MealPayload] {
        let entries = estimateOffline(from: utterance).entriesForLogging()
        let queries = entries.isEmpty ? [utterance] : entries.map(\.name)
        var map: [String: MealPayload] = [:]
        await withTaskGroup(of: (String, MealPayload?).self) { group in
            for query in queries.prefix(4) {
                group.addTask {
                    let match = await labelMatch(query: query, localCalories: nil)
                    let key = FoodItemNaming.canonicalName(for: query).lowercased()
                    return (key, match)
                }
            }
            for await (key, match) in group {
                if let match {
                    map[key] = match
                }
            }
        }
        return map
    }

    /// One Open Food Facts hit for a single food, rejected when the calories are wildly off the logged estimate.
    static func labelMatch(query: String, localCalories: Double?) async -> MealPayload? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let product = try? await OpenFoodFactsService.searchBestMatch(query: trimmed) else { return nil }
        let payload = mealPayload(from: product, userDescription: trimmed)
        guard payload.isLabelBacked, payload.calories > 0 else { return nil }
        guard caloriesArePlausible(payload.calories, comparedTo: localCalories) else { return nil }
        return payload
    }

    static func refinement(for mealName: String, calories: Double, prefetched: [String: MealPayload]) -> MealPayload? {
        let key = FoodItemNaming.canonicalName(for: mealName).lowercased()
        if let direct = prefetched[key], caloriesArePlausible(direct.calories, comparedTo: calories) {
            return direct
        }
        for (candidate, payload) in prefetched {
            guard key.count >= 3, candidate.count >= 3 else { continue }
            if key.contains(candidate) || candidate.contains(key),
               caloriesArePlausible(payload.calories, comparedTo: calories) {
                return payload
            }
        }
        return nil
    }

    /// Only rewrite a saved estimate when it is still the generic placeholder, not a confirmed portion.
    static func isGenericPlaceholder(calories: Double, proteinG: Double, carbsG: Double, fatG: Double) -> Bool {
        func close(_ value: Double, _ target: Double) -> Bool { abs(value - target) < 1.5 }
        if close(calories, 400) && close(proteinG, 25) && close(carbsG, 35) && close(fatG, 12) { return true }
        if close(calories, 450) && close(proteinG, 28) && close(carbsG, 40) && close(fatG, 18) { return true }
        guard calories > 0 else { return false }
        let quantity = (calories / 200).rounded()
        guard quantity >= 1, quantity <= 6 else { return false }
        return close(calories, 200 * quantity)
            && close(proteinG, 10 * quantity)
            && close(carbsG, 15)
            && close(fatG, 8)
    }

    private static func caloriesArePlausible(_ labelCalories: Double, comparedTo localCalories: Double?) -> Bool {
        guard let localCalories, localCalories > 40 else { return true }
        let ratio = labelCalories / localCalories
        return ratio >= 0.25 && ratio <= 4
    }

    static func mealPayload(from product: BarcodeProductResult, userDescription: String) -> MealPayload {
        let multiplier = servingMultiplier(userDescription: userDescription, product: product)
        let calories = product.perServing.calories * multiplier
        let protein = product.perServing.proteinG * multiplier
        let carbs = product.perServing.carbsG * multiplier
        let fat = product.perServing.fatG * multiplier
        let displayName = FoodItemNaming.canonicalName(for: product.name)
        var assumption = "Open Food Facts: \(product.name)"
        if let serving = product.servingDescription, !serving.isEmpty {
            assumption += " (\(serving))"
        }
        if multiplier != 1 {
            assumption += String(format: " — scaled ×%.2f for your portion", multiplier)
        }

        return MealPayload(
            name: displayName,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            barcode: product.barcode,
            isLabelBacked: true,
            assumptions: [assumption]
        )
    }

    private static func servingMultiplier(userDescription: String, product: BarcodeProductResult) -> Double {
        let sourceLower = userDescription.lowercased()
        guard let userOz = parseFluidOunces(in: sourceLower) else { return 1 }
        let productOz: Double
        if let ml = product.servingQuantityMl, ml > 0 {
            productOz = ml / 29.5735
        } else {
            productOz = 8
        }
        return max(userOz / max(productOz, 1), 0.25)
    }

    /// Rough offline macro estimate from a spoken or typed food description.
    static func estimateOffline(from description: String) -> MealPayload {
        let source = FoodItemNaming.extractFoodReference(from: description) ?? description
        let segments = foodSegments(from: source)
        let lineItems = segments.map { estimateSegment($0) }

        if lineItems.count > 1 {
            let totals = lineItems.reduce(into: MacroTotals()) { acc, item in
                acc.calories += item.calories
                acc.proteinG += item.proteinG
                acc.carbsG += item.carbsG
                acc.fatG += item.fatG
            }
            return MealPayload(
                name: "Meal",
                calories: totals.calories,
                proteinG: totals.proteinG,
                carbsG: totals.carbsG,
                fatG: totals.fatG,
                lineItems: lineItems
            )
        }

        if let only = lineItems.first {
            return MealPayload(
                name: only.name,
                calories: only.calories,
                proteinG: only.proteinG,
                carbsG: only.carbsG,
                fatG: only.fatG
            )
        }

        return MealPayload(name: "Meal", calories: 400, proteinG: 25, carbsG: 35, fatG: 12)
    }

    /// Re-estimate macros for a stored log label (USDA-based offline lookup).
    static func estimateForStoredName(_ name: String) -> MealPayload? {
        guard hasKnownNutrition(for: name) else { return nil }
        let estimate = estimateOffline(from: name)
        return estimate.entriesForLogging().first
    }

    /// Whether offline USDA-based estimates exist for this label.
    static func hasKnownNutrition(for name: String) -> Bool {
        let text = name.lowercased()
        let sanitized = FoodItemNaming.sanitizeSegment(name).lowercased()
        let known = [
            "carrot", "ground beef", "egg", "almond butter", "peanut butter",
            "toast", "bread", "dave", "chicken", "salmon", "fish", "yogurt", "greek",
            "rice", "salad", "big mac", "bigmac", "burger", "pizza", "mcdonald",
            "power green", "powder green", "twix", "candy", "chocolate bar",
            "chocolate milk", "nesquik",
        ]
        return known.contains { text.contains($0) || sanitized.contains($0) }
    }

    private static func foodSegments(from description: String) -> [String] {
        let text = FoodItemNaming.sanitizeUtterance(description)

        let parts = text
            .replacingOccurrences(of: " & ", with: ", ")
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            .split(separator: ",")
            .map { FoodItemNaming.sanitizeSegment(String($0)) }
            .filter { !$0.isEmpty }

        return parts.isEmpty ? [text] : parts
    }

    private static func estimateSegment(_ segment: String) -> MealLineItem {
        let sourceLower = segment.lowercased()
        let text = FoodItemNaming.sanitizeSegment(segment).lowercased()
        let qty = Double(FoodItemNaming.parseQuantity(in: sourceLower))
        let name = FoodItemNaming.logLabel(from: segment, quantity: qty)

        if text.contains("egg") {
            return macrosItem(name: name, perUnit: (70, 6, 0.5, 5), quantity: qty)
        }
        if text.contains("almond butter") || text.contains("peanut butter") {
            let tbsp = text.contains("tablespoon") || text.contains("tbsp") ? max(qty, 1) : max(qty, 1)
            return MealLineItem(name: name, calories: 98 * tbsp, proteinG: 3 * tbsp, carbsG: 3 * tbsp, fatG: 9 * tbsp)
        }
        if text.contains("toast") || text.contains("bread") || text.contains("dave") {
            let slices = text.contains("loaf") ? max(qty, 1) : max(qty, 1)
            return macrosItem(name: name, perUnit: (60, 3, 11, 1), quantity: slices)
        }
        if text.contains("chicken") {
            return macrosItem(name: name, perUnit: (165, 31, 0, 4), quantity: max(qty, 1))
        }
        if text.contains("salmon") || text.contains("fish") {
            return macrosItem(name: name, perUnit: (200, 34, 0, 7), quantity: max(qty, 1))
        }
        if text.contains("yogurt") || text.contains("greek") {
            return macrosItem(name: name, perUnit: (100, 17, 6, 0), quantity: max(qty, 1))
        }
        if text.contains("rice") {
            return macrosItem(name: name, perUnit: (200, 4, 44, 0), quantity: max(qty, 1))
        }
        if text.contains("salad") {
            return MealLineItem(name: name, calories: 320, proteinG: 28, carbsG: 18, fatG: 14)
        }
        if text.contains("big mac") || text.contains("bigmac") {
            return macrosItem(name: name, perUnit: (590, 25, 46, 34), quantity: qty)
        }
        if text.contains("burger") || text.contains("pizza") || text.contains("mcdonald") {
            return MealLineItem(name: name, calories: 650, proteinG: 28, carbsG: 55, fatG: 32)
        }
        if text.contains("power green") || text.contains("powder green") {
            return MealLineItem(name: name, calories: 450, proteinG: 28, carbsG: 45, fatG: 18)
        }
        if text.contains("carrot") || sourceLower.contains("carrot") {
            if sourceLower.contains("cup") {
                // USDA FDC: carrots, raw — 1 cup chopped (128g)
                return macrosItem(name: name, perUnit: (52, 1.2, 12.3, 0.3), quantity: max(qty, 1))
            }
            // USDA FDC: 1 medium carrot (61g)
            return macrosItem(name: name, perUnit: (25, 0.6, 6, 0.1), quantity: max(qty, 1))
        }
        if text.contains("ground beef") || sourceLower.contains("ground beef") {
            // USDA FDC: ground beef, cooked — 1 cup crumbled
            let cups = sourceLower.contains("cup") ? max(qty, 1) : 1
            return macrosItem(name: name, perUnit: (339, 31, 0, 23), quantity: cups)
        }
        if let chocolateMilk = estimateChocolateMilk(name: name, sourceLower: sourceLower) {
            return chocolateMilk
        }
        if text.contains("twix") || text.contains("candy") || text.contains("chocolate bar") {
            return MealLineItem(name: name, calories: 250, proteinG: 2, carbsG: 34, fatG: 12)
        }
        if isCoffeeDrink(text) || sourceLower.contains("starbucks") {
            return estimateCoffeeDrink(name: name, text: text, sourceLower: sourceLower, quantity: qty)
        }

        let q = max(qty, 1)
        return MealLineItem(name: name, calories: 200 * q, proteinG: 10 * q, carbsG: 15, fatG: 8)
    }

    /// Nesquik / ready-to-drink chocolate milk — 8 fl oz ≈ 140 cal (label reference).
    private static func estimateChocolateMilk(name: String, sourceLower: String) -> MealLineItem? {
        let isChocolateMilk =
            sourceLower.contains("chocolate milk")
            || sourceLower.contains("nesquik")
            || (sourceLower.contains("chocolate") && sourceLower.contains("milk") && !sourceLower.contains("bar"))
        guard isChocolateMilk else { return nil }

        let oz = parseFluidOunces(in: sourceLower) ?? 8
        let servings = max(oz / 8, 0.25)
        return macrosItem(name: name, perUnit: (140, 5, 24, 2.5), quantity: servings)
    }

    /// Parses "8 oz", "8 fl oz", etc. Returns nil if no fluid measure found.
    private static func parseFluidOunces(in text: String) -> Double? {
        let lower = text.lowercased()
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:fl\s*oz|fluid\s*ounces?|ounces?|oz)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let range = Range(match.range(at: 1), in: lower),
              let value = Double(lower[range]) else { return nil }
        return value
    }

    private static func isCoffeeDrink(_ text: String) -> Bool {
        FoodItemNaming.isBeverage(text)
    }

    /// Starbucks-style drinks — sugar-free skinny vs full-fat specialty.
    private static func estimateCoffeeDrink(
        name: String,
        text: String,
        sourceLower: String,
        quantity: Double
    ) -> MealLineItem {
        let q = max(quantity, 1)
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
            proteinG: protein * q,
            carbsG: carbs * sizeMultiplier * q,
            fatG: fat * sizeMultiplier * q
        )
    }

    private static func macrosItem(
        name: String,
        perUnit: (Double, Double, Double, Double),
        quantity: Double
    ) -> MealLineItem {
        let q = max(quantity, 1)
        return MealLineItem(
            name: name,
            calories: perUnit.0 * q,
            proteinG: perUnit.1 * q,
            carbsG: perUnit.2 * q,
            fatG: perUnit.3 * q
        )
    }

    private static func mockResult() -> FoodAnalysisResult {
        FoodAnalysisResult(
            calories: 450,
            proteinG: 28,
            carbsG: 40,
            fatG: 18,
            items: ["sample meal"],
            confidence: 0.5,
            assumptions: ["Demo mode — configure Supabase for real estimates"],
            labelDetected: false
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

private extension UIImage {
    /// Keeps label text legible for vision models without oversized uploads.
    func preparedForFoodAnalysis() -> UIImage {
        let maxEdge: CGFloat = 1024
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }

        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
