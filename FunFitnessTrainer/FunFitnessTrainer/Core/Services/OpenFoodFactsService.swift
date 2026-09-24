import Foundation

struct BarcodeProductResult: Equatable {
    let barcode: String
    let name: String
    let brand: String?
    let servingDescription: String?
    let imageURL: URL?
    /// Macros for one label serving (or per 100 g when the label has no serving size).
    let perServing: MacroTotals
    /// Serving amount in milliliters when the label is a volume.
    let servingQuantityMl: Double?
    /// False when Open Food Facts has the product but no energy data.
    let nutritionIsComplete: Bool
}

enum OpenFoodFactsService {
    private static let productURL = "https://world.openfoodfacts.org/api/v2/product"
    private static let searchURL = "https://world.openfoodfacts.org/cgi/search.pl"
    /// Name search stays short — it runs beside chat, not on the shutter path.
    private static let searchTimeout: TimeInterval = 4
    /// Barcode lookup is user-visible. 2.5s was dropping real products on slow radios.
    private static let barcodeTimeout: TimeInterval = 10
    private static let cacheLimit = 50
    private static let cacheLock = NSLock()
    private static var searchCache: [String: BarcodeProductResult] = [:]
    private static var searchCacheOrder: [String] = []
    private static var barcodeCache: [String: BarcodeProductResult] = [:]
    private static var barcodeCacheOrder: [String] = []

    // MARK: - Barcode codes

    /// Codes worth requesting, most likely Open Food Facts key first.
    static func lookupCandidates(from raw: String) -> [String] {
        var result: [String] = []

        func add(_ code: String) {
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }

        for seed in digitSeeds(in: raw) {
            switch seed.count {
            case 12:
                let ean = "0" + seed
                if hasValidCheckDigit(ean) { add(ean) }
                if hasValidCheckDigit(seed) { add(seed) }
            case 13:
                if hasValidCheckDigit(seed) { add(seed) }
            case 14:
                if hasValidCheckDigit(seed) { add(seed) }
                let item = String(seed.suffix(13))
                if hasValidCheckDigit(item) { add(item) }
            case 8:
                if hasValidCheckDigit(seed) { add(seed) }
                if let expanded = expandUPCE(seed) {
                    let ean = "0" + expanded
                    if hasValidCheckDigit(ean) { add(ean) }
                    if hasValidCheckDigit(expanded) { add(expanded) }
                }
            default:
                break
            }
        }

        return result
    }

    /// First code a successful scan should hand to lookup.
    static func preferredBarcode(from raw: String) -> String? {
        lookupCandidates(from: raw).first
    }

    /// True when the payload contains a GTIN we can trust on the first read.
    static func isImmediatelyAcceptableBarcode(_ raw: String) -> Bool {
        preferredBarcode(from: raw) != nil
    }

    static func hasValidCheckDigit(_ digits: String) -> Bool {
        guard digits.count == 8 || digits.count == 12 || digits.count == 13 || digits.count == 14 else {
            return false
        }
        guard digits.allSatisfy(\.isNumber), let check = digits.last?.wholeNumberValue else { return false }
        let body = digits.dropLast().compactMap(\.wholeNumberValue)
        guard body.count == digits.count - 1 else { return false }
        var sum = 0
        for (offset, digit) in body.reversed().enumerated() {
            sum += digit * (offset % 2 == 0 ? 3 : 1)
        }
        let expected = (10 - (sum % 10)) % 10
        return expected == check
    }

