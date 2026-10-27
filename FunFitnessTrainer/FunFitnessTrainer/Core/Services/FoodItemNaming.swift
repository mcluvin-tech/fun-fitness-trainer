import Foundation

/// Turns conversational meal descriptions into short log labels (e.g. "2 eggs").
enum FoodItemNaming {
    private static let utterancePrefixes = [
        "hey larry,", "hey larry ", "hey larry today i had ", "hey larry today i ate ",
        "hi larry ", "yo larry ", "ok larry ", "okay larry ",
        "larry,", "larry ", "dear larry ", "sup larry ",
    ]

    private static let consumptionTriggers = [
        "i also had ", "i also ate ", "i also drank ",
        "i've also had ", "ive also had ",
        "also had ", "also ate ", "also drank ",
        "i had ", "i ate ", "i drank ", "i've had ", "ive had ", "i've drank ", "ive drank ",
        "i just had ", "i just ate ", "i just drank ", "just had ", "just ate ", "just drank ",
        "already had ", "already ate ", "already drank ",
    ]

    /// Present / in-progress consumption — "I'm having Fairlife…" should still resolve as food.
    private static let presentConsumptionTriggers = [
        "i'm having ", "im having ", "i am having ",
        "i'm drinking ", "im drinking ", "i am drinking ",
        "i'm eating ", "im eating ", "i am eating ",
        "having a ", "having an ", "drinking a ", "drinking an ",
        "eating a ", "eating an ",
    ]

    private static let segmentPrefixes = consumptionTriggers + presentConsumptionTriggers + [
        "had some ", "had a ", "had ", "ate some ", "ate a ", "ate ", "drank a ", "drank ",
        "for breakfast ", "for lunch ", "for dinner ", "for a snack ", "this morning ",
        "today i had ", "today i ate ", "today i drank ", "today ", "tonight ",
    ]

    private static let clauseStoppers = [
        " what are", " what's", " whats ", " how many", " how much", " can i ",
        " tell me", " do i have", " am i ", " should i ", " macros", " macro ",
        " calories left", " protein left", " remaining",
        " will that", " would that", " good for my", " fit my macro",
    ]

    private static let hypotheticalPrefixes = [
        "i'm thinking about having ", "im thinking about having ", "i am thinking about having ",
        "i'm thinking about ", "im thinking about ", "i am thinking about ",
        "thinking about having ", "thinking about ",
        "i'm thinking of having ", "im thinking of having ", "i am thinking of having ",
        "i'm thinking of ", "im thinking of ", "i am thinking of ",
        "thinking of having ", "thinking of ", "considering having ", "considering ",
        "wondering if i should have ", "wondering if i should eat ",
        "i'm gonna have ", "im gonna have ", "i am gonna have ",
        "going to have ", "i'm going to have ", "im going to have ",
        "planning on having ", "planning on ", "want to have ", "wanna have ",
    ]

    private static let fillerPhrases = [
        "pieces of ", "piece of ", "slices of ", "slice of ", "loaves of ", "loaf of ",
        "cups of ", "cup of ", "tablespoons of ", "tablespoon of ", "tbsp of ", "tbsp ",
        "rounds of ", "round of ",
        "serving size of ", "servings of ", "serving of ", "size of ",
        "from costco", "from trader joe's", "from trader joes", "please", "thanks",
    ]

    private static let trailingTimePhrases = [
        " today", " tonight", " this morning", " this afternoon", " this evening",
        " yesterday", " earlier", " just now",
    ]

    private static let approximatePrefixes = [
        "about a ", "about an ", "about ", "around a ", "around an ", "around ",
        "approximately a ", "approximately an ", "approximately ",
        "roughly a ", "roughly an ", "roughly ", "some ",
    ]

    private static let trailingClauseStoppers = [
        " which i ", " which i", " which ", " that i ", " that i", " that ",
        " where i ", " where ", " when i ", " when ",
    ]

