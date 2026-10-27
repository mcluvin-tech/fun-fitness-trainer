import Foundation

/// One packaged or restaurant product returned by a brand catalog.
struct BrandedFoodHit: Equatable {
    var name: String
    var brand: String?
    var perServing: MacroTotals
    var servingDescription: String?
    var barcode: String?
    var source: MacroTrackingEngine.NutritionSource
    /// 0–1, filled in by the ranker. Catalogs leave this at 0.
    var score: Double = 0
}

struct BrandedFoodResolution: Equatable {
    var best: BrandedFoodHit
    var alternatives: [BrandedFoodHit]
    /// True when the best hit is too weak, or a rival is close enough that guessing would be wrong.
    var needsConfirmation: Bool
}

struct FoodLookupChoice: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var meal: MealPayload
}

struct FoodLookupOutcome: Equatable {
    var meal: MealPayload
    var choices: [FoodLookupChoice]
    var needsConfirmation: Bool
}

/// Brand/product search. Tests install a stand-in so lookups never touch the network.
protocol BrandedFoodCatalog {
    func searchBranded(query: String) async -> [BrandedFoodHit]
}

/// USDA Branded foods and Open Food Facts, side by side.
/// USDA uses the optional `USDA_API_KEY` already read by barcode lookup, or the public demo key.
/// Open Food Facts needs no key. A failure on either side returns nothing from that side.
struct LiveBrandedFoodCatalog: BrandedFoodCatalog {
    func searchBranded(query: String) async -> [BrandedFoodHit] {
        await Self.combiningIndependentResults(
            usda: { await Self.usdaHits(query) },
            off: { await Self.offHits(query) }
        )
    }

    /// Each side catches its own failure. A 503 or timeout from one catalog cannot cancel the other.
    static func combiningIndependentResults(
        usda: () async throws -> [BrandedFoodHit],
        off: () async throws -> [BrandedFoodHit]
    ) async -> [BrandedFoodHit] {
        await withTaskGroup(of: (String, [BrandedFoodHit]).self) { group in
            group.addTask {
                do { return ("usda", try await usda()) } catch { return ("usda", []) }
            }
            group.addTask {
                do { return ("off", try await off()) } catch { return ("off", []) }
            }
            var usdaHits: [BrandedFoodHit] = []
            var offHits: [BrandedFoodHit] = []
            for await (side, hits) in group {
                if side == "usda" {
                    usdaHits = hits
                } else {
                    offHits = hits
                }
            }
            return usdaHits + offHits
        }
    }

    private static func usdaHits(_ query: String) async -> [BrandedFoodHit] {
        await USDAFoodDataService.searchBranded(query: query).map { hit in
            BrandedFoodHit(
                name: hit.name,
                brand: hit.brand,
                perServing: hit.perServing,
                servingDescription: hit.servingDescription,
                barcode: hit.barcode,
                source: .usda
            )
        }
    }

    /// Open Food Facts is capped so a hung 503 cannot hold up USDA hits that already came back.
    private static func offHits(_ query: String) async -> [BrandedFoodHit] {
        let products = await productsFromOpenFoodFacts(query: query, within: 2.5)
        return products.map { product in
            BrandedFoodHit(
                name: product.name,
                brand: product.brand,
                perServing: product.perServing,
                servingDescription: product.servingDescription,
                barcode: product.barcode.isEmpty ? nil : product.barcode,
                source: .manufacturer
            )
        }
    }