    /// UPC-E (8 digits, number system 0 or 1) → 12-digit UPC-A, including the check digit.
    static func expandUPCE(_ upce: String) -> String? {
        guard upce.count == 8, upce.allSatisfy(\.isNumber) else { return nil }
        let chars = Array(upce)
        guard chars[0] == "0" || chars[0] == "1" else { return nil }
        let ns = String(chars[0])
        let data = chars[1...6].map(String.init)
        let check = String(chars[7])
        let last = data[5]
        let manufacturer: String
        let product: String
        switch last {
        case "0", "1", "2":
            manufacturer = data[0] + data[1] + last + "00"
            product = "00" + data[2] + data[3] + data[4]
        case "3":
            manufacturer = data[0] + data[1] + data[2] + "00"
            product = "000" + data[3] + data[4]
        case "4":
            manufacturer = data[0] + data[1] + data[2] + data[3] + "0"
            product = "0000" + data[4]
        default:
            manufacturer = data[0] + data[1] + data[2] + data[3] + data[4]
            product = "0000" + last
        }
        let upca = ns + manufacturer + product + check
        guard upca.count == 12, hasValidCheckDigit(upca) else { return nil }
        return upca
    }

    // MARK: - Lookup

    static func lookup(barcode: String) async throws -> BarcodeProductResult {
        let candidates = lookupCandidates(from: barcode)
        guard !candidates.isEmpty else {
            throw APIError.serverMessage("That doesn't look like a product barcode. Try again or type it in.")
        }

        for code in candidates {
            if let cached = cachedBarcode(code) { return cached }
        }

        var lastError: Error = APIError.serverMessage("Product not found in Open Food Facts. Try a photo or manual log.")
        for code in candidates {
            do {
                let parsed = try await fetchProduct(code: code)
                storeBarcode(parsed, aliases: candidates + [parsed.barcode])
                return parsed
            } catch LookupFailure.notFound {
                continue
            } catch {
                lastError = error
                throw error
            }
        }
        throw lastError
    }

