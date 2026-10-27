import Foundation

/// Local branded / USDA-style reference foods.
/// Values are **per reference quantity**. Callers scale with `FoodQuantity.multiplier`.
enum StapleNutritionDatabase {
    struct Entry: Equatable {
        let key: String
        let aliases: [String]
        let displayName: String
        let brand: String?
        let displayUnit: String
        let referenceQuantity: Double
        let referenceUnit: FoodUnit
        let preparation: MacroTrackingEngine.PreparationState
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let source: MacroTrackingEngine.NutritionSource
        let confidence: MacroTrackingEngine.NutritionConfidence
        let barcode: String?
        let notes: String
        /// Used only when the user/vision said "chicken" with no weight. Never 1 count / 100g.
        var defaultLoggedPortion: FoodPortion? = nil
        /// Food-specific. A cup of spinach is not a cup of rice.
        var gramsPerCup: Double? = nil
        var gramsPerTablespoon: Double? = nil

        var perReference: MacroTotals {
            MacroTotals(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        }

        var isBranded: Bool { brand != nil }
    }

    struct ScaledResult {
        let entry: Entry
        let portion: FoodPortion
        let multiplier: Double
        let totals: MacroTotals
        let inferredPreparation: Bool
        let usedDefaultPortion: Bool
        let assumptions: [String]
    }

    // MARK: - Branded

    static let davesKillerBread21WholeGrains = Entry(
        key: "daves_21_whole_grains",
        aliases: ["dave's", "daves", "dave’s killer", "21 whole grains"],
        displayName: "Dave's Killer Bread",
        brand: "Dave's Killer Bread",
        displayUnit: "slice",
        referenceQuantity: 1,
        referenceUnit: .slice,
        preparation: .unknown,
        calories: 110,
        proteinG: 5,
        carbsG: 22,
        fatG: 1.5,
        source: .manufacturer,
        confidence: .high,
        barcode: "013764005043",
        notes: "Dave's Killer Bread label · 21 Whole Grains & Seeds (1 slice / 45g)"
    )

    static let davesThinSliced = Entry(
        key: "daves_thin_sliced",
        aliases: ["dave's thin", "daves thin", "thin-sliced", "thin sliced"],
        displayName: "Dave's Thin Sliced",
        brand: "Dave's Killer Bread",
        displayUnit: "slice",
        referenceQuantity: 1,
        referenceUnit: .slice,
        preparation: .unknown,
        calories: 60,
        proteinG: 3,
        carbsG: 11,
        fatG: 1,
        source: .manufacturer,
        confidence: .high,
        barcode: nil,
        notes: "Dave's Killer Bread Thin-Sliced label"
    )

    // MARK: - USDA-style staples

    static let largeEgg = Entry(
        key: "large_egg",
        aliases: ["egg", "eggs"],
        displayName: "Large egg",
        brand: nil,
        displayUnit: "egg",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .unknown,
        calories: 72,
        proteinG: 6.3,
        carbsG: 0.4,
        fatG: 4.8,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA large egg"
    )

    static let genericToastSlice = Entry(
        key: "generic_toast",
        aliases: ["toast", "bread", "sandwich bread"],
        displayName: "Toast",
        brand: nil,
        displayUnit: "slice",
        referenceQuantity: 1,
        referenceUnit: .slice,
        preparation: .unknown,
        calories: 80,
        proteinG: 3,
        carbsG: 15,
        fatG: 1,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "Generic sandwich bread slice"
    )

    static let sourdoughSlice = Entry(
        key: "sourdough_slice",
        aliases: ["sourdough"],
        displayName: "Sourdough",
        brand: nil,
        displayUnit: "slice",
        referenceQuantity: 1,
        referenceUnit: .slice,
        preparation: .unknown,
        calories: 90,
        proteinG: 4,
        carbsG: 17,
        fatG: 1,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA-style sourdough slice (~50g)"
    )

    /// Cooked skinless chicken breast — USDA per 100 g. 6 oz ≈ 280 kcal / 53 g protein.
    static let chickenBreastCooked = Entry(
        key: "chicken_breast_cooked",
        aliases: ["chicken breast", "chicken"],
        displayName: "Cooked chicken breast",
        brand: nil,
        displayUnit: "g",
        referenceQuantity: 100,
        referenceUnit: .gram,
        preparation: .cooked,
        calories: 165,
        proteinG: 31,
        carbsG: 0,
        fatG: 3.6,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA chicken breast, cooked, skinless, per 100g",
        defaultLoggedPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .cooked),
        gramsPerCup: 140
    )

