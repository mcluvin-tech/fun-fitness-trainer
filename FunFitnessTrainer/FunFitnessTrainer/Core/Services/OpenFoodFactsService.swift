import Foundation

struct BarcodeProductResult: Equatable {
    let barcode: String
    let name: String
    let brand: String?
    let servingDescription: String?
    let imageURL: URL?
    /// Macros for one label serving.
    let perServing: MacroTotals
    /// Serving amount in milliliters when known (helps scale drinks).
    let servingQuantityMl: Double?
}

/// UPC-A and the EAN-13 form AVFoundation returns for the same grocery barcode.
enum BarcodeNormalization {
    static func normalizedBarcode(_ rawValue: String) -> String {
        let digits = rawValue.filter(\.isNumber)
        if digits.count == 13, digits.hasPrefix("0") {
            return String(digits.dropFirst())
        }
        return digits
    }

    /// Raw digits, the UPC-A form, and the EAN-13 form with a leading zero. Duplicates removed.
    static func lookupCandidates(for rawValue: String) -> [String] {
        let rawDigits = rawValue.filter(\.isNumber)
        let normalized = normalizedBarcode(rawValue)
        var candidates: [String] = []
        func add(_ value: String) {
            guard !value.isEmpty, !candidates.contains(value) else { return }
            candidates.append(value)
        }
        add(rawDigits)
        add(normalized)
        if normalized.count == 12 {
            add("0" + normalized)
        }
        return candidates
    }
}

enum OpenFoodFactsService {
    private static let productURL = "https://world.openfoodfacts.org/api/v2/product"
    private static let searchURL = "https://world.openfoodfacts.org/cgi/search.pl"
    /// Voice/text search stays short so chat stays snappy.
    private static let searchTimeout: TimeInterval = 2.5
    /// Direct barcode lookups tolerate slower cellular.
    private static let barcodeLookupTimeout: TimeInterval = 12
    private static let searchCacheLimit = 40
    private static var searchCache: [String: BarcodeProductResult] = [:]
    private static var searchCacheOrder: [String] = []

    static func lookup(barcode: String, timeout: TimeInterval = barcodeLookupTimeout) async throws -> BarcodeProductResult {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw APIError.serverMessage("Enter a valid barcode.")
        }

        let candidates = BarcodeNormalization.lookupCandidates(for: code)
        guard !candidates.isEmpty else {
            throw APIError.serverMessage("Enter a valid barcode.")
        }

