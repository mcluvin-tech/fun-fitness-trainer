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

enum OpenFoodFactsService {
    private static let productURL = "https://world.openfoodfacts.org/api/v2/product"
    private static let searchURL = "https://world.openfoodfacts.org/cgi/search.pl"
    private static let requestTimeout: TimeInterval = 2.5
    private static let searchCacheLimit = 40
    private static var searchCache: [String: BarcodeProductResult] = [:]
    private static var searchCacheOrder: [String] = []

    static func lookup(barcode: String) async throws -> BarcodeProductResult {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw APIError.serverMessage("Enter a valid barcode.")
        }

        var components = URLComponents(string: "\(productURL)/\(code)")!
        components.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments,serving_size,serving_quantity,image_url,status"
            ),
        ]

        guard let url = components.url else { throw APIError.invalidResponse }

        let data = try await fetch(url: url)
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

        let data = try await fetch(url: url)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = json["products"] as? [[String: Any]]
        else { return nil }

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

        guard perServing.calories > 0 else { return nil }

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

    private static func fetch(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("FunFitnessTrainer/1.0 (iOS; macro tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
        return data
    }

    private static func displayName(productName: String?, brand: String?) -> String {
        let cleanName = productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !cleanBrand.isEmpty, !cleanName.isEmpty {
            return "\(cleanBrand) — \(cleanName)"
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
        let calories = nutrient(nutriments, keys: ["energy-kcal_serving", "energy-kcal"])
        guard calories > 0 else { return nil }

        return MacroTotals(
            calories: calories,
            proteinG: nutrient(nutriments, keys: ["proteins_serving", "proteins"]),
            carbsG: nutrient(nutriments, keys: ["carbohydrates_serving", "carbohydrates"]),
            fatG: nutrient(nutriments, keys: ["fat_serving", "fat"])
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
