import Foundation

/// Turns conversational meal descriptions into short log labels (e.g. "2 eggs").
enum FoodItemNaming {
    private static let utterancePrefixes = [
        "hey larry,", "hey larry ", "hey larry today i had ", "hey larry today i ate ",
        "hi larry ", "yo larry ", "ok larry ", "okay larry ",
        "larry,", "larry ", "dear larry ", "sup larry ",
    ]

    private static let consumptionTriggers = [
        "i had ", "i ate ", "i drank ", "i've had ", "ive had ", "i've drank ", "ive drank ",
        "i just had ", "i just ate ", "i just drank ", "just had ", "just ate ", "just drank ",
        "already had ", "already ate ", "already drank ",
    ]

    private static let segmentPrefixes = consumptionTriggers + [
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
        "from costco", "from trader joe's", "from trader joes", "please", "thanks",
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
    ]

    private static let volumeMeasurePhrases = [
        "cups of ", "cup of ", "tablespoons of ", "tablespoon of ", "tbsp of ",
        "ounces of ", "ounce of ", "oz of ",
    ]

    // MARK: - Public

    /// Past-tense consumption clause, e.g. "I had a latte" from "What are my macros? I had a latte".
    static func extractLoggedConsumptionClause(from text: String) -> String? {
        let lower = text.lowercased()
        var best: (index: String.Index, clause: String)?
        for trigger in consumptionTriggers {
            guard let range = lower.range(of: trigger) else { continue }
            let clause = String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if best == nil || range.lowerBound < best!.index {
                best = (range.lowerBound, clause)
            }
        }
        return best?.clause
    }

    /// Best string to estimate macros from — prefers an "I had / I drank …" clause over the full utterance.
    static func loggedFoodDescription(from text: String) -> String? {
        if let clause = extractLoggedConsumptionClause(from: text) {
            return sanitizeSegment(clause)
        }
        return nil
    }

    static func isBeverage(_ text: String) -> Bool {
        let lower = text.lowercased()
        let drinks = [
            "latte", "late", "coffee", "espresso", "cappuccino", "mocha", "frappuccino",
            "smoothie", "shake", "soda", "cola", "juice", "tea", "starbucks", "dunkin",
            "energy drink", "beer", "wine", "cocktail", "milkshake",
            "chocolate milk", "nesquik",
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
        for phrase in fillerPhrases {
            t = t.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        t = stripLeadingQuantityWords(t)
        return collapseWhitespace(t)
    }

    /// Short label for a single food segment (e.g. "2 eggs", "Carrots", "Ground Beef").
    static func logLabel(from segment: String, quantity: Double) -> String {
        let sourceLower = segment.lowercased()
        if let product = matchKnownProduct(in: sourceLower) {
            return product
        }

        let text = sanitizeSegment(segment).lowercased()
        let qty = max(Int(quantity.rounded()), parseQuantity(in: sourceLower), 1)
        if let kind = detectKind(in: text.isEmpty ? sourceLower : text) {
            return titleCase(formatLabel(quantity: qty, kind: kind))
        }

        if hadVolumeMeasure(in: sourceLower) {
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
    static func displayTitle(for storedName: String) -> String {
        canonicalName(for: storedName)
    }

    /// Preferred name to store in the database.
    static func canonicalName(for raw: String) -> String {
        let sourceLower = raw.lowercased()
        if let product = matchKnownProduct(in: sourceLower) {
            return product
        }

        let stripped = stripParentheticalSuffix(raw)
        let sanitized = sanitizeSegment(stripped)
        let lower = sanitized.lowercased()
        let kindText = lower.isEmpty ? sourceLower : lower

        let qty = max(parseQuantity(in: sourceLower), parseQuantity(in: lower), 1)
        if let kind = detectKind(in: kindText) {
            return titleCase(formatLabel(quantity: qty, kind: kind))
        }

        if hadVolumeMeasure(in: sourceLower), !sanitized.isEmpty {
            return titleCase(sanitized)
        }

        if !sanitized.isEmpty, !looksConversational(sanitized), sanitized.count <= 40 {
            return titleCase(sanitized)
        }

        let fallback = sanitizeSegment(raw)
        if fallback.isEmpty { return "Food" }
        let trimmed = fallback.count <= 40 ? fallback : String(fallback.prefix(40)) + "…"
        return titleCase(trimmed)
    }

    static func sanitizedLineItem(_ item: MealLineItem) -> MealLineItem {
        var copy = item
        copy.name = canonicalName(for: item.name)
        return copy
    }

    // MARK: - Food detection

    private enum FoodKind {
        case eggs
        case toast(brand: String?)
        case almondButter
        case peanutButter
        case chicken
        case fish
        case yogurt
        case rice
        case salad
        case burger
        case bigMac
        case carrots
        case groundBeef
        case powerGreenBowl
    }

    private static func detectKind(in text: String) -> FoodKind? {
        if text.contains("power green") || text.contains("powder green") { return .powerGreenBowl }
        if text.contains("big mac") || text.contains("bigmac") { return .bigMac }
        if text.contains("egg") { return .eggs }
        if text.contains("almond butter") { return .almondButter }
        if text.contains("peanut butter") { return .peanutButter }
        if text.contains("toast") || text.contains("bread") || text.contains("dave") {
            let brand = text.contains("dave") ? "Dave's" : nil
            return .toast(brand: brand)
        }
        if text.contains("ground beef") { return .groundBeef }
        if text.contains("carrot") { return .carrots }
        if text.contains("chicken") { return .chicken }
        if text.contains("salmon") || text.contains("fish") { return .fish }
        if text.contains("yogurt") || text.contains("greek") { return .yogurt }
        if text.contains("rice") { return .rice }
        if text.contains("salad") { return .salad }
        if text.contains("burger") || text.contains("pizza") || text.contains("mcdonald") { return .burger }
        return nil
    }

    private static func formatLabel(quantity: Int, kind: FoodKind) -> String {
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
        case .chicken:
            return quantity == 1 ? "1 serving chicken" : "\(quantity) servings chicken"
        case .fish:
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
            return "ground beef"
        case .powerGreenBowl:
            return "Power Green Bowl"
        }
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

    static func parseQuantity(in text: String) -> Int {
        let lower = text.lowercased()
        let words: [(String, Int)] = [
            ("a couple of", 2), ("a couple", 2), ("couple of", 2), ("couple", 2),
            ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6),
        ]
        for (word, value) in words where lower.contains(word) {
            return value
        }
        // Word-boundary match so "about a" doesn't read as quantity 1.
        if let regex = try? NSRegularExpression(pattern: #"(?<![a-z])(?:one|a|an)\b"#),
           regex.firstMatch(in: lower, range: fullNSRange(for: lower)) != nil {
            return 1
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#),
           let match = regex.firstMatch(in: lower, range: fullNSRange(for: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let value = Double(lower[range]) {
            return max(Int(value.rounded()), 1)
        }
        return 1
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
        volumeMeasurePhrases.contains { text.contains($0) }
    }

    private static func stripLeadingQuantityWords(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(?:about|around|approximately|roughly)\s+(?:a|an|one|\d+(?:\.\d+)?)\s+"#,
            #"^(?:a|an|one|\d+(?:\.\d+)?)\s+"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            t = regex.stringByReplacingMatches(in: t, range: fullNSRange(for: t), withTemplate: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
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
