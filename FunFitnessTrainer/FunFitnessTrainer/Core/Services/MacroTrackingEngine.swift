import Foundation

/// Deterministic macro tracking: source priority, quantity scaling, official calories,
/// signed remaining, uncapped percentages, and display-only rounding.
enum MacroTrackingEngine {
    /// Atwater factors — used only when no official calorie value exists.
    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0
    static let kcalPerGramAlcohol = 7.0

    // MARK: - Source / confidence

    /// Lower number = higher priority. Never invent values when a better source exists.
    enum NutritionSource: String, Codable, CaseIterable, Sendable {
        case userLabel = "user_label"
        case userProvided = "user_provided"
        case restaurant = "restaurant"
        case manufacturer = "manufacturer"
        case database = "database"
        case usda = "usda"
        case genericEstimate = "generic_estimate"

        var priority: Int {
            switch self {
            case .userLabel, .userProvided: return 1
            case .restaurant, .manufacturer: return 2
            case .database: return 3
            case .usda: return 4
            case .genericEstimate: return 5
            }
        }

        var defaultConfidence: NutritionConfidence {
            switch self {
            case .userLabel, .userProvided, .restaurant, .manufacturer: return .high
            case .database, .usda: return .medium
            case .genericEstimate: return .low
            }
        }

        var isExact: Bool {
            switch self {
            case .userLabel, .userProvided, .restaurant, .manufacturer: return true
            case .database, .usda, .genericEstimate: return false
            }
        }
    }

    enum NutritionConfidence: String, Codable {
        case high, medium, low

        /// Visual estimates are never high — even a "sure" plate photo is still a guess.
        static func fromVisionScore(_ score: Double) -> NutritionConfidence {
            score >= 0.62 ? .medium : .low
        }
    }

    enum PreparationState: String, Codable {
        case raw, cooked, unknown
    }

    // MARK: - Nutrient math

    /// `consumed / reference` — both must already be in the same unit.
    static func multiplier(consumed: Double, reference: Double) -> Double {
        guard reference > 0, consumed > 0 else { return 0 }
        return consumed / reference
    }

    /// Scale a reference profile. Official calories stay official (never replaced by Atwater).
    static func scale(_ reference: MacroTotals, by multiplier: Double) -> MacroTotals {
        MacroTotals(
            calories: reference.calories * multiplier,
            proteinG: reference.proteinG * multiplier,
            carbsG: reference.carbsG * multiplier,
            fatG: reference.fatG * multiplier
        )
    }

    static func caloriesFromMacros(
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        alcoholG: Double = 0
    ) -> Double {
        proteinG * kcalPerGramProtein
            + carbsG * kcalPerGramCarbs
            + fatG * kcalPerGramFat
            + alcoholG * kcalPerGramAlcohol
    }

    /// Prefer an official / labeled calorie value. Only derive from macros when calories are missing.
    static func displayedCalories(
        officialCalories: Double?,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        alcoholG: Double = 0
    ) -> Double {
        if let official = officialCalories, official > 0 {
            return official
        }
        return caloriesFromMacros(proteinG: proteinG, carbsG: carbsG, fatG: fatG, alcoholG: alcoholG)
    }

