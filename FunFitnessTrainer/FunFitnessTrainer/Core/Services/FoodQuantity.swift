import Foundation

/// Parsed amount + unit for a logged food. Weight ounces and fluid ounces are not interchangeable.
struct FoodPortion: Equatable {
    var amount: Double
    var unit: FoodUnit
    var preparation: MacroTrackingEngine.PreparationState
}

enum FoodUnit: String, Equatable {
    case gram
    case ounce
    case fluidOunce
    case milliliter
    case cup
    case tablespoon
    case teaspoon
    case slice
    case piece
    case serving
    case count

    var isMass: Bool {
        self == .gram || self == .ounce
    }

    var isVolume: Bool {
        switch self {
        case .fluidOunce, .milliliter, .cup, .tablespoon, .teaspoon: return true
        default: return false
        }
    }

    var isCountable: Bool {
        switch self {
        case .slice, .piece, .serving, .count: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .gram: return "g"
        case .ounce: return "oz"
        case .fluidOunce: return "fl oz"
        case .milliliter: return "ml"
        case .cup: return "cup"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .slice: return "slice"
        case .piece: return "piece"
        case .serving: return "serving"
        case .count: return ""
        }
    }

    static let gramsPerOunce = 28.349523125
    static let mlPerFluidOunce = 29.5735295625
    static let mlPerCup = 240.0
    static let mlPerTablespoon = 15.0
    static let mlPerTeaspoon = 5.0

    func converted(amount: Double, to other: FoodUnit) -> Double? {
        if self == other { return amount }
        if let grams = toGrams(amount), let otherGramsPer = other.unitGrams {
            return grams / otherGramsPer
        }
        if let ml = toMilliliters(amount), let otherMl = other.unitMilliliters {
            return ml / otherMl
        }
        if isCountable && other.isCountable {
            return amount
        }
        return nil
    }

    private var unitGrams: Double? {
        switch self {
        case .gram: return 1
        case .ounce: return Self.gramsPerOunce
        default: return nil
        }
    }

    private var unitMilliliters: Double? {
        switch self {
        case .milliliter: return 1
        case .fluidOunce: return Self.mlPerFluidOunce
        case .cup: return Self.mlPerCup
        case .tablespoon: return Self.mlPerTablespoon
        case .teaspoon: return Self.mlPerTeaspoon
        default: return nil
        }
    }

    func toGrams(_ amount: Double) -> Double? {
        guard let g = unitGrams else { return nil }
        return amount * g
    }

    func toMilliliters(_ amount: Double) -> Double? {
        guard let ml = unitMilliliters else { return nil }
        return amount * ml
    }
}