        var sawNetworkError = false
        for variant in candidates {
            do {
                return try await lookupExact(code: variant, timeout: timeout)
            } catch is CancellationError {
                throw CancellationError()
            } catch is URLError {
                sawNetworkError = true
            } catch {
                continue
            }
        }
        for variant in candidates {
            if let usda = try? await USDAFoodDataService.lookup(barcode: variant) {
                return usda
            }
        }
        let recognized = BarcodeNormalization.normalizedBarcode(code)
        if sawNetworkError {
            throw APIError.serverMessage("Barcode \(recognized) was read. The food database didn't respond.")
        }
        throw APIError.serverMessage(
            "Barcode \(recognized) was read, but that product isn't in the database. Scan again."
        )
    }

    private static func lookupExact(code: String, timeout: TimeInterval) async throws -> BarcodeProductResult {
        var components = URLComponents(string: "\(productURL)/\(code)")!
        components.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments,serving_size,serving_quantity,image_url,status"
            ),
        ]

        guard let url = components.url else { throw APIError.invalidResponse }

        let data = try await fetch(url: url, timeout: timeout)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let status = json["status"] as? Int,
            status == 1,
            let product = json["product"] as? [String: Any],
            let parsed = parseProduct(product, barcode: code)
        else {
            throw APIError.serverMessage("Product not found in Open Food Facts. Try a photo or manual log.")
        }
        return parsed
    }

    /// Full-text search by product name (voice / typed logging). Returns best label match or nil.
    static func searchBestMatch(query: String) async throws -> BarcodeProductResult? {
        let terms = normalizedSearchTerms(query)
        guard !terms.isEmpty else { return nil }

        if let cached = cachedMatch(for: terms) { return cached }

        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "5"),
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments,serving_size,serving_quantity,image_url"
            ),
        ]

        guard let url = components.url else { return nil }

        let data = try await fetch(url: url, timeout: searchTimeout)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = json["products"] as? [[String: Any]]
        else {
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "D",
                location: "OpenFoodFactsService.searchBestMatch",
                message: "OFF response had no products array",
                data: ["terms": terms]
            )
            // #endregion
            return nil
        }

        let queryTokens = tokenSet(terms)
        var best: (result: BarcodeProductResult, score: Double)?

        for product in products {
            guard let code = product["code"] as? String, !code.isEmpty,
                  let parsed = parseProduct(product, barcode: code),
                  parsed.perServing.calories > 0 else { continue }

            let score = matchScore(queryTokens: queryTokens, product: product)
            guard score >= 0.35 else { continue }

            if best == nil || score > best!.score {
                best = (parsed, score)
            }
        }

        if let match = best?.result {
            storeCache(terms: terms, result: match)
        }
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "D",
            location: "OpenFoodFactsService.searchBestMatch",
            message: best == nil ? "no OFF product cleared score" : "OFF product selected",
            data: [
                "terms": terms,
                "productCount": products.count,
                "bestScore": best?.score ?? 0,
                "bestName": best?.result.name ?? "",
                "bestCalories": best?.result.perServing.calories ?? 0,
                "bestProtein": best?.result.perServing.proteinG ?? 0,
            ]
        )
        // #endregion
        return best?.result
    }

    private static func cachedMatch(for terms: String) -> BarcodeProductResult? {
        let key = terms.lowercased()
        return searchCache[key]
    }

    private static func storeCache(terms: String, result: BarcodeProductResult) {
        let key = terms.lowercased()
        if searchCache[key] == nil {
            searchCacheOrder.append(key)
        }
        searchCache[key] = result
        while searchCacheOrder.count > searchCacheLimit {
            let evict = searchCacheOrder.removeFirst()
            searchCache.removeValue(forKey: evict)
        }
    }

    // MARK: - Parsing

    static func parseProduct(_ product: [String: Any], barcode: String) -> BarcodeProductResult? {
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let servingQuantity = doubleValue(product["serving_quantity"]) ?? 100
        let perServing = macros(from: nutriments, servingQuantityGrams: servingQuantity)

        guard perServing.calories >= 0 else { return nil }

        let productName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = (product["brands"] as? String)?
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = displayName(productName: productName, brand: brand)
        let imageURL = (product["image_url"] as? String).flatMap(URL.init(string:))
        let servingDescription = (product["serving_size"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let servingMl = inferServingMl(
            servingDescription: servingDescription,
            servingQuantity: servingQuantity,
            nutriments: nutriments
        )

        return BarcodeProductResult(
            barcode: barcode,
            name: name,
            brand: brand,
            servingDescription: servingDescription,
            imageURL: imageURL,
            perServing: perServing,
            servingQuantityMl: servingMl
        )
    }

    private static func normalizedSearchTerms(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ref = FoodItemNaming.extractFoodReference(from: text) {
            text = ref
        } else if let logged = FoodItemNaming.loggedFoodDescription(from: text) {
            text = logged
        }
        text = FoodItemNaming.sanitizeSegment(text)
        let lower = text.lowercased()
        let strip = [
            "i had ", "i ate ", "i drank ", "just had ", "just ate ", "just drank ",
            "log my ", "log ", "please ",
        ]
        for prefix in strip where lower.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
        )
    }

    private static func matchScore(queryTokens: Set<String>, product: [String: Any]) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        let name = (product["product_name"] as? String ?? "").lowercased()
        let brands = (product["brands"] as? String ?? "").lowercased()
        let haystack = tokenSet("\(name) \(brands)")
        let hits = queryTokens.filter { token in
            haystack.contains(token) || name.contains(token) || brands.contains(token)
        }.count
        var score = Double(hits) / Double(queryTokens.count)

        if name.contains("powder") || name.contains("mix") { score *= 0.45 }
        if queryTokens.contains("milk") || queryTokens.contains("drink") || queryTokens.contains("shake") {
            if name.contains("milk") || name.contains("shake") || name.contains("drink") { score += 0.12 }
        }
        if queryTokens.contains("nesquik"), brands.contains("nesquik") { score += 0.15 }

        return min(score, 1)
    }

    private static func inferServingMl(
        servingDescription: String?,
        servingQuantity: Double,
        nutriments: [String: Any]
    ) -> Double? {
        if let per = nutriments["nutrition_data_per"] as? String, per.lowercased().contains("100ml") {
            return servingQuantity > 0 ? servingQuantity : nil
        }
        if let desc = servingDescription?.lowercased() {
            if desc.contains("ml"), let ml = parseLeadingNumber(in: desc) { return ml }
            if desc.contains("fl oz") || desc.contains("oz"), let oz = parseLeadingNumber(in: desc) {
                return oz * 29.5735
            }
        }
        if servingQuantity > 0, servingQuantity < 500 { return servingQuantity }
        return nil
    }

    private static func parseLeadingNumber(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    private static func fetch(url: URL, timeout: TimeInterval = searchTimeout) async throws -> Data {
        var lastError: Error?
        for attempt in 1...2 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                request.setValue("FunFitnessTrainer/1.0 (iOS; macro tracker)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                guard (200...299).contains(http.statusCode) else {
                    throw APIError.httpError(http.statusCode)
                }
                return data
            } catch let error as URLError where [
                .networkConnectionLost, .timedOut, .notConnectedToInternet,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
            ].contains(error.code) {
                lastError = error
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private static func displayName(productName: String?, brand: String?) -> String {
        let cleanName = productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !cleanBrand.isEmpty, !cleanName.isEmpty {
            return "\(cleanBrand), \(cleanName)"
        }
        if !cleanName.isEmpty { return cleanName }
        if !cleanBrand.isEmpty { return cleanBrand }
        return "Packaged food"
    }

    private static func macros(from nutriments: [String: Any], servingQuantityGrams: Double) -> MacroTotals {
        if let serving = servingMacros(from: nutriments) {
            return serving
        }
        return scaledFrom100g(nutriments: nutriments, servingQuantityGrams: servingQuantityGrams)
    }

    private static func servingMacros(from nutriments: [String: Any]) -> MacroTotals? {
        // Only trust explicit per-serving keys — bare "energy-kcal" is often per 100g.
        guard nutriments["energy-kcal_serving"] != nil,
              let calories = doubleValue(nutriments["energy-kcal_serving"]),
              calories >= 0 else { return nil }

        return MacroTotals(
            calories: calories,
            proteinG: nutrient(nutriments, keys: ["proteins_serving"]),
            carbsG: nutrient(nutriments, keys: ["carbohydrates_serving"]),
            fatG: nutrient(nutriments, keys: ["fat_serving"])
        )
    }

    private static func scaledFrom100g(
        nutriments: [String: Any],
        servingQuantityGrams: Double
    ) -> MacroTotals {
        let factor = max(servingQuantityGrams, 1) / 100.0
        let calories = nutrient(nutriments, keys: ["energy-kcal_100g", "energy-kcal"]) * factor

        if calories <= 0 {
            let kj = nutrient(nutriments, keys: ["energy-kj_100g", "energy-kj"]) * factor
            if kj > 0 {
                return MacroTotals(
                    calories: kj / 4.184,
                    proteinG: nutrient(nutriments, keys: ["proteins_100g", "proteins"]) * factor,
                    carbsG: nutrient(nutriments, keys: ["carbohydrates_100g", "carbohydrates"]) * factor,
                    fatG: nutrient(nutriments, keys: ["fat_100g", "fat"]) * factor
                )
            }
        }

        return MacroTotals(
            calories: calories,
            proteinG: nutrient(nutriments, keys: ["proteins_100g", "proteins"]) * factor,
            carbsG: nutrient(nutriments, keys: ["carbohydrates_100g", "carbohydrates"]) * factor,
            fatG: nutrient(nutriments, keys: ["fat_100g", "fat"]) * factor
        )
    }

    private static func nutrient(_ nutriments: [String: Any], keys: [String]) -> Double {
        for key in keys {
            if let value = doubleValue(nutriments[key]), value > 0 {
                return value
            }
        }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let text as String: return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}

struct USDAPortion {
    var modifier: String
    var amount: Double
    var gramWeight: Double
}

struct USDAGenericFood {
    var name: String
    var dataType: String
    /// Nutrients for 100 grams.
    var per100g: MacroTotals
    var grams: Double
    var quantity: Double
    var unit: String
    var portionLabel: String
    var assumedPortion: Bool
}

/// USDA FoodData Central lookup. Barcodes use branded foods; unnamed foods use Foundation / SR Legacy.
enum USDAFoodDataService {
    private static let searchURL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    /// Public demo key. A `USDA_API_KEY` in Secrets.plist replaces it.
    private static let demoKey = "DEMO_KEY"

    static func lookup(barcode: String) async throws -> BarcodeProductResult? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let key = Secrets.value(for: "USDA_API_KEY") ?? demoKey

        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "query", value: digits),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "15"),
            URLQueryItem(name: "api_key", value: key),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("FunFitnessTrainer/1.0 (iOS; macro tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let foods = json["foods"] as? [[String: Any]]
        else { return nil }

        for food in foods {
            let gtin = ((food["gtinUpc"] as? String) ?? "").filter(\.isNumber)
            guard OpenFoodFactsBarcode.sameProduct(gtin, digits) else { continue }
            if let parsed = parse(food, barcode: gtin.isEmpty ? digits : gtin) {
                return parsed
            }
        }
        return nil
    }

    /// Foundation / SR Legacy name search for foods that are not local staples (honey, berries, …).
    /// "raw honey" must not match every SR Legacy row that merely ends in ", raw".
    static func lookupGeneric(query: String) async -> USDAGenericFood? {
        let terms = genericSearchTerms(from: query)
        guard !terms.isEmpty else { return nil }
        let tokens = wordTokens(terms)
        guard !tokens.isEmpty else { return nil }

        guard let foods = await searchFoods(query: terms, dataTypes: "Foundation,SR Legacy", pageSize: 15) else {
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "B",
                location: "USDAFoodDataService.lookupGeneric",
                message: "USDA search failed",
                data: ["terms": terms, "runId": "post-fix"]
            )
            // #endregion
            return nil
        }

        var best: (food: [String: Any], score: Double)?
        for food in foods {
            let description = (food["description"] as? String) ?? ""
            let score = genericMatchScore(description: description, queryTokens: tokens)
            guard score >= 0.85 else { continue }
            if best == nil || score > best!.score {
                best = (food, score)
            }
        }

        guard let match = best else {
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "D",
                location: "USDAFoodDataService.lookupGeneric",
                message: "no USDA description matched the food name",
                data: ["terms": terms, "candidates": foods.count, "runId": "post-fix"]
            )
            // #endregion
            return nil
        }

        let description = ((match.food["description"] as? String) ?? terms)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let per100g = per100gMacros(from: match.food)
        guard per100g.calories > 0 else { return nil }

        var portions: [USDAPortion] = []
        if let id = intValue(match.food["fdcId"]), let detail = await foodDetail(fdcId: id) {
            portions = parsedPortions(from: detail)
        }
        let serving = scaledServing(userQuery: query, portions: portions)
        return USDAGenericFood(
            name: description,
            dataType: (match.food["dataType"] as? String) ?? "USDA",
            per100g: per100g,
            grams: serving.grams,
            quantity: serving.quantity,
            unit: serving.unit,
            portionLabel: serving.label,
            assumedPortion: serving.assumed
        )
    }

    private static func genericSearchTerms(from query: String) -> String {
        let cleaned = FoodItemNaming.sanitizeSegment(query)
        let source = cleaned.isEmpty ? query : cleaned
        let ignored: Set<String> = [
            "raw", "cooked", "uncooked", "grilled", "baked", "roasted", "fried",
            "boiled", "steamed", "fresh", "organic", "plain", "homemade", "leftover",
        ]
        return wordTokens(source)
            .filter { !ignored.contains($0) }
            .joined(separator: " ")
    }

    /// Primary name must be the food itself. "Honey" matches; "Honey Bunches of Oats" and "Abiyuch, raw" do not.
    private static func genericMatchScore(description: String, queryTokens: [String]) -> Double {
        let lower = description.lowercased()
        let primary = lower.split(separator: ",").first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? lower
        let primaryTokens = wordTokens(primary)
        guard queryTokens.allSatisfy({ wholeWord($0, in: primary) }) else { return 0 }
        if primaryTokens == queryTokens { return 1 }
        let extras = primaryTokens.filter { !queryTokens.contains($0) }
        if extras.isEmpty { return 0.95 }
        return max(0, 0.7 - Double(extras.count) * 0.2)
    }

    private static func scaledServing(
        userQuery: String,
        portions: [USDAPortion]
    ) -> (grams: Double, quantity: Double, unit: String, label: String, assumed: Bool) {
        let portion = FoodQuantity.parse(from: userQuery)
        if portion.unit.isMass, let grams = portion.unit.toGrams(portion.amount), grams > 0 {
            let unit = portion.unit.displayName
            return (grams, portion.amount, unit, "\(formatAmount(portion.amount)) \(unit)", false)
        }
        if let hit = matchingPortion(portion, in: portions) {
            let grams = hit.gramWeight * portion.amount / max(hit.amount, 0.01)
            return (grams, portion.amount, portion.unit.displayName, hit.modifier, false)
        }
        if portion.unit.isCountable {
            let preference = [
                "medium", "piece", "serving", "slice", "fruit", "fillet",
                "tbsp", "tablespoon", "tsp", "teaspoon", "packet", "oz", "cup",
            ]
            for key in preference {
                guard let hit = portions.first(where: { $0.modifier.lowercased().contains(key) }) else { continue }
                let grams = hit.gramWeight * max(portion.amount, 1) / max(hit.amount, 0.01)
                let unit = displayUnit(for: key)
                return (grams, max(portion.amount, 1), unit, "\(formatAmount(max(portion.amount, 1))) \(unit)", true)
            }
        }
        let grams = 100 * max(portion.amount, 1)
        return (grams, max(portion.amount, 1), "g", "100 g", true)
    }

    private static func matchingPortion(_ portion: FoodPortion, in portions: [USDAPortion]) -> USDAPortion? {
        let keys: [String]
        switch portion.unit {
        case .tablespoon: keys = ["tbsp", "tablespoon"]
        case .teaspoon: keys = ["tsp", "teaspoon"]
        case .cup: keys = ["cup"]
        case .slice: keys = ["slice"]
        case .ounce: keys = ["oz", "ounce"]
        default: return nil
        }
        return portions.first { item in
            let modifier = item.modifier.lowercased()
            return keys.contains { modifier.contains($0) }
        }
    }

    private static func displayUnit(for key: String) -> String {
        switch key {
        case "tbsp", "tablespoon": return "tbsp"
        case "tsp", "teaspoon": return "tsp"
        case "slice": return "slice"
        case "cup": return "cup"
        case "oz": return "oz"
        default: return "serving"
        }
    }

    private static func formatAmount(_ amount: Double) -> String {
        amount == floor(amount) ? String(Int(amount)) : String(format: "%g", amount)
    }

    private static func searchFoods(query: String, dataTypes: String, pageSize: Int) async -> [[String: Any]]? {
        let key = Secrets.value(for: "USDA_API_KEY") ?? demoKey
        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "dataType", value: dataTypes),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "api_key", value: key),
        ]
        guard let json = await getJSON(components.url) else { return nil }
        return json["foods"] as? [[String: Any]]
    }

    private static func foodDetail(fdcId: Int) async -> [String: Any]? {
        let key = Secrets.value(for: "USDA_API_KEY") ?? demoKey
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcId)")!
        components.queryItems = [URLQueryItem(name: "api_key", value: key)]
        return await getJSON(components.url)
    }

    private static func getJSON(_ url: URL?) async -> [String: Any]? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("FunFitnessTrainer/1.0 (iOS; macro tracker)", forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func parsedPortions(from food: [String: Any]) -> [USDAPortion] {
        let rows = food["foodPortions"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let grams = doubleValue(row["gramWeight"]), grams > 0 else { return nil }
            let modifier = ((row["modifier"] as? String) ?? (row["portionDescription"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = doubleValue(row["amount"]) ?? 1
            return USDAPortion(modifier: modifier, amount: max(amount, 0.01), gramWeight: grams)
        }
    }

    private static func per100gMacros(from food: [String: Any]) -> MacroTotals {
        let nutrients = food["foodNutrients"] as? [[String: Any]] ?? []
        let totals = MacroTotals(
            calories: nutrientAmount(nutrients, ids: [1008], names: ["energy"], energy: true),
            proteinG: nutrientAmount(nutrients, ids: [1003], names: ["protein"]),
            carbsG: nutrientAmount(nutrients, ids: [1005], names: ["carbohydrate"]),
            fatG: nutrientAmount(nutrients, ids: [1004], names: ["total lipid", "fat"])
        )
        let serving = doubleValue(food["servingSize"]) ?? 100
        let unit = ((food["servingSizeUnit"] as? String) ?? "g").lowercased()
        guard unit == "g" || unit == "grm" || unit.isEmpty, serving > 0, abs(serving - 100) > 0.5 else {
            return totals
        }
        return totals.scaled(by: 100 / serving)
    }

    private static func nutrientAmount(
        _ nutrients: [[String: Any]],
        ids: Set<Int>,
        names: [String],
        energy: Bool = false
    ) -> Double {
        var kcal: Double?
        var kilojoules: Double?
        var matched: Double?
        for nutrient in nutrients {
            let id = intValue(nutrient["nutrientId"])
                ?? intValue(nutrient["nutrientNumber"])
                ?? (nutrient["nutrient"] as? [String: Any]).flatMap { intValue($0["id"]) }
            let name = (nutrient["nutrientName"] as? String
                ?? (nutrient["nutrient"] as? [String: Any])?["name"] as? String
                ?? "").lowercased()
            let unit = (nutrient["unitName"] as? String
                ?? (nutrient["nutrient"] as? [String: Any])?["unitName"] as? String
                ?? "").lowercased()
            let matchesID = id.map { ids.contains($0) } ?? false
            let matchesName = names.contains { name.contains($0) }
            guard matchesID || matchesName else { continue }
            if energy, name.contains("from") { continue }
            if !matchesID, name.contains("saturated") || name.contains("trans") { continue }
            guard let value = doubleValue(nutrient["value"]) ?? doubleValue(nutrient["amount"]) else { continue }
            if energy {
                if id == 1008 || unit.contains("kcal") { kcal = value }
                else if unit.contains("kj") { kilojoules = value }
                else if matched == nil { matched = value }
            } else if matched == nil {
                matched = value
            }
        }
        if energy {
            if let kcal, kcal > 0 { return kcal }
            if let kilojoules, kilojoules > 0 { return kilojoules / 4.184 }
        }
        return matched ?? 0
    }

    private static func wordTokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
    }

    private static func wholeWord(_ token: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b",
            options: .caseInsensitive
        ) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as Double: return Int(number)
        case let text as String: return Int(text)
        default: return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let text as String: return Double(text)
        default: return nil
        }
    }

    private static func parse(_ food: [String: Any], barcode: String) -> BarcodeProductResult? {
        let nutrients = food["foodNutrients"] as? [[String: Any]] ?? []
        func amount(_ ids: Set<Int>, names: [String], energy: Bool = false) -> Double {
            for nutrient in nutrients {
                let id = (nutrient["nutrientId"] as? Int)
                    ?? (nutrient["nutrientNumber"] as? String).flatMap(Int.init)
                let name = (nutrient["nutrientName"] as? String ?? "").lowercased()
                let matchesID = id.map { ids.contains($0) } ?? false
                let matchesName = names.contains { name.contains($0) }
                guard matchesID || matchesName else { continue }
                if energy, name.contains("from") { continue }
                if !matchesID, name.contains("saturated") || name.contains("trans") { continue }
                let raw: Double?
                if let value = nutrient["value"] as? Double { raw = value }
                else if let value = nutrient["value"] as? Int { raw = Double(value) }
                else { raw = nil }
                guard var value = raw else { continue }
                let unit = (nutrient["unitName"] as? String ?? "").lowercased()
                if energy, unit.contains("kj") { value /= 4.184 }
                return value
            }
            return 0
        }

        let calories = amount([1008], names: ["energy"], energy: true)
        guard calories > 0 else { return nil }
        let description = (food["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let brand = ((food["brandOwner"] as? String) ?? (food["brandName"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let household = (food["householdServingFullText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let serving = household?.isEmpty == false ? household : nil
        let name: String
        if let brand, !brand.isEmpty, !description.isEmpty, !description.lowercased().contains(brand.lowercased()) {
            name = "\(brand), \(description)"
        } else if !description.isEmpty {
            name = description
        } else if let brand, !brand.isEmpty {
            name = brand
        } else {
            name = "Packaged food"
        }

        return BarcodeProductResult(
            barcode: barcode,
            name: name,
            brand: brand,
            servingDescription: serving,
            imageURL: nil,
            perServing: MacroTotals(
                calories: calories,
                proteinG: amount([1003], names: ["protein"]),
                carbsG: amount([1005], names: ["carbohydrate"]),
                fatG: amount([1004], names: ["total lipid", "fat"])
            ),
            servingQuantityMl: nil
        )
    }
}

enum OpenFoodFactsBarcode {
    static func variants(_ digits: String) -> [String] {
        var values = [digits]
        if digits.count == 12 { values.append("0" + digits) }
        if digits.count == 13, digits.hasPrefix("0") { values.append(String(digits.dropFirst())) }
        if digits.count == 14, digits.hasPrefix("0") { values.append(String(digits.dropFirst())) }
        return values
    }

    static func sameProduct(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.drop { $0 == "0" }
        let right = rhs.drop { $0 == "0" }
        return !left.isEmpty && left == right
    }
}