    /// Full-text search by product name (voice / typed logging). Returns best label match or nil.
    static func searchBestMatch(query: String, timeout: TimeInterval = searchTimeout) async throws -> BarcodeProductResult? {
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
                value: "code,product_name,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,image_url"
            ),
        ]

        guard let url = components.url else { return nil }

        let data: Data
        do {
            data = try await fetch(url: url, timeout: timeout, retries: 1)
        } catch {
            return nil
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let products = json["products"] as? [[String: Any]]
        else { return nil }

        let queryTokens = tokenSet(terms)
        var best: (result: BarcodeProductResult, score: Double)?

        for product in products {
            guard let code = stringValue(product["code"]), !code.isEmpty,
                  let parsed = parseProduct(product, barcode: code),
                  parsed.nutritionIsComplete,
                  parsed.perServing.calories > 0 else { continue }

            let score = matchScore(queryTokens: queryTokens, product: product)
            guard score >= 0.6 else { continue }

            if best == nil || score > best!.score {
                best = (parsed, score)
            }
        }

        if let match = best?.result {
            storeCache(terms: terms, result: match)
        }
        return best?.result
    }

    // MARK: - Parsing

    static func parseProduct(_ product: [String: Any], barcode: String) -> BarcodeProductResult? {
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let resolved = resolveMacros(nutriments: nutriments, product: product)
        let productName = stringValue(product["product_name"])
        let brand = stringValue(product["brands"])?
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = displayName(productName: productName, brand: brand)
        guard name != "Packaged food" || resolved.sawEnergyKey else { return nil }

        let imageURL = stringValue(product["image_url"]).flatMap(URL.init(string:))
        var servingDescription = stringValue(product["serving_size"])
        if (servingDescription == nil || servingDescription?.isEmpty == true), resolved.assumedPer100g {
            servingDescription = "100 g"
        }

        let servingMl = inferServingMl(
            servingDescription: servingDescription,
            servingQuantity: resolved.servingGrams,
            nutriments: nutriments,
            product: product
        )

        return BarcodeProductResult(
            barcode: barcode,
            name: name,
            brand: brand,
            servingDescription: servingDescription,
            imageURL: imageURL,
            perServing: resolved.macros,
            servingQuantityMl: servingMl,
            nutritionIsComplete: resolved.sawEnergyKey
        )
    }

    // MARK: - Cache

    private static func cachedMatch(for terms: String) -> BarcodeProductResult? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return searchCache[terms.lowercased()]
    }

    private static func storeCache(terms: String, result: BarcodeProductResult) {
        let key = terms.lowercased()
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if searchCache[key] == nil {
            searchCacheOrder.append(key)
        }
        searchCache[key] = result
        while searchCacheOrder.count > cacheLimit {
            let evict = searchCacheOrder.removeFirst()
            searchCache.removeValue(forKey: evict)
        }
    }

    private static func cachedBarcode(_ code: String) -> BarcodeProductResult? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return barcodeCache[code]
    }

    private static func storeBarcode(_ result: BarcodeProductResult, aliases: [String]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        for alias in aliases where !alias.isEmpty {
            if barcodeCache[alias] == nil {
                barcodeCacheOrder.append(alias)
            }
            barcodeCache[alias] = result
        }
        while barcodeCacheOrder.count > cacheLimit {
            let evict = barcodeCacheOrder.removeFirst()
            barcodeCache.removeValue(forKey: evict)
        }
    }

    // MARK: - Search helpers

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
        let name = (stringValue(product["product_name"]) ?? "").lowercased()
        let brands = (stringValue(product["brands"]) ?? "").lowercased()
        let haystack = tokenSet("\(name) \(brands)")
        let hits = queryTokens.filter { token in
            haystack.contains(token) || name.contains(token) || brands.contains(token)
        }.count
        var score = Double(hits) / Double(queryTokens.count)

        let longest = queryTokens.filter { $0.count >= 4 }.max(by: { $0.count < $1.count })
        if let longest, !name.contains(longest), !brands.contains(longest) {
            score *= 0.4
        }
        if (name.contains("powder") || name.contains("mix")), !queryTokens.contains("powder") {
            score *= 0.45
        }
        if queryTokens.contains("milk") || queryTokens.contains("drink") || queryTokens.contains("shake") {
            if name.contains("milk") || name.contains("shake") || name.contains("drink") { score += 0.12 }
        }
        if queryTokens.contains("nesquik"), brands.contains("nesquik") { score += 0.15 }

        return min(score, 1)
    }

    // MARK: - Nutrition

    private struct ResolvedNutrition {
        var macros: MacroTotals
        var servingGrams: Double
        var assumedPer100g: Bool
        var sawEnergyKey: Bool
    }

    /// Per-serving keys stay per serving. Bare `energy-kcal` / `proteins` on Open Food Facts
    /// match the per-100 g values, so they are never treated as a serving on their own.
    private static func resolveMacros(nutriments: [String: Any], product: [String: Any]) -> ResolvedNutrition {
        let serving = servingAmount(product: product)
        let per = (stringValue(nutriments["nutrition_data_per"]) ?? "").lowercased()

        if var partial = partialFromServingKeys(nutriments) {
            fillGaps(&partial, nutriments: nutriments, servingGrams: serving.grams)
            return ResolvedNutrition(
                macros: partial.asTotals,
                servingGrams: serving.grams,
                assumedPer100g: serving.assumed100g,
                sawEnergyKey: true
            )
        }

        if per.contains("serving"), let bare = partialFromBareKeys(nutriments), bare.calories != nil {
            return ResolvedNutrition(
                macros: bare.asTotals,
                servingGrams: serving.grams,
                assumedPer100g: false,
                sawEnergyKey: true
            )
        }

        let scaled = partialFrom100g(nutriments, servingGrams: serving.grams)
        return ResolvedNutrition(
            macros: scaled.asTotals,
            servingGrams: serving.grams,
            assumedPer100g: serving.assumed100g,
            sawEnergyKey: scaled.calories != nil
        )
    }

    private struct PartialMacros {
        var calories: Double?
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?

        var asTotals: MacroTotals {
            MacroTotals(
                calories: calories ?? 0,
                proteinG: proteinG ?? 0,
                carbsG: carbsG ?? 0,
                fatG: fatG ?? 0
            )
        }
    }

    private static func partialFromServingKeys(_ nutriments: [String: Any]) -> PartialMacros? {
        guard let calories = kcal(
            nutriments,
            kcalKeys: ["energy-kcal_serving"],
            kjKeys: ["energy-kj_serving"]
        ) else { return nil }
        return PartialMacros(
            calories: calories,
            proteinG: optionalNutrient(nutriments, keys: ["proteins_serving"]),
            carbsG: optionalNutrient(nutriments, keys: ["carbohydrates_serving"]),
            fatG: optionalNutrient(nutriments, keys: ["fat_serving"])
        )
    }

    private static func partialFromBareKeys(_ nutriments: [String: Any]) -> PartialMacros? {
        guard let calories = kcal(
            nutriments,
            kcalKeys: ["energy-kcal"],
            kjKeys: ["energy-kj"]
        ) else { return nil }
        return PartialMacros(
            calories: calories,
            proteinG: optionalNutrient(nutriments, keys: ["proteins"]),
            carbsG: optionalNutrient(nutriments, keys: ["carbohydrates"]),
            fatG: optionalNutrient(nutriments, keys: ["fat"])
        )
    }

    private static func partialFrom100g(_ nutriments: [String: Any], servingGrams: Double) -> PartialMacros {
        let factor = max(servingGrams, 1) / 100.0
        func scaled(_ keys100: [String], bare: String) -> Double? {
            if let value = optionalNutrient(nutriments, keys: keys100) {
                return value * factor
            }
            let per = (stringValue(nutriments["nutrition_data_per"]) ?? "").lowercased()
            if per.contains("serving") { return nil }
            if let value = optionalNutrient(nutriments, keys: [bare]) {
                return value * factor
            }
            return nil
        }
        let calories = kcal(
            nutriments,
            kcalKeys: ["energy-kcal_100g"],
            kjKeys: ["energy-kj_100g"]
        ).map { $0 * factor } ?? scaled(["energy-kcal_100g"], bare: "energy-kcal")

        return PartialMacros(
            calories: calories,
            proteinG: scaled(["proteins_100g"], bare: "proteins"),
            carbsG: scaled(["carbohydrates_100g"], bare: "carbohydrates"),
            fatG: scaled(["fat_100g"], bare: "fat")
        )
    }

    private static func fillGaps(_ partial: inout PartialMacros, nutriments: [String: Any], servingGrams: Double) {
        let scaled = partialFrom100g(nutriments, servingGrams: servingGrams)
        if partial.proteinG == nil { partial.proteinG = scaled.proteinG }
        if partial.carbsG == nil { partial.carbsG = scaled.carbsG }
        if partial.fatG == nil { partial.fatG = scaled.fatG }
    }

    private static func servingAmount(product: [String: Any]) -> (grams: Double, assumed100g: Bool) {
        let unit = (stringValue(product["serving_quantity_unit"]) ?? "").lowercased()
        if let quantity = doubleValue(product["serving_quantity"]), quantity > 0 {
            return (grams(fromQuantity: quantity, unit: unit), false)
        }
        if let size = stringValue(product["serving_size"]),
           let parsed = grams(fromServingSize: size) {
            return (parsed, false)
        }
        return (100, true)
    }

    private static func grams(fromQuantity quantity: Double, unit: String) -> Double {
        if unit.contains("kg") { return quantity * 1000 }
        if unit == "l" || unit.contains("liter") { return quantity * 1000 }
        if unit == "cl" { return quantity * 10 }
        if unit.contains("ml") { return quantity }
        if unit.contains("fl") && unit.contains("oz") { return quantity * 29.5735 }
        if unit == "oz" || unit.contains("ounce") { return quantity * 28.3495 }
        if unit.contains("lb") { return quantity * 453.592 }
        return quantity
    }

    /// Prefer a parenthetical weight ("1 bar (68 g)") over the leading count.
    private static func grams(fromServingSize text: String) -> Double? {
        let lower = text.lowercased()
        if let grams = firstMatch(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*kg\b"#) { return grams * 1000 }
        if let grams = firstMatch(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*g\b"#) { return grams }
        if let ml = firstMatch(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*ml\b"#) { return ml }
        if let oz = firstMatch(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*fl\s*oz\b"#) { return oz * 29.5735 }
        if let oz = firstMatch(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*oz\b"#) { return oz * 28.3495 }
        return nil
    }

    private static func inferServingMl(
        servingDescription: String?,
        servingQuantity: Double,
        nutriments: [String: Any],
        product: [String: Any]
    ) -> Double? {
        let unit = (stringValue(product["serving_quantity_unit"]) ?? "").lowercased()
        let per = (stringValue(nutriments["nutrition_data_per"]) ?? "").lowercased()
        if per.contains("100ml") || unit.contains("ml") || unit == "l" || unit == "cl" {
            return servingQuantity > 0 ? servingQuantity : nil
        }
        if let desc = servingDescription?.lowercased() {
            if desc.contains("ml"), let ml = parseLeadingNumber(in: desc) { return ml }
            if desc.contains("fl oz") || (desc.contains("oz") && desc.contains("fl")),
               let oz = parseLeadingNumber(in: desc) {
                return oz * 29.5735
            }
        }
        return nil
    }

    private static func kcal(_ nutriments: [String: Any], kcalKeys: [String], kjKeys: [String]) -> Double? {
        if let kcal = optionalNutrient(nutriments, keys: kcalKeys) { return kcal }
        if let kj = optionalNutrient(nutriments, keys: kjKeys) { return kj / 4.184 }
        return nil
    }

    /// First present key, including an explicit 0. Missing keys are nil so we don't
    /// substitute a per-100 g value for a per-serving 0.
    private static func optionalNutrient(_ nutriments: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = doubleValue(nutriments[key]) {
                return value
            }
        }
        return nil
    }

    // MARK: - Network

    private enum LookupFailure: Error {
        case notFound
    }

    private static func fetchProduct(code: String) async throws -> BarcodeProductResult {
        var components = URLComponents(string: "\(productURL)/\(code)")!
        components.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,image_url,status"
            ),
        ]
        guard let url = components.url else { throw APIError.invalidResponse }

        let data = try await fetch(url: url, timeout: barcodeTimeout, retries: 1)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let status = (json["status"] as? NSNumber)?.intValue ?? (json["status"] as? Int) ?? 0
        guard
            status == 1,
            let product = json["product"] as? [String: Any],
            let parsed = parseProduct(product, barcode: code)
        else {
            throw LookupFailure.notFound
        }
        return parsed
    }

    private static func fetch(url: URL, timeout: TimeInterval, retries: Int) async throws -> Data {
        var lastError: Error = APIError.invalidResponse
        for attempt in 0...retries {
            do {
                return try await fetchOnce(url: url, timeout: timeout)
            } catch {
                lastError = error
                guard attempt < retries, isRetryable(error) else { throw error }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError
    }

    private static func fetchOnce(url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("FunFitnessTrainer/1.0 (iOS; macro tracker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
        return data
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if case APIError.httpError(let code) = error {
            return code == 408 || code == 429 || (500...599).contains(code)
        }
        return false
    }

    // MARK: - Strings

    private static func digitSeeds(in raw: String) -> [String] {
        var seeds: [String] = []
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        if digits.count >= 8 && digits.count <= 14 {
            seeds.append(digits)
        }
        var current = ""
        func flush() {
            if (8...14).contains(current.count), !seeds.contains(current) {
                seeds.append(current)
            }
            current = ""
        }
        for character in trimmed {
            if character.isNumber {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return seeds
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
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

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let direct = Double(trimmed) { return direct }
            return parseLeadingNumber(in: trimmed)
        default:
            return nil
        }
    }

    private static func parseLeadingNumber(in text: String) -> Double? {
        firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)"#)
    }

    private static func firstMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}
