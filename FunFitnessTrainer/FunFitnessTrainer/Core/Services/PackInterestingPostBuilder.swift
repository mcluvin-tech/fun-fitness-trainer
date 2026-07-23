import Foundation

/// Turns raw pack meal logs into share-worthy weekly headlines (absurd counts, volume flexes, junk streaks).
enum PackInterestingPostBuilder {
    private struct ParsedMeal {
        let foodKey: String
        let foodName: String
        let quantity: Int
        let unit: FoodUnit
    }

    private enum FoodUnit: Hashable {
        case count(singular: String, plural: String)
        case cups
        case slices
        case servings
        case tbsp
    }

    private struct AggregateKey: Hashable {
        let memberName: String
        let isYou: Bool
        let foodKey: String
        let unit: FoodUnit
    }

    private struct Aggregate {
        let key: AggregateKey
        let foodName: String
        var totalQuantity: Int
        var totalCalories: Int
        var totalProtein: Int
        var latestLoggedAt: Date
    }

    static func startOfWeek(_ date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// Prefer interesting weekly headlines; fall back to raw meal logs until the pack tab is fully built out.
    static func presentableFeed(from rawMeals: [PackFeedEntry], pinnedStats: [PackFeedEntry] = []) -> [PackFeedEntry] {
        let weekStart = startOfWeek()
        let thisWeek = rawMeals.filter { !$0.isInterestingStat && $0.loggedAt >= weekStart }
        let interesting = buildInterestingPosts(from: thisWeek)
        let combined = (interesting + pinnedStats.filter(\.isInterestingStat))
            .sorted { $0.loggedAt > $1.loggedAt }

        if !combined.isEmpty {
            return combined
        }

        // MVP fallback: show individual logs when nothing crosses the interesting bar yet.
        return rawMeals.sorted { $0.loggedAt > $1.loggedAt }
    }

    static func buildInterestingPosts(from entries: [PackFeedEntry]) -> [PackFeedEntry] {
        var aggregates: [AggregateKey: Aggregate] = [:]

        for entry in entries {
            guard let parsed = parse(entry.mealName) else { continue }
            let key = AggregateKey(
                memberName: entry.memberName,
                isYou: entry.isYou,
                foodKey: parsed.foodKey,
                unit: parsed.unit
            )

            if var existing = aggregates[key] {
                existing.totalQuantity += parsed.quantity
                existing.totalCalories += entry.calories
                existing.totalProtein += entry.proteinG
                existing.latestLoggedAt = max(existing.latestLoggedAt, entry.loggedAt)
                aggregates[key] = existing
            } else {
                aggregates[key] = Aggregate(
                    key: key,
                    foodName: parsed.foodName,
                    totalQuantity: parsed.quantity,
                    totalCalories: entry.calories,
                    totalProtein: entry.proteinG,
                    latestLoggedAt: entry.loggedAt
                )
            }
        }

        return aggregates.values
            .filter(isInteresting)
            .map(makeFeedEntry(from:))
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    // MARK: - Parsing

    private static func parse(_ mealName: String) -> ParsedMeal? {
        let lower = mealName.lowercased()
        let quantity = max(FoodItemNaming.parseQuantity(in: mealName), 1)

        if lower.contains("cup") {
            let food = normalizedFoodName(from: lower, stripVolumeWords: true)
            guard !food.key.isEmpty else { return nil }
            return ParsedMeal(foodKey: food.key, foodName: food.display, quantity: quantity, unit: .cups)
        }

        if lower.contains("tbsp") || lower.contains("tablespoon") {
            let food = normalizedFoodName(from: lower, stripVolumeWords: true)
            guard !food.key.isEmpty else { return nil }
            return ParsedMeal(foodKey: food.key, foodName: food.display, quantity: quantity, unit: .tbsp)
        }

        if lower.contains("egg") {
            return ParsedMeal(foodKey: "eggs", foodName: "eggs", quantity: quantity, unit: .count(singular: "egg", plural: "eggs"))
        }

        if lower.contains("slice") && (lower.contains("toast") || lower.contains("bread")) {
            return ParsedMeal(
                foodKey: "toast",
                foodName: "toast",
                quantity: quantity,
                unit: .slices
            )
        }

        if lower.contains("big mac") || lower.contains("bigmac") {
            return ParsedMeal(
                foodKey: "big mac",
                foodName: "Big Mac",
                quantity: quantity,
                unit: .count(singular: "Big Mac", plural: "Big Macs")
            )
        }

        if lower.contains("burger") || lower.contains("mcdonald") || lower.contains("pizza") {
            let food = normalizedFoodName(from: lower, stripVolumeWords: false)
            return ParsedMeal(
                foodKey: food.key.isEmpty ? "junk food" : food.key,
                foodName: food.display.isEmpty ? "junk food" : food.display,
                quantity: quantity,
                unit: .count(singular: food.display.isEmpty ? "junk meal" : food.display, plural: "\(food.display.isEmpty ? "junk meals" : food.display)s")
            )
        }

        if lower.contains("ground beef") {
            return ParsedMeal(
                foodKey: "ground beef",
                foodName: "ground beef",
                quantity: quantity,
                unit: .cups
            )
        }

        if lower.contains("chicken") || lower.contains("salmon") || lower.contains("fish") {
            let food = normalizedFoodName(from: lower, stripVolumeWords: false)
            return ParsedMeal(
                foodKey: food.key,
                foodName: food.display,
                quantity: quantity,
                unit: .servings
            )
        }

        if lower.contains("yogurt") || lower.contains("greek") {
            return ParsedMeal(foodKey: "greek yogurt", foodName: "Greek yogurt", quantity: quantity, unit: .cups)
        }

        if lower.contains("rice") {
            return ParsedMeal(foodKey: "rice", foodName: "rice", quantity: quantity, unit: .cups)
        }

        let generic = normalizedFoodName(from: lower, stripVolumeWords: false)
        guard !generic.key.isEmpty else { return nil }
        return ParsedMeal(
            foodKey: generic.key,
            foodName: generic.display,
            quantity: quantity,
            unit: .count(singular: generic.display, plural: "\(generic.display)s")
        )
    }

    private static func normalizedFoodName(from lower: String, stripVolumeWords: Bool) -> (key: String, display: String) {
        var text = lower
        let stripTokens = [
            "logged ", "had ", "ate ", "just ", "about ", "around ", "roughly ",
            "cups of ", "cup of ", "tablespoons of ", "tablespoon of ", "tbsp of ", "tbsp ",
            "servings of ", "serving of ", "slices of ", "slice of ",
        ]
        for token in stripTokens {
            text = text.replacingOccurrences(of: token, with: "")
        }
        if stripVolumeWords {
            text = text.replacingOccurrences(of: #"\b\d+(?:\.\d+)?\b"#, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\b(one|two|three|four|five|six|seven|eight|nine|ten|a|an)\b"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ("", "") }

        let display = FoodItemNaming.displayTitle(for: text)
        let key = display.lowercased()
        return (key, display.lowercased())
    }

    // MARK: - Interesting thresholds

    private static func isInteresting(_ aggregate: Aggregate) -> Bool {
        let qty = aggregate.totalQuantity

        switch aggregate.key.unit {
        case .cups:
            if aggregate.key.foodKey == "ground beef" { return qty >= 3 }
            return qty >= 4
        case .tbsp:
            return qty >= 6
        case .slices:
            return qty >= 4
        case .servings:
            return qty >= 5
        case .count(let singular, _):
            if aggregate.key.foodKey == "eggs" { return qty >= 5 }
            if aggregate.key.foodKey == "big mac" { return qty >= 2 }
            if aggregate.key.foodKey.contains("junk") || singular.contains("burger") || singular.contains("mac") {
                return qty >= 2
            }
            return qty >= 5
        }
    }

    // MARK: - Headlines

    private static func makeFeedEntry(from aggregate: Aggregate) -> PackFeedEntry {
        PackFeedEntry(
            memberName: aggregate.key.memberName,
            mealName: headline(for: aggregate),
            calories: aggregate.totalCalories,
            proteinG: aggregate.totalProtein,
            loggedAt: aggregate.latestLoggedAt,
            isYou: aggregate.key.isYou,
            isInterestingStat: true
        )
    }

    private static func headline(for aggregate: Aggregate) -> String {
        let who = aggregate.key.memberName
        let count = spokenCount(aggregate.totalQuantity)

        switch aggregate.key.unit {
        case .cups:
            let cupWord = aggregate.totalQuantity == 1 ? "cup" : "cups"
            return "\(who) logged \(count) \(cupWord) of \(aggregate.foodName) this week"
        case .tbsp:
            let tbspWord = aggregate.totalQuantity == 1 ? "tablespoon" : "tablespoons"
            return "\(who) logged \(count) \(tbspWord) of \(aggregate.foodName) this week"
        case .slices:
            let sliceWord = aggregate.totalQuantity == 1 ? "slice" : "slices"
            return "\(who) had \(count) \(sliceWord) of \(aggregate.foodName) this week"
        case .servings:
            let servingWord = aggregate.totalQuantity == 1 ? "serving" : "servings"
            return "\(who) logged \(count) \(servingWord) of \(aggregate.foodName) this week"
        case .count(let singular, let plural):
            let noun = aggregate.totalQuantity == 1 ? singular : plural
            return "\(who) had \(count) \(noun) this week"
        }
    }

    private static func spokenCount(_ value: Int) -> String {
        let words = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        ]
        if value >= 0, value < words.count {
            return words[value]
        }
        return "\(value)"
    }
}
