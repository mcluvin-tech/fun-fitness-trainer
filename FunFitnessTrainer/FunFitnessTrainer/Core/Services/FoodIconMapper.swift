import Foundation

/// Cartoon badge for a logged food. Emoji only, so it works offline with no extra art.
struct FoodIconBadge: Equatable, Sendable {
    var emoji: String
    var category: FoodIconCategory
}

enum FoodIconCategory: String, Equatable, Sendable {
    case honey
    case vegetable
    case chicken
    case rice
    case egg
    case banana
    case apple
    case bread
    case oats
    case milk
    case coffee
    case protein
    case salad
    case pizza
    case burger
    case fish
    case steak
    case pasta
    case smoothie
    case snack
    case drink
    case dessert
    case plate
}

enum FoodIconMapper {
    /// First matching keyword wins. Specific foods come before broad ones.
    static func badge(for name: String) -> FoodIconBadge {
        let text = name.lowercased()
        for rule in rules where rule.keywords.contains(where: { text.contains($0) }) {
            return FoodIconBadge(emoji: rule.emoji, category: rule.category)
        }
        return FoodIconBadge(emoji: "🍽️", category: .plate)
    }

    private static let rules: [(keywords: [String], emoji: String, category: FoodIconCategory)] = [
        (["honey"], "🍯", .honey),
        (["broccoli", "cauliflower", "spinach", "kale", "asparagus", "zucchini", "cucumber", "carrot", "pepper", "vegetable"], "🥦", .vegetable),
        (["chicken", "turkey", "poultry"], "🍗", .chicken),
        (["rice"], "🍚", .rice),
        (["egg"], "🥚", .egg),
        (["banana"], "🍌", .banana),
        (["apple"], "🍎", .apple),
        (["bread", "toast", "bagel"], "🍞", .bread),
        (["oat", "oatmeal"], "🥣", .oats),
        (["milk", "yogurt"], "🥛", .milk),
        (["coffee", "latte", "espresso"], "☕", .coffee),
        (["protein bite", "protein bar", "quest"], "🍫", .protein),
        (["salad"], "🥗", .salad),
        (["pizza"], "🍕", .pizza),
        (["burger", "big mac"], "🍔", .burger),
        (["fish", "tuna", "salmon", "shrimp"], "🐟", .fish),
        (["steak", "beef", "sirloin"], "🥩", .steak),
        (["pasta", "spaghetti", "noodle"], "🍝", .pasta),
        (["smoothie"], "🥤", .smoothie),
        (["chip", "cookie", "cracker", "snack"], "🍿", .snack),
        (["beer", "wine", "soda", "juice"], "🥤", .drink),
        (["ice cream", "cake", "donut", "doughnut", "twinkie", "candy", "dessert"], "🍰", .dessert),
    ]
}