    static let chickenBreastRaw = Entry(
        key: "chicken_breast_raw",
        aliases: ["chicken breast", "chicken"],
        displayName: "Raw chicken breast",
        brand: nil,
        displayUnit: "g",
        referenceQuantity: 100,
        referenceUnit: .gram,
        preparation: .raw,
        calories: 120,
        proteinG: 22.5,
        carbsG: 0,
        fatG: 2.6,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA chicken breast, raw, skinless, per 100g",
        defaultLoggedPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .raw)
    )

    static let groundBeefCooked = Entry(
        key: "ground_beef_cooked",
        aliases: ["ground beef", "hamburger meat"],
        displayName: "Cooked ground beef",
        brand: nil,
        displayUnit: "g",
        referenceQuantity: 100,
        referenceUnit: .gram,
        preparation: .cooked,
        calories: 250,
        proteinG: 26,
        carbsG: 0,
        fatG: 15,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA 80/20 ground beef, cooked, per 100g",
        defaultLoggedPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .cooked)
    )

    static let groundBeefCookedCup = Entry(
        key: "ground_beef_cooked_cup",
        aliases: ["ground beef"],
        displayName: "Cooked ground beef",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .cooked,
        calories: 339,
        proteinG: 31,
        carbsG: 0,
        fatG: 23,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA ground beef, cooked — 1 cup crumbled"
    )

    static let salmonCooked = Entry(
        key: "salmon_cooked",
        aliases: ["salmon", "fish"],
        displayName: "Cooked salmon",
        brand: nil,
        displayUnit: "g",
        referenceQuantity: 100,
        referenceUnit: .gram,
        preparation: .cooked,
        calories: 206,
        proteinG: 22,
        carbsG: 0,
        fatG: 12,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA Atlantic salmon, cooked, per 100g",
        defaultLoggedPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .cooked)
    )

    static let appleMedium = Entry(
        key: "apple_medium",
        aliases: ["apple", "apples"],
        displayName: "Apple",
        brand: nil,
        displayUnit: "medium",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .raw,
        calories: 95,
        proteinG: 0.5,
        carbsG: 25,
        fatG: 0.3,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA apple, medium (182g)"
    )

    static let clementine = Entry(
        key: "clementine",
        aliases: ["clementine", "clementines", "cutie", "cuties"],
        displayName: "Clementine",
        brand: nil,
        displayUnit: "fruit",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .raw,
        calories: 35,
        proteinG: 0.6,
        carbsG: 9,
        fatG: 0.1,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA clementine, 1 fruit (74g)"
    )

    static let bananaMedium = Entry(
        key: "banana_medium",
        aliases: ["banana", "bananas"],
        displayName: "Banana",
        brand: nil,
        displayUnit: "medium",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .raw,
        calories: 105,
        proteinG: 1.3,
        carbsG: 27,
        fatG: 0.4,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA banana, medium (118g)"
    )

    static let butterTbsp = Entry(
        key: "butter_tbsp",
        aliases: ["butter"],
        displayName: "Butter",
        brand: nil,
        displayUnit: "tbsp",
        referenceQuantity: 1,
        referenceUnit: .tablespoon,
        preparation: .unknown,
        calories: 102,
        proteinG: 0.1,
        carbsG: 0,
        fatG: 11.5,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA butter, 1 tbsp (14g)",
        defaultLoggedPortion: FoodPortion(amount: 1, unit: .tablespoon, preparation: .unknown),
        gramsPerTablespoon: 14.2
    )

    static let oliveOilTbsp = Entry(
        key: "olive_oil_tbsp",
        aliases: ["olive oil", "oil"],
        displayName: "Olive oil",
        brand: nil,
        displayUnit: "tbsp",
        referenceQuantity: 1,
        referenceUnit: .tablespoon,
        preparation: .unknown,
        calories: 119,
        proteinG: 0,
        carbsG: 0,
        fatG: 13.5,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA olive oil, 1 tbsp",
        defaultLoggedPortion: FoodPortion(amount: 1, unit: .tablespoon, preparation: .unknown),
        gramsPerTablespoon: 13.5
    )

    /// USDA honey, per 100 g. A tablespoon is 21 g: about 64 kcal, 0 g protein, 17 g carbs, 0 g fat.
    static let honey = per100g(
        key: "honey",
        aliases: ["honey", "raw honey"],
        name: "Honey",
        calories: 304,
        proteinG: 0.3,
        carbsG: 82.4,
        fatG: 0,
        notes: "USDA honey per 100 g. 1 tablespoon is 21 g (about 64 kcal). 1 teaspoon is 7 g (about 21 kcal).",
        gramsPerTablespoon: 21,
        defaultPortion: FoodPortion(amount: 1, unit: .tablespoon, preparation: .unknown)
    )

    static let whiteSugar = per100g(
        key: "sugar",
        aliases: ["sugar", "white sugar", "granulated sugar", "brown sugar"],
        name: "Sugar",
        calories: 387,
        proteinG: 0,
        carbsG: 100,
        fatG: 0,
        notes: "USDA granulated sugar per 100 g. 1 tablespoon is about 12.6 g.",
        gramsPerTablespoon: 12.6,
        defaultPortion: FoodPortion(amount: 1, unit: .tablespoon, preparation: .unknown)
    )

    static let mapleSyrup = per100g(
        key: "maple_syrup",
        aliases: ["maple syrup"],
        name: "Maple syrup",
        calories: 260,
        proteinG: 0,
        carbsG: 67,
        fatG: 0,
        notes: "USDA maple syrup per 100 g. 1 tablespoon is about 20 g.",
        gramsPerTablespoon: 20,
        defaultPortion: FoodPortion(amount: 1, unit: .tablespoon, preparation: .unknown)
    )

    static let peanutButterTbsp = Entry(
        key: "peanut_butter_tbsp",
        aliases: ["peanut butter"],
        displayName: "Peanut butter",
        brand: nil,
        displayUnit: "tbsp",
        referenceQuantity: 1,
        referenceUnit: .tablespoon,
        preparation: .unknown,
        calories: 94,
        proteinG: 4,
        carbsG: 3.5,
        fatG: 8,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA peanut butter, 1 tbsp",
        gramsPerTablespoon: 16
    )

    static let almondButterTbsp = Entry(
        key: "almond_butter_tbsp",
        aliases: ["almond butter"],
        displayName: "Almond butter",
        brand: nil,
        displayUnit: "tbsp",
        referenceQuantity: 1,
        referenceUnit: .tablespoon,
        preparation: .unknown,
        calories: 98,
        proteinG: 3.4,
        carbsG: 3,
        fatG: 8.9,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA almond butter, 1 tbsp",
        gramsPerTablespoon: 16
    )

    static let avocadoHalf = Entry(
        key: "avocado",
        aliases: ["avocado"],
        displayName: "Avocado",
        brand: nil,
        displayUnit: "half",
        referenceQuantity: 0.5,
        referenceUnit: .count,
        preparation: .raw,
        calories: 120,
        proteinG: 1.5,
        carbsG: 6,
        fatG: 11,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA avocado, 1/2 fruit — default when amount unspecified"
    )

    static let cheddarSlice = Entry(
        key: "cheddar_slice",
        aliases: ["cheese", "cheddar"],
        displayName: "Cheddar",
        brand: nil,
        displayUnit: "slice",
        referenceQuantity: 1,
        referenceUnit: .slice,
        preparation: .unknown,
        calories: 90,
        proteinG: 5,
        carbsG: 0.5,
        fatG: 7,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA cheddar, 1 slice (~21g)"
    )

    static let carrotMedium = Entry(
        key: "carrot_medium",
        aliases: ["carrot", "carrots"],
        displayName: "Carrot",
        brand: nil,
        displayUnit: "medium",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .raw,
        calories: 25,
        proteinG: 0.6,
        carbsG: 6,
        fatG: 0.1,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA carrot, medium (61g)"
    )

    static let carrotCup = Entry(
        key: "carrot_cup",
        aliases: ["carrot", "carrots"],
        displayName: "Carrots",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .raw,
        calories: 52,
        proteinG: 1.2,
        carbsG: 12.3,
        fatG: 0.3,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA carrots, raw, 1 cup chopped (128g)"
    )

    static let greekYogurtCup = Entry(
        key: "greek_yogurt_cup",
        aliases: ["greek yogurt", "yogurt", "greek"],
        displayName: "Greek yogurt",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 100,
        proteinG: 17,
        carbsG: 6,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "Nonfat Greek yogurt, 1 cup (about 170 g)",
        gramsPerCup: 170
    )

    static let riceCookedCup = Entry(
        key: "rice_cooked_cup",
        aliases: ["rice"],
        displayName: "Cooked rice",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .cooked,
        calories: 205,
        proteinG: 4.3,
        carbsG: 45,
        fatG: 0.4,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA white rice, cooked, 1 cup",
        defaultLoggedPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let potatoChipsOz = Entry(
        key: "potato_chips_oz",
        aliases: ["chips", "chip", "potato chips"],
        displayName: "Potato chips",
        brand: nil,
        displayUnit: "oz",
        referenceQuantity: 1,
        referenceUnit: .ounce,
        preparation: .unknown,
        calories: 150,
        proteinG: 2,
        carbsG: 15,
        fatG: 10,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA potato chips, ~1 oz serving",
        defaultLoggedPortion: FoodPortion(amount: 1, unit: .ounce, preparation: .unknown)
    )

    static let bigMac = Entry(
        key: "big_mac",
        aliases: ["big mac", "bigmac"],
        displayName: "Big Mac",
        brand: "McDonald's",
        displayUnit: "sandwich",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .cooked,
        calories: 590,
        proteinG: 25,
        carbsG: 46,
        fatG: 34,
        source: .restaurant,
        confidence: .high,
        barcode: nil,
        notes: "McDonald's published Big Mac nutrition"
    )

    /// Hostess Twinkies label, one cake (38.5g). Not a protein food.
    static let hostessTwinkie = Entry(
        key: "hostess_twinkie",
        aliases: ["twinkie", "twinkies"],
        displayName: "Twinkie",
        brand: "Hostess",
        displayUnit: "cake",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .unknown,
        calories: 140,
        proteinG: 1,
        carbsG: 23,
        fatG: 4.5,
        source: .manufacturer,
        confidence: .high,
        barcode: nil,
        notes: "Hostess Twinkies label · 1 cake (38.5g)"
    )

    static let coconutMilkCup = Entry(
        key: "coconut_milk_carton",
        aliases: ["coconut milk", "coconutmilk"],
        displayName: "Coconut milk",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 50,
        proteinG: 0.5,
        carbsG: 2,
        fatG: 4.5,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Carton beverage coconut milk, 8 fl oz — not canned cream"
    )

    static let almondMilkCup = Entry(
        key: "almond_milk",
        aliases: ["almond milk"],
        displayName: "Almond milk",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 40,
        proteinG: 1,
        carbsG: 2,
        fatG: 3,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Unsweetened-style carton almond milk, 8 fl oz"
    )

    static let oatMilkCup = Entry(
        key: "oat_milk",
        aliases: ["oat milk"],
        displayName: "Oat milk",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 120,
        proteinG: 3,
        carbsG: 16,
        fatG: 5,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Carton oat milk, 8 fl oz"
    )

    static let soyMilkCup = Entry(
        key: "soy_milk",
        aliases: ["soy milk", "soymilk"],
        displayName: "Soy milk",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 80,
        proteinG: 7,
        carbsG: 4,
        fatG: 4,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Carton soy milk, 8 fl oz"
    )

    static let fairlifeChocolateCup = Entry(
        key: "fairlife_chocolate",
        aliases: ["fairlife", "fair life", "core power"],
        displayName: "Fairlife Chocolate Milk",
        brand: "Fairlife",
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 140,
        proteinG: 13,
        carbsG: 13,
        fatG: 4.5,
        source: .manufacturer,
        confidence: .high,
        barcode: nil,
        notes: "Fairlife ultra-filtered chocolate milk, ~1 cup"
    )

    /// 11.5 fl oz Fairlife Nutrition Plan / Core Power Elite-style shake.
    /// Bare "Fairlife" stays the chocolate milk above — only these longer names hit the shake.
    static let fairlifeProteinShake = Entry(
        key: "fairlife_protein_shake",
        aliases: [
            "fairlife protein shake",
            "fairlife shake",
            "fairlife nutrition plan",
            "fair life protein shake",
            "fair life shake",
            "core power shake",
            "core power elite",
        ],
        displayName: "Fairlife Protein Shake",
        brand: "Fairlife",
        displayUnit: "bottle",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .unknown,
        calories: 150,
        proteinG: 30,
        carbsG: 4,
        fatG: 2.5,
        source: .manufacturer,
        confidence: .high,
        barcode: nil,
        notes: "Fairlife Nutrition Plan chocolate shake, 11.5 fl oz bottle. 150 kcal, 30 g protein."
    )

    /// Published Chipotle chicken bowl: chicken, cilantro-lime white rice, black beans,
    /// fajita vegetables, tomato salsa, cheese, sour cream.
    static let chipotleChickenBowl = Entry(
        key: "chipotle_chicken_bowl",
        aliases: ["chipotle chicken bowl", "chipotle bowl", "chipotle chicken"],
        displayName: "Chipotle Chicken Bowl",
        brand: "Chipotle",
        displayUnit: "bowl",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .unknown,
        calories: 785,
        proteinG: 52,
        carbsG: 73,
        fatG: 30,
        source: .restaurant,
        confidence: .high,
        barcode: nil,
        notes: "Chipotle chicken bowl with rice, black beans, fajita vegetables, tomato salsa, cheese, and sour cream."
    )

    static let nesquikCup = Entry(
        key: "nesquik_chocolate_milk",
        aliases: ["nesquik", "chocolate milk"],
        displayName: "Chocolate milk",
        brand: nil,
        displayUnit: "cup",
        referenceQuantity: 1,
        referenceUnit: .cup,
        preparation: .unknown,
        calories: 140,
        proteinG: 5,
        carbsG: 24,
        fatG: 2.5,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Nesquik-style RTD chocolate milk, 8 fl oz"
    )

    static let ice = Entry(
        key: "ice",
        aliases: ["ice cube", "ice cubes"],
        displayName: "Ice",
        brand: nil,
        displayUnit: "serving",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .unknown,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        source: .usda,
        confidence: .high,
        barcode: nil,
        notes: "Plain ice is water. ~0 calories."
    )

    /// 12 fl oz IPA. A US pint lands near 260 kcal — not a lager, and not a protein drink.
    static let ipaBeer = Entry(
        key: "ipa_beer",
        aliases: ["ipa", "india pale ale"],
        displayName: "IPA",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 195,
        proteinG: 2,
        carbsG: 18,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "Typical IPA, 12 fl oz. Alcohol calories are included (7 kcal/g). A pint is about 260 kcal."
    )

    /// 12 fl oz blonde ale. A US pint is about 210 kcal, 2 g protein, 18 g carbs.
    static let blondeBeer = Entry(
        key: "blonde_beer",
        aliases: ["blonde ale", "blond ale", "blonde beer", "blond beer"],
        displayName: "Blonde beer",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 160,
        proteinG: 1.2,
        carbsG: 13.5,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "Typical blonde ale, 12 fl oz. Alcohol calories are included. A pint is about 210 kcal, not a coffee drink."
    )

    /// USDA regular beer, 12 fl oz. A US pint is 16 fl oz (~204 kcal, ~2 g protein, ~17 g carbs).
    static let regularBeer = Entry(
        key: "regular_beer",
        aliases: ["beer", "lager", "ipa", "pale ale", "pilsner", "stout"],
        displayName: "Beer",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 153,
        proteinG: 1.64,
        carbsG: 12.64,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA regular beer, 12 fl oz. A pint is 16 fl oz."
    )

    static let lightBeer = Entry(
        key: "light_beer",
        aliases: ["light beer", "lite beer"],
        displayName: "Light beer",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 103,
        proteinG: 0.85,
        carbsG: 5.81,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA light beer, 12 fl oz"
    )

    static let nonAlcoholicBeer = Entry(
        key: "na_beer",
        aliases: ["non-alcoholic beer", "nonalcoholic beer", "na beer"],
        displayName: "Non-alcoholic beer",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 70,
        proteinG: 1,
        carbsG: 12,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "Typical non-alcoholic beer, 12 fl oz"
    )

    static let wineGlass = Entry(
        key: "wine",
        aliases: ["wine", "champagne", "prosecco"],
        displayName: "Wine",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 5,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 125,
        proteinG: 0.1,
        carbsG: 3.8,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA table wine, 5 fl oz glass"
    )

    static let sodaCan = Entry(
        key: "soda",
        aliases: ["soda", "cola", "coke", "pepsi", "sprite", "root beer", "ginger ale"],
        displayName: "Soda",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 140,
        proteinG: 0,
        carbsG: 39,
        fatG: 0,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Regular cola, 12 fl oz"
    )

    static let dietSodaCan = Entry(
        key: "diet_soda",
        aliases: ["diet soda", "diet coke", "coke zero", "diet cola", "zero sugar"],
        displayName: "Diet soda",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 12,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        source: .manufacturer,
        confidence: .medium,
        barcode: nil,
        notes: "Diet or zero-sugar soda, 12 fl oz"
    )

    static let spiritsShot = Entry(
        key: "spirits",
        aliases: ["whiskey", "whisky", "vodka", "tequila", "rum", "gin", "bourbon"],
        displayName: "Liquor",
        brand: nil,
        displayUnit: "fl oz",
        referenceQuantity: 1.5,
        referenceUnit: .fluidOunce,
        preparation: .unknown,
        calories: 97,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        source: .usda,
        confidence: .medium,
        barcode: nil,
        notes: "USDA 80-proof distilled spirit, 1.5 fl oz shot"
    )

    static let water = Entry(
        key: "water",
        aliases: ["tap water", "sparkling water", "seltzer"],
        displayName: "Water",
        brand: nil,
        displayUnit: "serving",
        referenceQuantity: 1,
        referenceUnit: .count,
        preparation: .unknown,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        source: .usda,
        confidence: .high,
        barcode: nil,
        notes: "Plain water. ~0 calories."
    )

    static let spinachRaw = per100g(
        key: "spinach_raw",
        aliases: ["spinach"],
        name: "Spinach",
        calories: 23, proteinG: 2.9, carbsG: 3.6, fatG: 0.4,
        notes: "USDA raw spinach per 100 g. 1 cup is about 30 g, not a cup of rice.",
        preparation: .raw,
        gramsPerCup: 30,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .raw)
    )

    static let spinachCooked = per100g(
        key: "spinach_cooked",
        aliases: ["cooked spinach", "sautéed spinach", "sauteed spinach"],
        name: "Cooked spinach",
        calories: 23, proteinG: 3, carbsG: 3.8, fatG: 0.3,
        notes: "USDA cooked spinach per 100 g. 1 cup cooked is about 180 g.",
        preparation: .cooked,
        gramsPerCup: 180,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let broccoliCooked = per100g(
        key: "broccoli_cooked",
        aliases: ["broccoli"],
        name: "Broccoli",
        calories: 35, proteinG: 2.4, carbsG: 7.2, fatG: 0.4,
        notes: "USDA cooked broccoli per 100 g. 1 cup is about 156 g.",
        preparation: .cooked,
        gramsPerCup: 156,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let potatoBaked = per100g(
        key: "potato_baked",
        aliases: ["potato", "baked potato", "potatoes"],
        name: "Potato",
        calories: 93, proteinG: 2.5, carbsG: 21, fatG: 0.1,
        notes: "USDA baked potato per 100 g. One medium potato is about 173 g.",
        preparation: .cooked,
        gramsPerCup: 150,
        defaultPortion: FoodPortion(amount: 173, unit: .gram, preparation: .cooked)
    )

    static let sweetPotatoBaked = per100g(
        key: "sweet_potato",
        aliases: ["sweet potato", "sweet potatoes"],
        name: "Sweet potato",
        calories: 90, proteinG: 2, carbsG: 21, fatG: 0.2,
        notes: "USDA baked sweet potato per 100 g. One medium is about 114 g.",
        preparation: .cooked,
        defaultPortion: FoodPortion(amount: 114, unit: .gram, preparation: .cooked)
    )

    static let pastaCooked = per100g(
        key: "pasta_cooked",
        aliases: ["pasta", "spaghetti", "noodles", "macaroni"],
        name: "Cooked pasta",
        calories: 157, proteinG: 5.8, carbsG: 31, fatG: 0.9,
        notes: "USDA cooked pasta per 100 g. 1 cup is about 140 g.",
        preparation: .cooked,
        gramsPerCup: 140,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let oatmealCooked = per100g(
        key: "oatmeal_cooked",
        aliases: ["oatmeal", "oats", "porridge"],
        name: "Oatmeal",
        calories: 71, proteinG: 2.5, carbsG: 12, fatG: 1.5,
        notes: "USDA cooked oatmeal per 100 g. 1 cup is about 234 g.",
        preparation: .cooked,
        gramsPerCup: 234,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let wholeMilk = per100g(
        key: "whole_milk",
        aliases: ["whole milk", "milk"],
        name: "Whole milk",
        calories: 61, proteinG: 3.2, carbsG: 4.8, fatG: 3.3,
        notes: "USDA whole milk per 100 g. 1 cup is about 244 g. Not a pint of beer.",
        gramsPerCup: 244,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .unknown)
    )

    static let skimMilk = per100g(
        key: "skim_milk",
        aliases: ["skim milk", "nonfat milk", "fat free milk"],
        name: "Skim milk",
        calories: 34, proteinG: 3.4, carbsG: 5, fatG: 0.1,
        notes: "USDA skim milk per 100 g. 1 cup is about 245 g.",
        gramsPerCup: 245,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .unknown)
    )

    static let orangeJuice = per100g(
        key: "orange_juice",
        aliases: ["orange juice", "oj"],
        name: "Orange juice",
        calories: 45, proteinG: 0.7, carbsG: 10.4, fatG: 0.2,
        notes: "USDA orange juice per 100 g. 1 cup is about 248 g.",
        gramsPerCup: 248,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .unknown)
    )

    static let sirloinCooked = per100g(
        key: "sirloin_cooked",
        aliases: ["steak", "sirloin", "ribeye", "filet"],
        name: "Steak",
        calories: 183, proteinG: 27, carbsG: 0, fatG: 8,
        notes: "USDA cooked sirloin per 100 g. Unspecified steak uses 6 oz.",
        preparation: .cooked,
        defaultPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .cooked)
    )

    static let turkeyBreastCooked = per100g(
        key: "turkey_breast_cooked",
        aliases: ["turkey breast", "turkey"],
        name: "Turkey breast",
        calories: 135, proteinG: 30, carbsG: 0, fatG: 0.7,
        notes: "USDA cooked turkey breast per 100 g. Unspecified portion uses 6 oz.",
        preparation: .cooked,
        defaultPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .cooked)
    )

    static let shrimpCooked = per100g(
        key: "shrimp_cooked",
        aliases: ["shrimp", "prawns"],
        name: "Shrimp",
        calories: 99, proteinG: 24, carbsG: 0.2, fatG: 0.3,
        notes: "USDA cooked shrimp per 100 g. Unspecified portion uses 6 oz.",
        preparation: .cooked,
        defaultPortion: FoodPortion(amount: 6, unit: .ounce, preparation: .cooked)
    )

    static let tunaCanned = per100g(
        key: "tuna_canned",
        aliases: ["tuna"],
        name: "Tuna",
        calories: 106, proteinG: 23, carbsG: 0, fatG: 1,
        notes: "Light tuna in water, drained, per 100 g (about 60 kcal and 13 g protein per 2 oz). A serving is 2 oz (56 g). A can is the drained fish from a typical 5 oz can, about 4 oz, which is two servings. Stated ounces, such as \"5 oz\", scale by weight instead.",
        defaultPortion: FoodPortion(amount: 2, unit: .ounce, preparation: .unknown)
    )

    static let greenBeansCooked = per100g(
        key: "green_beans",
        aliases: ["green beans"],
        name: "Green beans",
        calories: 35, proteinG: 1.9, carbsG: 7.9, fatG: 0.3,
        notes: "USDA cooked green beans per 100 g. 1 cup is about 125 g. Not black beans.",
        preparation: .cooked,
        gramsPerCup: 125,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let blackBeansCooked = per100g(
        key: "black_beans",
        aliases: ["black beans", "beans"],
        name: "Beans",
        calories: 132, proteinG: 8.9, carbsG: 24, fatG: 0.5,
        notes: "USDA cooked black beans per 100 g. 1 cup is about 172 g.",
        preparation: .cooked,
        gramsPerCup: 172,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .cooked)
    )

    static let salsa = per100g(
        key: "salsa",
        aliases: ["salsa"],
        name: "Salsa",
        calories: 36, proteinG: 1.5, carbsG: 7, fatG: 0.2,
        notes: "USDA salsa per 100 g. 1 tablespoon is about 16 g, not a tablespoon of oil.",
        gramsPerTablespoon: 16,
        defaultPortion: FoodPortion(amount: 2, unit: .tablespoon, preparation: .unknown)
    )

    static let cottageCheese = per100g(
        key: "cottage_cheese",
        aliases: ["cottage cheese"],
        name: "Cottage cheese",
        calories: 72, proteinG: 12.4, carbsG: 2.7, fatG: 1,
        notes: "USDA low-fat cottage cheese per 100 g. 1 cup is about 226 g.",
        gramsPerCup: 226,
        defaultPortion: FoodPortion(amount: 1, unit: .cup, preparation: .unknown)
    )

    /// Ordered most-specific first so "Dave's thin" wins over generic bread.
    static let allEntries: [Entry] = [
        davesThinSliced,
        davesKillerBread21WholeGrains,
        hostessTwinkie,
        bigMac,
        chipotleChickenBowl,
        fairlifeProteinShake,
        fairlifeChocolateCup,
        nesquikCup,
        coconutMilkCup,
        almondMilkCup,
        oatMilkCup,
        soyMilkCup,
        ice,
        water,
        lightBeer,
        nonAlcoholicBeer,
        ipaBeer,
        blondeBeer,
        regularBeer,
        wineGlass,
        dietSodaCan,
        sodaCan,
        spiritsShot,
        spinachCooked,
        spinachRaw,
        broccoliCooked,
        sweetPotatoBaked,
        potatoBaked,
        pastaCooked,
        oatmealCooked,
        skimMilk,
        wholeMilk,
        orangeJuice,
        sirloinCooked,
        turkeyBreastCooked,
        shrimpCooked,
        tunaCanned,
        greenBeansCooked,
        blackBeansCooked,
        salsa,
        cottageCheese,
        sourdoughSlice,
        largeEgg,
        honey,
        whiteSugar,
        mapleSyrup,
        peanutButterTbsp,
        almondButterTbsp,
        butterTbsp,
        oliveOilTbsp,
        avocadoHalf,
        cheddarSlice,
        appleMedium,
        clementine,
        bananaMedium,
        carrotCup,
        carrotMedium,
        chickenBreastCooked,
        chickenBreastRaw,
        groundBeefCookedCup,
        groundBeefCooked,
        salmonCooked,
        greekYogurtCup,
        riceCookedCup,
        potatoChipsOz,
        genericToastSlice,
    ]

    // MARK: - Matching / scaling

    /// Resolve a per-unit staple from a food name / utterance.
    static func match(in raw: String) -> Entry? {
        scale(for: raw)?.entry
    }

    /// Gram weight of a stated tablespoon, teaspoon, cup, or ounce for a known food.
    /// A bare count ("honey" with no measure) returns nil so the food's own default serving is used.
    static func householdGrams(in text: String) -> Double? {
        let portion = FoodQuantity.parse(from: text)
        guard !portion.unit.isCountable else { return nil }
        guard let entry = bestEntry(for: text.lowercased(), portion: portion) else { return nil }
        return gramsConsumed(entry: entry, portion: portion)
    }

    static func scale(for raw: String) -> ScaledResult? {
        let lower = raw.lowercased()
        let portion = FoodQuantity.parse(from: raw)
        guard let entry = bestEntry(for: lower, portion: portion) else { return nil }

        var assumptions: [String] = [entry.notes]
        var usedPortion = portion
        var inferredPrep = false
        var usedDefaultPortion = false

        if entry.preparation != .unknown, portion.preparation == .unknown {
            usedPortion.preparation = entry.preparation
            inferredPrep = true
            assumptions.append("Assumed \(entry.preparation.rawValue) weight. Raw and cooked are not interchangeable.")
        }

        if entry.key == "avocado", portion.unit == .count, portion.amount == 1, !lower.contains("half") {
            // Default 1 avocado → whole fruit = 2 × half reference.
            let totals = entry.perReference.scaled(by: 2)
            return ScaledResult(
                entry: entry,
                portion: usedPortion,
                multiplier: 2,
                totals: totals,
                inferredPreparation: inferredPrep,
                usedDefaultPortion: true,
                assumptions: assumptions + ["Assumed 1 whole avocado (2 halves)."]
            )
        }

        // Countable "1 serving" / bare "chicken" against a 100g reference used to scale 1/100.
        if let assumed = assumedPortionIfUnspecified(consumed: usedPortion, entry: entry, text: lower) {
            usedPortion = assumed.portion
            usedDefaultPortion = true
            assumptions.append(assumed.assumption)
        }

        // Unspecified chicken ounces: people usually mean cooked; flag uncertainty.
        if entry.key.hasPrefix("chicken"), portion.preparation == .unknown {
            inferredPrep = true
            if !assumptions.contains(where: { $0.lowercased().contains("cooked") }) {
                assumptions.append("Preparation not specified. Used cooked nutrition. Say raw or cooked for a tighter match.")
            }
        }

        let factor = foodSpecificFactor(entry: entry, portion: usedPortion)
        let totals = entry.perReference.scaled(by: factor)
        let explicitMass = usedPortion.unit.isMass && !usedDefaultPortion
        let (score, reason) = confidenceScore(entry: entry, usedDefaultPortion: usedDefaultPortion, explicitMass: explicitMass)
        assumptions.append("confidence_score: \(score). \(reason)")
        return ScaledResult(
            entry: entry,
            portion: usedPortion,
            multiplier: factor,
            totals: totals,
            inferredPreparation: inferredPrep,
            usedDefaultPortion: usedDefaultPortion,
            assumptions: assumptions
        )
    }

    /// Cup and tablespoon weights belong to the food. 1 cup spinach ≠ 1 cup rice.
    /// Fluid ounces of milk must not be treated as a count of 100 g servings.
    private static func foodSpecificFactor(entry: Entry, portion: FoodPortion) -> Double {
        if let consumedGrams = gramsConsumed(entry: entry, portion: portion),
           let referenceGrams = gramsInOneReferenceUnit(entry),
           referenceGrams > 0 {
            let units = consumedGrams / referenceGrams
            return MacroTrackingEngine.multiplier(consumed: units, reference: entry.referenceQuantity)
        }
        return FoodQuantity.multiplier(
            consumed: portion,
            referenceQuantity: entry.referenceQuantity,
            referenceUnit: entry.referenceUnit
        )
    }

    /// Weight of what the user said, using this food's own cup/tablespoon weight when we have one.
    private static func gramsConsumed(entry: Entry, portion: FoodPortion) -> Double? {
        if let grams = portion.unit.toGrams(portion.amount) {
            return grams
        }
        guard portion.unit.isVolume, let ml = portion.unit.toMilliliters(portion.amount) else {
            return nil
        }
        if portion.unit == .fluidOunce, let perCup = entry.gramsPerCup, perCup > 0 {
            // 8 fl oz is one US cup, even though a metric cup is 240 ml.
            return perCup * (portion.amount / 8)
        }
        if let perCup = entry.gramsPerCup, perCup > 0 {
            return perCup * (ml / FoodUnit.mlPerCup)
        }
        if let perTablespoon = entry.gramsPerTablespoon, perTablespoon > 0,
           portion.unit == .tablespoon || portion.unit == .teaspoon {
            return perTablespoon * (ml / FoodUnit.mlPerTablespoon)
        }
        if looksLikeLiquid(entry) {
            return ml
        }
        return nil
    }

    private static func gramsInOneReferenceUnit(_ entry: Entry) -> Double? {
        switch entry.referenceUnit {
        case .gram:
            return 1
        case .ounce:
            return FoodUnit.gramsPerOunce
        case .cup:
            return entry.gramsPerCup
        case .tablespoon:
            return entry.gramsPerTablespoon ?? (looksLikeLiquid(entry) ? FoodUnit.mlPerTablespoon : nil)
        case .teaspoon:
            return (entry.gramsPerTablespoon ?? FoodUnit.mlPerTablespoon) / 3
        case .fluidOunce:
            return looksLikeLiquid(entry) ? FoodUnit.mlPerFluidOunce : nil
        case .milliliter:
            return 1
        default:
            return nil
        }
    }

    private static func looksLikeLiquid(_ entry: Entry) -> Bool {
        let haystack = (entry.key + " " + entry.displayName + " " + entry.aliases.joined(separator: " ")).lowercased()
        return haystack.contains("milk") || haystack.contains("juice") || haystack.contains("beer")
            || haystack.contains("wine") || haystack.contains("soda") || haystack.contains("water")
    }

    private static func confidenceScore(
        entry: Entry,
        usedDefaultPortion: Bool,
        explicitMass: Bool
    ) -> (Int, String) {
        if entry.source.isExact {
            return (98, "Verified label or restaurant nutrition.")
        }
        if explicitMass {
            return (93, "USDA per 100 g scaled by the stated weight for this food.")
        }
        if usedDefaultPortion {
            return (82, "Standard serving for this food. No scale weight was given.")
        }
        return (88, "This food's own reference, scaled to the stated portion.")
    }

    private static func per100g(
        key: String,
        aliases: [String],
        name: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        notes: String,
        preparation: MacroTrackingEngine.PreparationState = .unknown,
        gramsPerCup: Double? = nil,
        gramsPerTablespoon: Double? = nil,
        defaultPortion: FoodPortion? = nil
    ) -> Entry {
        Entry(
            key: key,
            aliases: aliases,
            displayName: name,
            brand: nil,
            displayUnit: defaultPortion?.unit.displayName.isEmpty == false ? defaultPortion!.unit.displayName : "g",
            referenceQuantity: 100,
            referenceUnit: .gram,
            preparation: preparation,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            source: .usda,
            confidence: .medium,
            barcode: nil,
            notes: notes,
            defaultLoggedPortion: defaultPortion,
            gramsPerCup: gramsPerCup,
            gramsPerTablespoon: gramsPerTablespoon
        )
    }

    /// Bare "chicken" parses as 1 count. Never divide that count by a 100g reference.
    private static func assumedPortionIfUnspecified(
        consumed: FoodPortion,
        entry: Entry,
        text: String
    ) -> (portion: FoodPortion, assumption: String)? {
        guard consumed.unit.isCountable else { return nil }

        // "can" is not "canned". A stated weight ("5 oz") is not countable, so it never comes through here.
        if entry.key == "tuna_canned", mentionsWholeCan(text) {
            let cans = max(consumed.amount, 1)
            let portion = FoodPortion(
                amount: 4 * cans,
                unit: .ounce,
                preparation: consumed.preparation
            )
            return (
                portion,
                "A can of tuna is the drained fish from a typical 5 oz can, about 4 oz (two 2 oz label servings). A serving stays 2 oz."
            )
        }

        let fallback: FoodPortion
        if let listed = entry.defaultLoggedPortion {
            fallback = listed
        } else if entry.referenceUnit.isMass || (entry.referenceUnit.isVolume && consumed.unit != entry.referenceUnit) {
            fallback = FoodPortion(
                amount: entry.referenceQuantity,
                unit: entry.referenceUnit,
                preparation: entry.preparation
            )
        } else {
            return nil
        }

        let plates = max(consumed.amount, 0.05)
        let portion = FoodPortion(
            amount: fallback.amount * plates,
            unit: fallback.unit,
            preparation: consumed.preparation == .unknown ? fallback.preparation : consumed.preparation
        )
        return (
            portion,
            "Assumed \(FoodQuantity.describe(portion)) of \(entry.displayName.lowercased()). A weight/volume was not specified (not 1 count per \(Int(entry.referenceQuantity))\(entry.referenceUnit.displayName.isEmpty ? " unit" : entry.referenceUnit.displayName))."
        )
    }

    /// Quantity from the label ("2 Slices Dave's Toast" → 2) times per-unit macros.
    static func scaledMacros(forName name: String) -> (MacroTotals, Entry, Int)? {
        guard let scaled = scale(for: name) else { return nil }
        let qty = max(Int(scaled.portion.amount.rounded()), 1)
        return (scaled.totals, scaled.entry, qty)
    }

    private static func bestEntry(for lower: String, portion: FoodPortion) -> Entry? {
        let haystack = lower

        if haystack.contains("dave"), haystack.contains("thin") {
            return davesThinSliced
        }
        if haystack.contains("dave") {
            return davesKillerBread21WholeGrains
        }
        if looksLikePlainIce(haystack) {
            return ice
        }
        if looksLikePlainWater(haystack) {
            return water
        }
        if let drink = drinkEntry(for: haystack) {
            return drink
        }

        if matchesToken(haystack, "carrot") || haystack.contains("carrots") {
            return portion.unit == .cup ? carrotCup : carrotMedium
        }
        if haystack.contains("ground beef") {
            return portion.unit == .cup ? groundBeefCookedCup : groundBeefCooked
        }
        if haystack.contains("chicken"), !haystack.contains("chipotle") {
            if portion.preparation == .raw { return chickenBreastRaw }
            return chickenBreastCooked
        }
        if haystack.contains("salmon") || (matchesToken(haystack, "fish") && !haystack.contains("shellfish")) {
            return salmonCooked
        }

        // Longer / more specific aliases first among remaining entries.
        let ranked = allEntries.sorted { $0.aliases.map(\.count).max() ?? 0 > $1.aliases.map(\.count).max() ?? 0 }
        for entry in ranked {
            if entry.key.hasPrefix("chicken") || entry.key.hasPrefix("ground_beef") { continue }
            if entry.key.hasPrefix("carrot") { continue }
            if entry.key == "generic_toast", haystack.contains("dave") || haystack.contains("sourdough") {
                continue
            }
            if entry.key == "nesquik_chocolate_milk", haystack.contains("fairlife") || haystack.contains("coconut")
                || haystack.contains("almond milk") || haystack.contains("oat milk") {
                continue
            }
            if entry.key == "black_beans", haystack.contains("jelly") || haystack.contains("green bean") {
                continue
            }
            if entry.key == "whole_milk" || entry.key == "skim_milk" {
                if haystack.contains("almond") || haystack.contains("oat") || haystack.contains("soy")
                    || haystack.contains("coconut") || haystack.contains("chocolate") || haystack.contains("fairlife") {
                    continue
                }
            }
            if entry.key == "spinach_raw", haystack.contains("cooked") || haystack.contains("sauté") || haystack.contains("saute") {
                continue
            }
            if entry.key == "potato_baked", haystack.contains("sweet potato") || haystack.contains("chip") {
                continue
            }
            if entry.key == "honey" {
                if haystack.contains("mustard") || haystack.contains("bunches") { continue }
            }
            if entry.key == "sugar" {
                if haystack.contains("sugar-free") || haystack.contains("sugar free") || haystack.contains("zero sugar") {
                    continue
                }
            }
            if entry.key == "olive_oil_tbsp", haystack.contains("olive oil") {
                return entry
            }
            if entry.key == "olive_oil_tbsp", haystack.contains("oil"), !haystack.contains("olive") {
                // Bare "oil" — only if it's clearly cooking oil, not "oil-based".
                if matchesToken(haystack, "oil") { return entry }
                continue
            }
            for alias in entry.aliases {
                if alias.contains(" ") {
                    if haystack.contains(alias) { return entry }
                } else if matchesToken(haystack, alias) {
                    return entry
                }
            }
        }
        return nil
    }

    /// Alcohol and soda. Root beer and ginger ale are soda, not beer. Coffee stays out of this list.
    private static func drinkEntry(for text: String) -> Entry? {
        if text.contains("espresso") || text.contains("coffee") || text.contains("latte")
            || text.contains("cappuccino") || text.contains("frappuccino") {
            return nil
        }
        let sodaName = text.contains("soda") || text.contains("cola") || matchesToken(text, "coke")
            || text.contains("pepsi") || text.contains("sprite") || text.contains("root beer")
            || text.contains("ginger ale") || text.contains("ginger beer")
        if sodaName, text.contains("diet") || text.contains("zero sugar") || text.contains("coke zero") {
            return dietSodaCan
        }
        if sodaName { return sodaCan }
        if text.contains("non-alcoholic") || text.contains("nonalcoholic")
            || text.contains("na beer") || text.contains("n/a beer") || text.contains("zero alcohol") {
            if matchesToken(text, "beer") { return nonAlcoholicBeer }
        }
        if text.contains("light beer") || text.contains("lite beer") || text.contains("bud light")
            || text.contains("coors light") || text.contains("miller lite") || text.contains("michelob ultra") {
            return lightBeer
        }
        if text.contains("ipa") { return ipaBeer }
        if (text.contains("blonde") || text.contains("blond"))
            && (matchesToken(text, "beer") || matchesToken(text, "ale")) {
            return blondeBeer
        }
        if matchesToken(text, "beer") || text.contains("lager") || text.contains("pilsner")
            || matchesToken(text, "ale") || text.contains("stout") {
            return regularBeer
        }
        if matchesToken(text, "wine") || text.contains("champagne") || text.contains("prosecco") {
            return wineGlass
        }
        if text.contains("whiskey") || text.contains("whisky") || text.contains("vodka")
            || text.contains("tequila") || matchesToken(text, "rum") || matchesToken(text, "gin")
            || text.contains("bourbon") {
            return spiritsShot
        }
        return nil
    }

    /// "a can of tuna" / "two cans", not the adjective "canned".
    private static func mentionsWholeCan(_ text: String) -> Bool {
        text.range(of: #"\bcans?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Ice" / "ice cubes" — not ice cream, iced coffee, or Italian ice.
    static func looksLikePlainIce(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("ice cream") || lower.contains("ice-cream") || lower.contains("icecream") {
            return false
        }
        if lower.contains("iced") || lower.contains("italian ice") || lower.contains("icee") {
            return false
        }
        return matchesToken(lower, "ice") || lower.contains("ice cube")
    }

    static func looksLikePlainWater(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("coconut") || lower.contains("tonic") || lower.contains("vitamin")
            || lower.contains("melon") || lower.contains("watermelon") {
            return false
        }
        return matchesToken(lower, "water") || lower.contains("seltzer")
    }

    private static func matchesToken(_ text: String, _ token: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b",
            options: .caseInsensitive
        ) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
    }
}