    private static func productsFromOpenFoodFacts(
        query: String,
        within seconds: Double
    ) async -> [BarcodeProductResult] {
        await withTaskGroup(of: [BarcodeProductResult]?.self) { group in
            group.addTask {
                await OpenFoodFactsService.searchCandidates(query: query)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }
}

/// Turns whatever name Luke used into a real per-serving label.
///
/// Order: spelling fix, then a local staple when that staple actually covers the phrase,
/// then a ranked search of branded catalogs, then the existing generic USDA / Open Food Facts path.
/// Repeats of the same corrected name reuse the last ranked result.
enum BrandedFoodResolver {
    private static let lock = NSLock()
    private static var catalog: BrandedFoodCatalog = LiveBrandedFoodCatalog()
    private static var cache: [String: BrandedFoodResolution] = [:]
    private static var cacheOrder: [String] = []

    /// Words that are a product form. A chicken staple must not swallow "protein shake".
    private static let productForms: Set<String> = [
        "shake", "bar", "cereal", "burrito", "wrap", "taco", "quesadilla",
    ]

    /// Everyday foods stay on the staple / generic USDA path.
    private static let genericFoodWords: Set<String> = [
        "honey", "chicken", "egg", "rice", "milk", "yogurt", "greek", "spinach", "oil", "olive",
        "butter", "beef", "salmon", "fish", "oat", "oatmeal", "potato", "bread", "toast", "beer",
        "wine", "coffee", "latte", "banana", "apple", "orange", "broccoli", "tuna", "shrimp",
        "turkey", "pasta", "water", "ice", "breast", "juice", "bean", "salsa", "cheese", "avocado",
        "carrot", "peanut", "almond", "soy", "coconut", "sirloin", "grain", "seed", "fruit",
        "whole", "skim", "white", "brown",
    ]

    private static let stopWords: Set<String> = [
        "a", "an", "the", "of", "with", "and", "plus", "i", "had", "my", "some", "for", "to", "on",
        "it", "was", "bowl", "cup", "slice", "serving", "oz", "ounce", "gram", "grams", "ml",
        "about", "just", "only", "fl", "fluid", "large", "small", "medium", "one", "two", "half",
        "grilled", "baked", "roasted", "fried", "raw", "cooked", "fresh", "organic", "plain",
        "leftover", "homemade", "steamed", "boiled", "crispy", "boneless", "skinless", "unsweetened",
    ]

    /// Brand words we are willing to repair. A one-letter slip ("catalena") maps here. Everyday words do not.
    private static let brandLexicon: [String] = [
        "catalina", "crunch", "quest", "fairlife", "chipotle", "killer", "daves",
    ]

    static func useCatalogForTests(_ replacement: BrandedFoodCatalog) {
        lock.lock()
        catalog = replacement
        cache.removeAll()
        cacheOrder.removeAll()
        lock.unlock()
    }

    static func restoreLiveCatalogForTests() {
        useCatalogForTests(LiveBrandedFoodCatalog())
    }

    /// "Catalina, Crunch" is one product. "eggs, toast" stays two foods.
    static func joiningSpokenBrandPairs(_ text: String) -> String {
        let pattern = #"\b([\p{L}']{3,})\s*,\s*([\p{L}']{3,})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges == 3,
                  let whole = Range(match.range, in: result),
                  let leftRange = Range(match.range(at: 1), in: result),
                  let rightRange = Range(match.range(at: 2), in: result) else { continue }
            let left = String(result[leftRange])
            let right = String(result[rightRange])
            guard isBrandLexiconWord(left), isBrandLexiconWord(right) else { continue }
            let fixedLeft = correctedBrandToken(left.lowercased()) ?? left
            let fixedRight = correctedBrandToken(right.lowercased()) ?? right
            result.replaceSubrange(whole, with: "\(fixedLeft) \(fixedRight)")
        }
        return result
    }

    static func isBrandLexiconWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        if brandLexicon.contains(lower) { return true }
        return correctedBrandToken(lower) != nil
    }