    /// Kilojoules sometimes land in a kcal field (Open Food Facts and European labels).
    /// Convert only when the number matches the kJ scale against the macro math.
    static func normalizedEnergy(
        reportedCalories: Double,
        kilojoules: Double? = nil,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0
    ) -> Double {
        let reported = max(reportedCalories, 0)
        let atwater = caloriesFromMacros(proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        if let kilojoules, kilojoules > 0 {
            let sameNumber = reported > 0 && abs(reported - kilojoules) / kilojoules < 0.08
            let fromKJ = (sameNumber ? reported : kilojoules) / 4.184
            if reported == 0 {
                return fromKJ
            }
            if sameNumber, atwater >= 20, reported > atwater * 3, abs(fromKJ - atwater) < abs(reported - atwater) {
                return fromKJ
            }
        }
        if atwater >= 25, reported > atwater * 3.7 {
            let ratio = reported / atwater
            if ratio < 4.7 {
                return reported / 4.184
            }
        }
        return reported
    }

    /// Scale stored macros when the user changes a serving count. `from` and `to` are the same unit.
    static func scaledForQuantityChange(_ macros: MacroTotals, from oldQuantity: Double, to newQuantity: Double) -> MacroTotals {
        scale(macros, by: multiplier(consumed: newQuantity, reference: max(oldQuantity, 0.0001)))
    }

    static func recipeTotals(_ ingredients: [MacroTotals]) -> MacroTotals {
        ingredients.reduce(MacroTotals(), +)
    }

    static func portion(of recipe: MacroTotals, servingsEaten: Double, servingsInRecipe: Double) -> MacroTotals {
        let factor = multiplier(consumed: servingsEaten, reference: max(servingsInRecipe, 0.0001))
        return scale(recipe, by: factor)
    }

    // MARK: - Daily totals / remaining / percentage

    static func dailyTotals(_ entries: [MacroTotals]) -> MacroTotals {
        entries.reduce(MacroTotals(), +)
    }

    /// Negative remaining means the user exceeded the target. Do not clamp to zero.
    static func remaining(consumed: MacroTotals, goal: MacroGoalPayload) -> MacroTotals {
        MacroTotals(
            calories: goal.calories - consumed.calories,
            proteinG: goal.proteinG - consumed.proteinG,
            carbsG: goal.carbsG - consumed.carbsG,
            fatG: goal.fatG - consumed.fatG
        )
    }

    /// Uncapped — 204g vs 185g target is 110.3%, not 100%.
    static func percentOfTarget(consumed: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return consumed / target * 100
    }

    // MARK: - Display rounding (never round intermediates)

    static func displayCalories(_ value: Double) -> Int {
        Int(value.rounded())
    }

    static func displayGrams(_ value: Double) -> Int {
        Int(value.rounded())
    }

    // MARK: - Source selection

    static func preferred(existing: NutritionSource, incoming: NutritionSource) -> NutritionSource {
        incoming.priority < existing.priority ? incoming : existing
    }

    /// User-typed or labeled macros win unless they asked us to verify.
    static func shouldHonorUserMacros(utterance: String) -> Bool {
        let lower = utterance.lowercased()
        let verify = ["check", "verify", "is that right", "does that sound", "confirm the macros"]
        if verify.contains(where: { lower.contains($0) }) { return false }
        return parseUserMacros(from: lower).hasAny
    }

    static func explicitMacroMention(in text: String) -> Bool {
        parseUserMacros(from: text).hasAny
    }

    struct UserMacros: Equatable {
        var calories: Double?
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?

        var hasAny: Bool {
            calories != nil || proteinG != nil || carbsG != nil || fatG != nil
        }
    }

    /// "ice for 5 calories", "20g protein", "~90 cal".
    static func parseUserMacros(from text: String) -> UserMacros {
        let lower = text.lowercased()
        var result = UserMacros()
        result.calories = firstCapture(
            in: lower,
            pattern: #"(?:for|at|only|just|about|around)?\s*(\d+(?:\.\d+)?)\s*(?:kilo)?cal(?:orie)?s?\b"#
        )
        result.proteinG = firstCapture(
            in: lower,
            pattern: #"(\d+(?:\.\d+)?)\s*(?:g(?:rams?)?\s*(?:of\s+)?)?protein\b"#
        )
        result.carbsG = firstCapture(
            in: lower,
            pattern: #"(\d+(?:\.\d+)?)\s*(?:g(?:rams?)?\s*(?:of\s+)?)?(?:carbs?|carbohydrates?)\b"#
        )
        result.fatG = firstCapture(
            in: lower,
            pattern: #"(\d+(?:\.\d+)?)\s*(?:g(?:rams?)?\s*(?:of\s+)?)?fat\b"#
        )
        return result
    }

    private static func firstCapture(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}

extension MacroTotals {
    var displayedCalories: Int { MacroTrackingEngine.displayCalories(calories) }
    var displayedProteinG: Int { MacroTrackingEngine.displayGrams(proteinG) }
    var displayedCarbsG: Int { MacroTrackingEngine.displayGrams(carbsG) }
    var displayedFatG: Int { MacroTrackingEngine.displayGrams(fatG) }

    func scaled(by multiplier: Double) -> MacroTotals {
        MacroTrackingEngine.scale(self, by: multiplier)
    }
}

/// Quantity correction of an already-logged food ("actually that was 8 oz, not 6").
enum FoodLogCorrection {
    struct Match {
        let meal: Meal
        let replacementDescription: String
    }

    static func match(utterance: String, todayMeals: [Meal]) -> Match? {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeCorrection(text), !todayMeals.isEmpty else { return nil }

        let description = correctedDescription(from: text) ?? text
        guard let meal = bestMatchingMeal(for: description, in: todayMeals) else { return nil }
        return Match(meal: meal, replacementDescription: description)
    }

    static func looksLikeCorrection(_ text: String) -> Bool {
        let lower = text.lowercased()
        let triggers = [
            "actually", "i meant", "wait it was", "wait that was",
            "change that", "change the", "update that", "update the",
            "fix that", "fix the", "correct that", "make that",
            "not  ", " not ", ", not ", " instead of ",
        ]
        return triggers.contains { lower.contains($0) }
    }

    private static func correctedDescription(from text: String) -> String? {
        let lower = text.lowercased()
        let patterns = [
            #"actually(?:\s+that was|\s+it was)?\s+(.+?)(?:,?\s+not\b.*)?$"#,
            #"i meant\s+(.+?)(?:,?\s+not\b.*)?$"#,
            #"(?:wait\s+)?(?:that|it) was\s+(.+?)(?:,?\s+not\b.*)?$"#,
            #"(?:change|update|fix|make)\s+(?:that|the|it)\s+(?:to\s+)?(.+)$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let extracted = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if extracted.count >= 3 { return extracted }
        }

        if let notRange = lower.range(of: ", not "), notRange.lowerBound > lower.startIndex {
            let before = String(text[text.startIndex..<notRange.lowerBound])
            if let was = before.range(of: "was ", options: .caseInsensitive) {
                return String(before[was.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func bestMatchingMeal(for description: String, in meals: [Meal]) -> Meal? {
        let tokens = significantTokens(in: description)
        guard !tokens.isEmpty else { return meals.last }

        let scored: [(Meal, Int)] = meals.compactMap { meal in
            let nameTokens = significantTokens(in: meal.name)
            let hits = tokens.filter { token in
                nameTokens.contains(token) || meal.name.lowercased().contains(token)
            }.count
            guard hits > 0 else { return nil }
            return (meal, hits)
        }
        return scored.max { $0.1 < $1.1 }?.0
    }

    private static func significantTokens(in text: String) -> [String] {
        let stop = Set([
            "a", "an", "the", "of", "and", "with", "was", "that", "this", "it",
            "oz", "ounce", "ounces", "g", "gram", "grams", "cup", "cups",
            "not", "actually", "meant", "had", "ate",
        ])
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) && Double($0) == nil }
    }
}