    /// Speech-to-text often garbles product names — map fuzzy matches to clean labels.
    private static let knownProducts: [(match: (String) -> Bool, label: String)] = [
        ({ $0.contains("power green bowl") || $0.contains("powder green bowl") }, "Power Green Bowl"),
        ({ $0.contains("sugar free") && ($0.contains("latte") || $0.contains("vanilla")) }, "Sugar Free Vanilla Latte"),
        ({ $0.contains("sugar-free") && ($0.contains("latte") || $0.contains("vanilla")) }, "Sugar Free Vanilla Latte"),
        ({ $0.contains("chipotle") && ($0.contains("bowl") || $0.contains("chicken")) }, "Chipotle Chicken Bowl"),
        ({
            ($0.contains("fairlife") || $0.contains("fair life") || $0.contains("core power"))
                && ($0.contains("shake") || $0.contains("nutrition plan"))
        }, "Fairlife Protein Shake"),
        ({
            ($0.contains("fairlife") || $0.contains("fair life"))
                && ($0.contains("chocolate") || $0.contains("core power"))
                && !$0.contains("shake")
        }, "Fairlife Chocolate Milk"),
        ({ $0.contains("fairlife") || $0.contains("fair life") }, "Fairlife Milk"),
    ]

    private static let volumeMeasurePhrases = [
        "cups of ", "cup of ", "tablespoons of ", "tablespoon of ", "tbsp of ",
        "ounces of ", "ounce of ", "oz of ", "pints of ", "pint of ",
    ]

    // MARK: - Public

    /// Past-tense consumption clause, e.g. "I had a latte" from "What are my macros? I had a latte".
    static func extractLoggedConsumptionClause(from text: String) -> String? {
        extractClause(from: text, triggers: consumptionTriggers)
    }

    /// Present / in-progress clause, e.g. "I'm having Fairlife chocolate milk".
    static func extractPresentConsumptionClause(from text: String) -> String? {
        extractClause(from: text, triggers: presentConsumptionTriggers)
    }

    /// Best string to estimate macros from — prefers an "I had / I drank …" clause over the full utterance.
    /// Keeps quantities and list separators ("plus", "and") so multi-item meals can be split.
    static func loggedFoodDescription(from text: String) -> String? {
        if let clause = extractLoggedConsumptionClause(from: text) {
            return foodListForEstimation(from: clause)
        }
        return nil
    }

    /// Food mention for logging — past tense, present "I'm having…", or a cleaned utterance.
    static func foodMentionForLogging(from text: String) -> String? {
        if let past = loggedFoodDescription(from: text) {
            return past
        }
        if let present = extractPresentConsumptionClause(from: text) {
            let cleaned = foodListForEstimation(from: present)
            return cleaned.isEmpty ? nil : cleaned
        }
        let cleaned = foodListForEstimation(from: text)
        return cleaned.isEmpty || cleaned.count < 3 ? nil : cleaned
    }

    /// Speech-to-text `formattedString` capitalizes and often adds a period.
    /// "catalina crunch." keeps the words. A comma between two brand words ("Catalina, crunch") is one product.
    static func normalizedSpeechTranscript(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = CharacterSet(charactersIn: ".!,;:…\"“”。")
        var stripping = true
        while stripping {
            stripping = false
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let scalar = t.unicodeScalars.last, trailing.contains(scalar) else { break }
            t.unicodeScalars.removeLast()
            stripping = true
        }
        t = BrandedFoodResolver.joiningSpokenBrandPairs(t)
        return collapseWhitespace(t)
    }

    private static func extractClause(from text: String, triggers: [String]) -> String? {
        let lower = text.lowercased()
        var best: (index: String.Index, clause: String)?
        for trigger in triggers {
            guard let range = lower.range(of: trigger) else { continue }
            let clause = String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if best == nil || range.lowerBound < best!.index {
                best = (range.lowerBound, clause)
            }
        }
        return best?.clause
    }

    /// Strips greetings / questions but preserves quantities and "plus/and" lists for segmentation.
    static func foodListForEstimation(from text: String) -> String {
        var t = normalizedSpeechTranscript(text)
        if let q = t.firstIndex(of: "?") {
            t = String(t[..<q])
        }
        t = stripPrefixes(t, utterancePrefixes)
        t = stripPrefixes(t, hypotheticalPrefixes)
        t = stripPrefixes(t, segmentPrefixes)
        for stop in clauseStoppers {
            if let range = t.range(of: stop, options: .caseInsensitive) {
                t = String(t[..<range.lowerBound])
            }
        }
        return collapseWhitespace(t)
    }