enum FoodQuantity {
    /// Parse a spoken/typed portion. Distinguishes weight oz (chicken) from fluid oz (milk).
    static func parse(from text: String) -> FoodPortion {
        let lower = text.lowercased()
        let quantityText = strippingMacroClauses(lower)
        let prep = preparation(in: lower)
        let number = leadingNumber(in: quantityText) ?? wordNumber(in: quantityText)

        if let grams = parseGrams(in: quantityText) {
            return FoodPortion(amount: grams, unit: .gram, preparation: prep)
        }
        if let ml = parseMilliliters(in: quantityText) {
            return FoodPortion(amount: ml, unit: .milliliter, preparation: prep)
        }
        if let flOz = parseExplicitFluidOunces(in: quantityText) {
            return FoodPortion(amount: flOz, unit: .fluidOunce, preparation: prep)
        }
        if let pintOz = pintFluidOunces(in: quantityText) {
            return FoodPortion(amount: pintOz, unit: .fluidOunce, preparation: prep)
        }
        if let oz = parseOunces(in: quantityText) {
            if looksLikeBeverage(quantityText) {
                return FoodPortion(amount: oz, unit: .fluidOunce, preparation: prep)
            }
            return FoodPortion(amount: oz, unit: .ounce, preparation: prep)
        }
        if quantityText.contains("tbsp") || quantityText.contains("tablespoon") {
            return FoodPortion(amount: amountForUnit(#"(?:tbsp|tablespoons?)\b"#, in: quantityText, fallback: number), unit: .tablespoon, preparation: prep)
        }
        if quantityText.contains("tsp") || quantityText.contains("teaspoon") {
            return FoodPortion(amount: amountForUnit(#"(?:tsp|teaspoons?)\b"#, in: quantityText, fallback: number), unit: .teaspoon, preparation: prep)
        }
        if quantityText.contains("cup") {
            return FoodPortion(amount: amountForUnit(#"cups?\b"#, in: quantityText, fallback: number), unit: .cup, preparation: prep)
        }
        if quantityText.contains("slice") {
            return FoodPortion(amount: amountForUnit(#"slices?\b"#, in: quantityText, fallback: number), unit: .slice, preparation: prep)
        }
        if quantityText.contains("piece") || quantityText.contains("pieces") {
            return FoodPortion(amount: amountForUnit(#"pieces?\b"#, in: quantityText, fallback: number), unit: .piece, preparation: prep)
        }
        if quantityText.contains("serving") {
            return FoodPortion(amount: amountForUnit(#"servings?\b"#, in: quantityText, fallback: number), unit: .serving, preparation: prep)
        }

        return FoodPortion(amount: number ?? 1, unit: .count, preparation: prep)
    }

    /// Human-readable portion for assumptions / debug ("6 oz", "1 cup").
    static func describe(_ portion: FoodPortion) -> String {
        let amount = portion.amount == floor(portion.amount)
            ? String(Int(portion.amount))
            : String(format: "%g", portion.amount)
        let unit = portion.unit.displayName
        if unit.isEmpty { return amount }
        return "\(amount) \(unit)"
    }

    /// Prefers an explicit quantity/unit from structured vision output over a bare food name.
    static func queryForScaling(name: String, quantity: Double?, unit: String?) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quantity, quantity > 0 else { return trimmedName }

        let unitText = (unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmedName.lowercased()
        if parseGrams(in: lower) != nil || parseOunces(in: lower) != nil
            || parseMilliliters(in: lower) != nil || parseExplicitFluidOunces(in: lower) != nil {
            return trimmedName
        }
        if lower.contains("cup") || lower.contains("tbsp") || lower.contains("tablespoon")
            || lower.contains("tsp") || lower.contains("teaspoon") || lower.contains("slice") {
            return trimmedName
        }

        let qtyText = quantity == floor(quantity)
            ? String(Int(quantity))
            : String(format: "%g", quantity)
        let unitLower = unitText.lowercased()
        if unitLower.isEmpty || unitLower == "serving" || unitLower == "count" {
            return quantity == 1 ? trimmedName : "\(qtyText) servings \(trimmedName)"
        }
        if lower.contains(unitLower) { return trimmedName }
        return "\(qtyText) \(unitText) \(trimmedName)"
    }

    /// Drop "for 5 calories" / "20g protein" so those numbers are not treated as servings.
    static func strippingMacroClauses(_ text: String) -> String {
        let patterns = [
            #"(?:for|at|only|just|about|around)?\s*\d+(?:\.\d+)?\s*(?:kilo)?cal(?:orie)?s?\b"#,
            #"\d+(?:\.\d+)?\s*(?:g(?:rams?)?\s*(?:of\s+)?)?protein\b"#,
            #"\d+(?:\.\d+)?\s*(?:g(?:rams?)?\s*(?:of\s+)?)?(?:carbs?|carbohydrates?)\b"#,
            #"\d+(?:\.\d+)?\s*(?:g(?:rams?)?\s*(?:of\s+)?)?fat\b"#,
        ]
        var result = text
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func preparation(in text: String) -> MacroTrackingEngine.PreparationState {
        let lower = text.lowercased()
        if lower.contains("cooked") || lower.contains("grilled") || lower.contains("baked")
            || lower.contains("roasted") || lower.contains("seared") || lower.contains("fried")
            || lower.contains("saute") || lower.contains("sauté") || lower.contains("boiled") {
            return .cooked
        }
        if lower.contains("raw") || lower.contains("uncooked") {
            return .raw
        }
        return .unknown
    }

    /// Scale reference nutrients to the user's portion.
    /// When units cannot convert, treat countable amounts as a simple count multiplier.
    static func multiplier(consumed: FoodPortion, referenceQuantity: Double, referenceUnit: FoodUnit) -> Double {
        if let converted = consumed.unit.converted(amount: consumed.amount, to: referenceUnit) {
            return MacroTrackingEngine.multiplier(consumed: converted, reference: referenceQuantity)
        }
        if consumed.unit.isMass, referenceUnit == .gram, let grams = consumed.unit.toGrams(consumed.amount) {
            return MacroTrackingEngine.multiplier(consumed: grams, reference: referenceQuantity)
        }
        if consumed.unit.isVolume, referenceUnit == .milliliter, let ml = consumed.unit.toMilliliters(consumed.amount) {
            return MacroTrackingEngine.multiplier(consumed: ml, reference: referenceQuantity)
        }
        if consumed.unit.isCountable || referenceUnit.isCountable {
            return MacroTrackingEngine.multiplier(consumed: consumed.amount, reference: max(referenceQuantity, 1))
        }
        // Incompatible units (100 g vs 1 cup) must not treat the raw number as a serving count.
        return 1
    }

    static func looksLikeBeverage(_ text: String) -> Bool {
        FoodItemNaming.isBeverage(text)
            || text.contains("milk")
            || text.contains("juice")
            || text.contains("soda")
            || text.contains("water")
            || text.contains("drink")
            || text.contains("fl oz")
            || text.contains("fluid")
    }

    static func parseOunces(in text: String) -> Double? {
        parseMeasurement(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:ounces?|oz)\b"#)
    }

    static func parseExplicitFluidOunces(in text: String) -> Double? {
        parseMeasurement(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:fl\.?\s*oz|fluid\s*ounces?)\b"#)
    }

    /// US pint = 16 fl oz. "a pint", "two pints", and "half a pint".
    static func pintFluidOunces(in text: String) -> Double? {
        guard text.range(of: #"\bpints?\b"#, options: .regularExpression) != nil else { return nil }
        if let count = parseMeasurement(in: text, pattern: #"(\d+(?:\.\d+)?)\s*pints?\b"#) {
            return count * 16
        }
        let count = wordNumber(in: text) ?? 1
        return count * 16
    }

    static func parseGrams(in text: String) -> Double? {
        parseMeasurement(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:grams?|g)\b"#)
    }

    static func parseMilliliters(in text: String) -> Double? {
        parseMeasurement(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:millilitres?|milliliters?|ml)\b"#)
    }

    /// A count only when the number starts the phrase ("3 eggs"), not a name like "21 Whole Grains".
    static func leadingNumber(in text: String) -> Double? {
        let pattern = #"(?i)^\s*(?:about|around|approximately|roughly)?\s*(\d+(?:\.\d+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    /// "2 slices of Dave's 21" is 2, not 21.
    private static func amountForUnit(_ unitPattern: String, in text: String, fallback: Double?) -> Double {
        let pattern = #"(\d+(?:\.\d+)?)\s*"# + unitPattern
        if let attached = parseMeasurement(in: text, pattern: pattern) {
            return attached
        }
        return fallback ?? 1
    }

    static func wordNumber(in text: String) -> Double? {
        let words: [(String, Double)] = [
            ("a couple of", 2), ("a couple", 2), ("couple of", 2), ("couple", 2),
            ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6),
            ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
            ("half", 0.5), ("a half", 0.5),
        ]
        for (word, value) in words {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil else {
                continue
            }
            return value
        }
        if let regex = try? NSRegularExpression(pattern: #"(?<![a-z])(?:one|a|an)\b"#),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil {
            return 1
        }
        return nil
    }

    private static func parseMeasurement(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}