    static func correctedPhrase(_ text: String) -> String {
        let pattern = #"\b[\p{L}']+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let word = ns.substring(with: match.range)
            guard let fixed = correctedBrandToken(word),
                  fixed.caseInsensitiveCompare(word) != .orderedSame,
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: fixed)
        }
        return result
    }

    /// Local staple wins only when it covers the product form the person actually said.
    static func trustedStapleCovers(_ query: String) -> Bool {
        let phrase = correctedPhrase(query)
        guard let entry = StapleNutritionDatabase.scale(for: phrase)?.entry else { return false }
        let tokens = Set(distinctiveTokens(phrase))
        let entryTokens = Set(distinctiveTokens(
            ([entry.displayName, entry.brand ?? ""] + entry.aliases).joined(separator: " ")
        ))
        for form in productForms where tokens.contains(form) {
            if !entryTokens.contains(form) { return false }
        }
        return true
    }

    /// Branded search is for names the staple list does not already own.
    static func shouldSearchCatalog(_ query: String) -> Bool {
        let phrase = correctedPhrase(query)
        if trustedStapleCovers(phrase) { return false }
        let tokens = distinctiveTokens(phrase)
        if tokens.isEmpty { return false }
        if tokens.allSatisfy({ genericFoodWords.contains($0) }) { return false }
        return true
    }

    static func resolve(query: String) async -> BrandedFoodResolution? {
        let search = searchText(for: query)
        guard !search.isEmpty else { return nil }

        lock.lock()
        if let cached = cache[search] {
            lock.unlock()
            return cached
        }
        let active = catalog
        lock.unlock()

        let hits = await active.searchBranded(query: search)
        guard let ranked = rank(searchText: search, hits: hits) else { return nil }

        lock.lock()
        if cache[search] == nil {
            cacheOrder.append(search)
        }
        cache[search] = ranked
        while cacheOrder.count > 60 {
            let evict = cacheOrder.removeFirst()
            cache.removeValue(forKey: evict)
        }
        lock.unlock()
        return ranked
    }

    static func searchText(for query: String) -> String {
        distinctiveTokens(correctedPhrase(query)).joined(separator: " ")
    }

    /// Every distinctive word has to show up on the brand or the product. "Catalina" dressing loses to a missing "crunch".
    static func rank(searchText: String, hits: [BrandedFoodHit]) -> BrandedFoodResolution? {
        let tokens = searchText.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        var scored: [BrandedFoodHit] = []
        for var hit in hits {
            let score = matchScore(tokens: tokens, hit: hit)
            guard score >= 0.72, hit.perServing.calories > 0 else { continue }
            hit.score = score
            scored.append(hit)
        }
        guard !scored.isEmpty else { return nil }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let best = scored[0]
        let alternatives = scored.dropFirst().filter { isUsefulAlternative($0, best: best) }.prefix(3)
        let rival = alternatives.contains { alt in
            alt.score >= best.score - 0.03
                && abs(alt.perServing.calories - best.perServing.calories) / max(best.perServing.calories, 1) > 0.25
        }
        return BrandedFoodResolution(
            best: best,
            alternatives: Array(alternatives),
            needsConfirmation: best.score < 0.82 || rival
        )
    }

    // MARK: - Scoring

    private static func matchScore(tokens: [String], hit: BrandedFoodHit) -> Double {
        let haystack = "\(hit.brand ?? "") \(hit.name)"
        guard tokens.allSatisfy({ containsToken($0, in: haystack) }) else { return 0 }

        var score = 0.78 + min(0.08, Double(tokens.count) * 0.02)
        if let brand = hit.brand, distinctiveTokens(brand).contains(where: { tokens.contains($0) }) {
            score += 0.05
        }
        score += preferredVarietyBoost(tokens: tokens, hit: hit)
        score += servingQuality(hit)
        return min(score, 0.99)
    }

    /// No flavor in the phrase: Catalina Crunch means the cinnamon toast cereal, Quest means a chocolate chip bar.
    private static func preferredVarietyBoost(tokens: [String], hit: BrandedFoodHit) -> Double {
        let name = "\(hit.brand ?? "") \(hit.name)".lowercased()
        let asked = Set(tokens)
        if asked.contains("catalina"), asked.contains("crunch"), !asksForFlavor(asked, besides: ["catalina", "crunch"]) {
            var boost = 0.0
            if name.contains("cereal"), !name.contains("cookie"), !name.contains("mix") {
                boost += 0.03
            }
            if name.contains("cinnamon"), name.contains("toast") {
                boost += 0.06
            }
            return boost
        }
        if asked.contains("quest"), asked.contains("bar"), !asksForFlavor(asked, besides: ["quest", "bar", "protein"]) {
            var boost = 0.0
            if hit.perServing.calories >= 170, hit.perServing.calories <= 210,
               hit.perServing.proteinG >= 18, hit.perServing.proteinG <= 24 {
                boost += 0.02
            }
            if name.contains("chocolate"), name.contains("chip") {
                boost += 0.04
            }
            return boost
        }
        return 0
    }

    private static func asksForFlavor(_ tokens: Set<String>, besides brand: Set<String>) -> Bool {
        let flavors: Set<String> = [
            "cinnamon", "chocolate", "apple", "mint", "cheddar", "banana", "peanut", "vanilla",
            "brownie", "cookie", "pumpkin", "strawberry", "blueberry", "maple", "honey", "caramel",
        ]
        return !tokens.subtracting(brand).isDisjoint(with: flavors)
    }

    private static func servingQuality(_ hit: BrandedFoodHit) -> Double {
        let text = (hit.servingDescription ?? "").lowercased()
        if text.contains("cup") || text.contains("bar") || text.contains("slice")
            || text.contains("bottle") || text.contains("fl oz") || text.contains("container") {
            return 0.04
        }
        if text.contains("portion") { return -0.04 }
        return 0
    }

    /// Drop a second copy of the same flavor whose calories are a bad serving (225 vs 110).
    private static func isUsefulAlternative(_ alt: BrandedFoodHit, best: BrandedFoodHit) -> Bool {
        guard alt.score >= 0.80 else { return false }
        let ratio = alt.perServing.calories / max(best.perServing.calories, 1)
        if flavorSignature(alt) == flavorSignature(best), ratio > 1.4 || ratio < 0.7 {
            return false
        }
        return true
    }

    private static func flavorSignature(_ hit: BrandedFoodHit) -> String {
        var text = "\(hit.brand ?? "") \(hit.name)".lowercased()
        for word in ["cereal", "protein", "bar", "shake", "the", "and", "with"] {
            text = text.replacingOccurrences(of: word, with: " ")
        }
        return distinctiveTokens(text).joined(separator: " ")
    }

    // MARK: - Tokens

    static func distinctiveTokens(_ text: String) -> [String] {
        var seen: [String] = []
        let parts = text.lowercased().split { character in
            !(character.isLetter || character.isNumber || character == "'" || character == "’")
        }
        for raw in parts {
            var token = String(raw)
            if token.allSatisfy(\.isNumber) { continue }
            if token.count < 3 { continue }
            if token.hasSuffix("s"), token.count > 3, !token.hasSuffix("ss") {
                let stem = String(token.dropLast())
                if stem.allSatisfy(\.isLetter) { token = stem }
            }
            if stopWords.contains(token) { continue }
            if !seen.contains(token) { seen.append(token) }
        }
        return seen
    }

    private static func containsToken(_ token: String, in text: String) -> Bool {
        let words = distinctiveTokens(text) + unstemmedWords(text)
        if words.contains(token) { return true }
        let stemmed = words.map { stem($0) }
        if stemmed.contains(token) { return true }
        guard token.count >= 6 else { return false }
        return words.contains { word in
            let candidate = stem(word)
            return candidate.count >= 6
                && abs(candidate.count - token.count) <= 1
                && levenshtein(token, candidate) <= 1
        }
    }

    private static func unstemmedWords(_ text: String) -> [String] {
        text.lowercased().split { character in
            !(character.isLetter || character.isNumber)
        }.map(String.init).filter { $0.count >= 3 }
    }

    private static func stem(_ token: String) -> String {
        guard token.hasSuffix("s"), token.count > 3, !token.hasSuffix("ss") else { return token }
        let trimmed = String(token.dropLast())
        return trimmed.allSatisfy(\.isLetter) ? trimmed : token
    }

    private static func correctedBrandToken(_ word: String) -> String? {
        let lower = word.lowercased()
        if brandLexicon.contains(lower) { return nil }
        guard lower.count >= 5 else { return nil }
        let matches = brandLexicon.filter { candidate in
            candidate.count >= 5
                && abs(candidate.count - lower.count) <= 1
                && levenshtein(lower, candidate) <= 1
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let left = Array(a)
        let right = Array(b)
        if abs(left.count - right.count) > 2 { return 3 }
        var previous = Array(0...right.count)
        for (row, character) in left.enumerated() {
            var current = [row + 1]
            for (column, other) in right.enumerated() {
                let cost = character == other ? 0 : 1
                let inserted = current[column] + 1
                let deleted = previous[column + 1] + 1
                let replaced = previous[column] + cost
                current.append(min(inserted, deleted, replaced))
            }
            previous = current
        }
        return previous[right.count]
    }
}