    static func isBeverage(_ text: String) -> Bool {
        let lower = text.lowercased()
        let drinks = [
            "latte", "late", "coffee", "espresso", "cappuccino", "mocha", "frappuccino",
            "smoothie", "shake", "soda", "cola", "juice", "tea", "starbucks", "dunkin",
            "energy drink", "beer", "wine", "cocktail", "milkshake",
            "chocolate milk", "nesquik", "fairlife", "fair life", "core power",
            "coconut milk", "almond milk", "oat milk", "soy milk",
        ]
        return drinks.contains { lower.contains($0) }
    }

    /// Pulls the food name from macro/calorie questions, e.g. "macros for a Big Mac at McDonald's".
    static func extractFoodReference(from text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = t.firstIndex(of: "?") {
            t = String(t[..<q])
        }
        t = stripPrefixes(t, utterancePrefixes)
        let patterns = [
            #"what(?:'s|s| is)\s+(?:the\s+)?(?:estimated\s+)?macros?\s+for\s+(?:a\s+|an\s+)?(.+)$"#,
            #"estimated\s+macros?\s+for\s+(?:a\s+|an\s+)?(.+)$"#,
            #"macros?\s+(?:for|in|of)\s+(?:a\s+|an\s+)?(.+)$"#,
            #"how\s+many\s+calories?\s+(?:are\s+)?in\s+(?:a\s+|an\s+)?(.+)$"#,
            #"calories?\s+in\s+(?:a\s+|an\s+)?(.+)$"#,
            #"nutrition(?:al)?\s+(?:info\s+)?for\s+(?:a\s+|an\s+)?(.+)$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: t, range: fullNSRange(for: t)),
                  let range = Range(match.range(at: 1), in: t) else { continue }
            var food = String(t[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            food = stripLocationSuffix(food)
            if !food.isEmpty { return food }
        }
        return nil
    }

    static func sanitizeUtterance(_ text: String) -> String {
        sanitizeSegment(text)
    }

    static func sanitizeSegment(_ segment: String) -> String {
        var t = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = t.firstIndex(of: "?") {
            t = String(t[..<q])
        }
        if let logged = extractLoggedConsumptionClause(from: t) {
            t = logged.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        t = stripPrefixes(t, utterancePrefixes)
        t = stripPrefixes(t, hypotheticalPrefixes)
        t = stripPrefixes(t, segmentPrefixes)
        t = stripPrefixes(t, approximatePrefixes)
        for stop in clauseStoppers {
            if let range = t.range(of: stop, options: .caseInsensitive) {
                t = String(t[..<range.lowerBound])
            }
        }
        for stop in trailingClauseStoppers {
            if let range = t.range(of: stop, options: .caseInsensitive) {
                t = String(t[..<range.lowerBound])
            }
        }
        for phrase in trailingTimePhrases {
            if t.lowercased().hasSuffix(phrase) {
                t = String(t.dropLast(phrase.count))
            }
        }
        for phrase in fillerPhrases {
            t = t.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        // Speech-to-text often hears "chips" as "chicks".
        if let regex = try? NSRegularExpression(pattern: #"\bchicks\b"#, options: .caseInsensitive) {
            t = regex.stringByReplacingMatches(in: t, range: fullNSRange(for: t), withTemplate: "chips")
        }
        t = stripLeadingQuantityWords(t)
        t = FoodQuantity.strippingMacroClauses(t)
        return collapseWhitespace(t)
    }

    /// Short label for a single food segment (e.g. "2 eggs", "Chicken", "Carrots").
    /// The portion stays on the meal's quantity and unit. It is not written into the name.
    static func logLabel(from segment: String, quantity: Double) -> String {
        displayFoodName(rawLogLabel(from: segment, quantity: quantity))
    }

    private static func rawLogLabel(from segment: String, quantity: Double) -> String {
        if let measured = measuredLabel(from: segment) {
            return measured
        }
        let sourceLower = segment.lowercased()
        if let product = matchKnownProduct(in: sourceLower) {
            return product
        }

        let text = sanitizeSegment(segment).lowercased()
        let qty = max(Int(quantity.rounded()), parseQuantity(in: sourceLower), 1)
        if let kind = detectKind(in: text.isEmpty ? sourceLower : text) {
            return titleCase(formatLabel(quantity: qty, kind: kind, source: sourceLower))
        }

        if hadVolumeMeasure(in: sourceLower) {
            if let labeled = volumeLabel(from: segment) {
                return labeled
            }
            let trimmed = sanitizeSegment(segment)
            guard !trimmed.isEmpty else { return "Food" }
            return titleCase(trimmed)
        }

        let trimmed = sanitizeSegment(segment)
        guard !trimmed.isEmpty else { return "Food" }
        let short = trimmed.count <= 32 ? trimmed : String(trimmed.prefix(32)) + "…"
        return titleCase(short)
    }

    /// Cleans names already stored (including legacy conversational titles).
    /// Today's log and meal rows never show dashes.
    static func displayTitle(for storedName: String) -> String {
        stripDashes(canonicalName(for: storedName))
    }

    /// Removes em/en/hyphen dashes from user-facing food labels.
    static func stripDashes(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: " — ", with: ", ")
        s = s.replacingOccurrences(of: " – ", with: ", ")
        s = s.replacingOccurrences(of: " - ", with: ", ")
        s = s.replacingOccurrences(of: "—", with: ", ")
        s = s.replacingOccurrences(of: "–", with: ", ")
        s = s.replacingOccurrences(of: "-", with: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        s = s.replacingOccurrences(of: " ,", with: ",")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Preferred name to store in the database (no dashes).
    static func canonicalName(for raw: String) -> String {
        let named: String
        if let measured = measuredLabel(from: raw) {
            named = measured
        } else {
            let sourceLower = raw.lowercased()
            if let product = matchKnownProduct(in: sourceLower) {
                named = product
            } else {
                let stripped = stripParentheticalSuffix(raw)
                let sanitized = sanitizeSegment(stripped)
                let lower = sanitized.lowercased()
                let kindText = lower.isEmpty ? sourceLower : lower

                let qty = max(parseQuantity(in: sourceLower), parseQuantity(in: lower), 1)
                if let kind = detectKind(in: kindText) {
                    named = titleCase(formatLabel(quantity: qty, kind: kind, source: sourceLower))
                } else if hadVolumeMeasure(in: sourceLower), !sanitized.isEmpty {
                    if let labeled = volumeLabel(from: raw) {
                        named = labeled
                    } else {
                        named = titleCase(sanitized)
                    }
                } else if !sanitized.isEmpty, !looksConversational(sanitized), sanitized.count <= 40 {
                    named = titleCase(sanitized)
                } else {
                    let fallback = sanitizeSegment(raw)
                    if fallback.isEmpty {
                        named = "Food"
                    } else {
                        let trimmed = fallback.count <= 40 ? fallback : String(fallback.prefix(40)) + "…"
                        named = titleCase(trimmed)
                    }
                }
            }
        }
        return stripDashes(displayFoodName(named))
    }

    static func sanitizedLineItem(_ item: MealLineItem) -> MealLineItem {
        var copy = item
        copy.name = canonicalName(for: item.name)
        return copy
    }

    /// True when two labels are the same food ("2 eggs" / "two eggs", "clementines" / "clementine").
    static func refersToSameFood(_ a: String, _ b: String) -> Bool {
        let left = significantFoodWords(in: a)
        let right = significantFoodWords(in: b)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return !left.isDisjoint(with: right)
    }

    private static func significantFoodWords(in text: String) -> Set<String> {
        let stop: Set<String> = [
            "a", "an", "the", "of", "and", "with", "plus", "also", "had", "ate", "drank",
            "slice", "slices", "piece", "pieces", "serving", "servings", "some", "my",
            "for", "to", "on", "oz", "cup", "cups", "tbsp", "pint", "pints",
        ]
        return Set(text.lowercased().split { !$0.isLetter }.compactMap { raw in
            let token = String(raw)
            guard token.count > 2, !stop.contains(token) else { return nil }
            if token.hasSuffix("s"), token.count > 3 {
                return String(token.dropLast())
            }
            return token
        })
    }

    // MARK: - Food detection

    private enum FoodKind {
        case eggs
        case toast(brand: String?)
        case almondButter
        case peanutButter
        case sandwich
        case chicken
        case chips
        case fish
        case yogurt
        case rice
        case salad
        case burger
        case bigMac
        case carrots
        case groundBeef
        case powerGreenBowl
        case banana
        case butter
    }

    private static func detectKind(in text: String) -> FoodKind? {
        if text.contains("power green") || text.contains("powder green") { return .powerGreenBowl }
        if text.contains("big mac") || text.contains("bigmac") { return .bigMac }
        if (matchesFoodToken(text, "chips") || matchesFoodToken(text, "chip")),
           !text.contains("bar"), !text.contains("cookie"), !text.contains("quest") {
            return .chips
        }
        if text.contains("sandwich") { return .sandwich }
        if text.contains("egg") { return .eggs }
        if text.contains("almond butter") { return .almondButter }
        if text.contains("peanut butter") { return .peanutButter }
        if text.contains("toast") || text.contains("bread") || text.contains("dave") {
            // "Cinnamon Toast Cereal" is a box of cereal, not a slice of bread.
            let packagedCereal = text.contains("cereal") || text.contains("crunch") || text.contains("catalina")
            if !packagedCereal {
                let brand = text.contains("dave") ? "Dave's" : nil
                return .toast(brand: brand)
            }
        }
        if text.contains("ground beef") { return .groundBeef }
        if text.contains("carrot") { return .carrots }
        if text.contains("banana") { return .banana }
        if matchesFoodToken(text, "butter") && !text.contains("peanut") && !text.contains("almond") && !text.contains("nut") {
            return .butter
        }
        if text.contains("chicken"), !text.contains("chipotle") { return .chicken }
        if text.contains("salmon") || text.contains("fish") { return .fish }
        if text.contains("yogurt") || text.contains("greek") { return .yogurt }
        if text.contains("rice") { return .rice }
        if text.contains("salad") { return .salad }
        if text.contains("burger") || text.contains("pizza") || text.contains("mcdonald") { return .burger }
        return nil
    }

    private static func formatLabel(quantity: Int, kind: FoodKind, source: String) -> String {
        switch kind {
        case .eggs:
            return quantity == 1 ? "1 egg" : "\(quantity) eggs"
        case .toast(let brand):
            let name = brand.map { "\($0) toast" } ?? "toast"
            return quantity == 1 ? "1 slice \(name)" : "\(quantity) slices \(name)"
        case .almondButter:
            return quantity == 1 ? "1 tbsp almond butter" : "\(quantity) tbsp almond butter"
        case .peanutButter:
            return quantity == 1 ? "1 tbsp peanut butter" : "\(quantity) tbsp peanut butter"
        case .sandwich:
            return quantity == 1 ? "1 sandwich" : "\(quantity) sandwiches"
        case .chicken:
            if let weight = weightLabel(in: source, food: "chicken") { return weight }
            return quantity == 1 ? "1 serving chicken" : "\(quantity) servings chicken"
        case .chips:
            return quantity == 1 ? "1 serving chips" : "\(quantity) servings chips"
        case .fish:
            if let weight = weightLabel(in: source, food: "fish") { return weight }
            return quantity == 1 ? "1 serving fish" : "\(quantity) servings fish"
        case .yogurt:
            return quantity == 1 ? "1 cup Greek yogurt" : "\(quantity) cups Greek yogurt"
        case .rice:
            return quantity == 1 ? "1 cup rice" : "\(quantity) cups rice"
        case .salad:
            return quantity == 1 ? "1 salad" : "\(quantity) salads"
        case .burger:
            return quantity == 1 ? "1 burger" : "\(quantity) burgers"
        case .bigMac:
            return quantity == 1 ? "1 Big Mac" : "\(quantity) Big Macs"
        case .carrots:
            return "carrots"
        case .groundBeef:
            if let weight = weightLabel(in: source, food: "ground beef") { return weight }
            return "ground beef"
        case .powerGreenBowl:
            return "Power Green Bowl"
        case .banana:
            return quantity == 1 ? "1 banana" : "\(quantity) bananas"
        case .butter:
            return quantity == 1 ? "butter" : "\(quantity) tbsp butter"
        }
    }

    /// Keep "6 oz cooked chicken" instead of collapsing ounces into a serving count.
    private static func measuredLabel(from raw: String) -> String? {
        let lower = raw.lowercased()
        guard let grams = FoodQuantity.parseGrams(in: lower) ?? FoodQuantity.parseOunces(in: lower).map({ $0 * FoodUnit.gramsPerOunce }),
              !FoodQuantity.looksLikeBeverage(lower) else { return nil }

        let food: String
        if lower.contains("chicken") { food = "chicken" }
        else if lower.contains("ground beef") { food = "ground beef" }
        else if lower.contains("salmon") { food = "salmon" }
        else if matchesFoodToken(lower, "fish") { food = "fish" }
        else { return nil }

        let prep = FoodQuantity.preparation(in: lower)
        let prepWord = prep == .unknown ? "" : " \(prep.rawValue)"
        if let oz = FoodQuantity.parseOunces(in: lower), FoodQuantity.parseGrams(in: lower) == nil {
            let ozText = oz == floor(oz) ? "\(Int(oz))" : String(format: "%g", oz)
            return titleCase("\(ozText) oz\(prepWord) \(food)")
        }
        let gText = grams == floor(grams) ? "\(Int(grams))" : String(format: "%g", grams)
        return titleCase("\(gText) g\(prepWord) \(food)")
    }

    private static func weightLabel(in source: String, food: String) -> String? {
        measuredLabel(from: source)?.contains(food) == true ? measuredLabel(from: source) : nil
    }

    private static func stripLocationSuffix(_ food: String) -> String {
        var t = food
        let suffixes = [" at mcdonald's", " at mcdonalds", " from mcdonald's", " from mcdonalds"]
        for suffix in suffixes {
            if let range = t.range(of: suffix, options: .caseInsensitive) {
                t = String(t[..<range.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses "8 oz", "8 fl oz", "16 ounces", etc.
    /// Weight ounces on solids (chicken) are not fluid ounces.
    static func parseFluidOunces(in text: String) -> Double? {
        if let explicit = FoodQuantity.parseExplicitFluidOunces(in: text) {
            return explicit
        }
        if let pints = FoodQuantity.pintFluidOunces(in: text) {
            return pints
        }
        guard FoodQuantity.looksLikeBeverage(text) else { return nil }
        return FoodQuantity.parseOunces(in: text)
    }

    static func parseQuantity(in text: String) -> Int {
        let portion = FoodQuantity.parse(from: text)
        if portion.unit == .fluidOunce || portion.unit == .milliliter {
            return 1
        }
        if portion.unit.isMass {
            return 1
        }
        return max(Int(portion.amount.rounded()), 1)
    }

    // MARK: - Helpers

    private static func stripParentheticalSuffix(_ name: String) -> String {
        if let open = name.lastIndex(of: "("), open > name.startIndex {
            return String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    private static func looksConversational(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains(" i had") || lower.contains("hey ") || lower.hasPrefix("today ")
            || lower.contains("what are") || lower.contains("tell me")
    }

    private static func stripPrefixes(_ text: String, _ prefixes: [String]) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lower = t.lowercased()
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes where lower.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                lower = t.lowercased()
                changed = true
                break
            }
        }
        return t
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func matchKnownProduct(in text: String) -> String? {
        let lower = text.lowercased()
        for (match, label) in knownProducts where match(lower) {
            return label
        }
        return nil
    }

    private static func hadVolumeMeasure(in text: String) -> Bool {
        volumeMeasurePhrases.contains { text.contains($0) } || parseFluidOunces(in: text) != nil
    }

    /// Keeps portion in the log label: "16 ounces of coconut milk" → "16 Oz Coconut Milk".
    /// A pint stays "Pint of beer". Re-running this must not stack another "oz".
    private static func volumeLabel(from segment: String) -> String? {
        let lower = segment.lowercased()
        let food = foodNameWithoutMeasure(segment)
        guard !food.isEmpty else { return nil }
        if lower.range(of: #"\bpints?\b"#, options: .regularExpression) != nil {
            let pints = (FoodQuantity.pintFluidOunces(in: lower) ?? 16) / 16
            if abs(pints - 1) < 0.05 { return titleCase("pint of \(food)") }
            let count = pints == floor(pints) ? "\(Int(pints))" : String(format: "%g", pints)
            return titleCase("\(count) pints of \(food)")
        }
        guard let oz = parseFluidOunces(in: lower) else { return nil }
        let ozText = oz == floor(oz) ? "\(Int(oz))" : String(format: "%g", oz)
        return titleCase("\(ozText) oz \(food)")
    }

    /// Drops measure words so "16 oz oz pint of beer" becomes "beer".
    private static func foodNameWithoutMeasure(_ segment: String) -> String {
        var food = sanitizeSegment(segment).lowercased()
        let patterns = [
            #"\d+(?:\.\d+)?\s*(?:fl\.?\s*)?(?:oz|ounces?)\b"#,
            #"\bfl\.?\s*oz\b"#,
            #"\bounces?\b"#,
            #"\boz\b"#,
            #"\bpints?\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            food = regex.stringByReplacingMatches(in: food, range: fullNSRange(for: food), withTemplate: " ")
        }
        food = collapseWhitespace(food)
        while food.hasPrefix("of ") {
            food = String(food.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        return food
    }

    /// Whole-token match so "chip" does not hit "chipotle".
    private static func matchesFoodToken(_ text: String, _ token: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b",
            options: .caseInsensitive
        ) else {
            return text.split(whereSeparator: { !$0.isLetter }).contains { $0.lowercased() == token }
        }
        return regex.firstMatch(in: text, range: fullNSRange(for: text)) != nil
    }

    private static func stripLeadingQuantityWords(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Take the unit with the number. Stripping only "4 " from "4 oz canned tuna" left "oz canned tuna".
        let unit = #"(?:fl\.?\s*oz|fluid\s+ounces?|ounces?|oz|grams?|g|cups?|servings?(?:\s+size)?)\b"#
        let patterns = [
            #"^(?:about|around|approximately|roughly)\s+(?:a|an|one|\d+(?:\.\d+)?)(?:\s+"# + unit + #")?\s+"#,
            #"^(?:a|an|one|\d+(?:\.\d+)?)(?:\s+"# + unit + #")?\s+"#,
            #"^(?:"# + unit + #")\s+"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            t = regex.stringByReplacingMatches(in: t, range: fullNSRange(for: t), withTemplate: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Food identity only. Quantity and unit stay on the meal, so a label never starts with "Oz" or "Serving".
    /// "Pint of beer" keeps its "of"; other "of" words are removed only when they are left hanging on the edge.
    private static func displayFoodName(_ text: String) -> String {
        var t = collapseWhitespace(text)
        guard !t.isEmpty else { return t }

        let patterns = [
            #"\bi\s+had\b"#,
            #"\bserving\s+size\b"#,
            #"\b\d+(?:\.\d+)?\s+fl\.?\s*oz\b"#,
            #"\b\d+(?:\.\d+)?\s+fluid\s+ounces?\b"#,
            #"\b\d+(?:\.\d+)?\s+ounces?\b"#,
            #"\b\d+(?:\.\d+)?\s+oz\b"#,
            #"\b\d+(?:\.\d+)?\s+grams?\b"#,
            #"\b\d+(?:\.\d+)?\s+g\b"#,
            #"\b\d+(?:\.\d+)?\s+cups?\b"#,
            #"\b\d+(?:\.\d+)?\s+servings?\b"#,
            #"\bfl\.?\s*oz\b"#,
            #"\bfluid\s+ounces?\b"#,
            #"\bounces?\b"#,
            #"\boz\b"#,
            #"\bgrams?\b"#,
            #"\bg\b"#,
            #"\bcups?\b"#,
            #"\bservings?\b"#,
            #"\bcans?\b"#,
            #"\btins?\b"#,
            #"\bsome\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            t = regex.stringByReplacingMatches(in: t, range: fullNSRange(for: t), withTemplate: " ")
        }
        t = collapseWhitespace(t)

        var trimmedEdge = true
        while trimmedEdge {
            trimmedEdge = false
            for pattern in [#"^(?:a|an|of)\s+"#, #"\s+of$"#] {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                let next = collapseWhitespace(
                    regex.stringByReplacingMatches(in: t, range: fullNSRange(for: t), withTemplate: " ")
                )
                if next != t {
                    trimmedEdge = true
                    t = next
                }
            }
        }

        if t.isEmpty { return "Food" }
        return titleCase(t)
    }

    /// UTF-16 range for NSRegularExpression (safe with emoji and apostrophes).
    private static func fullNSRange(for text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
    }

    /// "2 eggs" → "2 Eggs", preserves brands like "Dave's".
    private static func titleCase(_ text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { word in
                let s = String(word)
                guard let first = s.first else { return s }

                if s.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                    return s
                }

                if s.contains(where: \.isUppercase), s != s.uppercased() {
                    return s
                }

                return first.uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
