import XCTest
@testable import FunFitnessTrainer

/// Typed and spoken brand names resolve to per-serving label values. The catalog is scripted — these tests never hit the network.
final class BrandedFoodLookupTests: XCTestCase {
    private var catalog = ScriptedBrandCatalog()

    override func setUp() {
        super.setUp()
        catalog = ScriptedBrandCatalog(responses: Self.fixtures)
        BrandedFoodResolver.useCatalogForTests(catalog)
    }

    override func tearDown() {
        BrandedFoodResolver.restoreLiveCatalogForTests()
        super.tearDown()
    }

    func testCatalinaCrunchUsesTheCinnamonToastServing() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "Catalina Crunch")
        XCTAssertEqual(meal.calories, 110, accuracy: 1)
        XCTAssertEqual(meal.proteinG, 11, accuracy: 0.5)
        XCTAssertEqual(meal.carbsG, 14, accuracy: 0.5)
        XCTAssertEqual(meal.fatG, 5, accuracy: 0.5)
        XCTAssertTrue(meal.name.lowercased().contains("cinnamon"))
        XCTAssertFalse(meal.name.lowercased().contains("dressing"))
        XCTAssertEqual(catalog.queries, ["catalina crunch"])
        let outcome = await FoodAnalysisService.resolveFoodLog(from: "Catalina Crunch")
        XCTAssertFalse(outcome.needsConfirmation)
        XCTAssertEqual(catalog.queries, ["catalina crunch"], "A repeat of the same food must come from the cache")
    }

    func testMisspelledCatalinaCrunchFindsTheSameCereal() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "catalena crunch")
        XCTAssertEqual(meal.calories, 110, accuracy: 1)
        XCTAssertEqual(meal.proteinG, 11, accuracy: 0.5)
        XCTAssertTrue(meal.name.lowercased().contains("cinnamon"))
        XCTAssertEqual(catalog.queries, ["catalina crunch"])
    }

    func testBowlOfCatalinaCrunchAddsAlmondMilk() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "a bowl of catalina crunch with almond milk")
        let entries = meal.entriesForLogging()
        XCTAssertEqual(entries.count, 2, "Got \(entries.map(\.name))")
        let calories = entries.reduce(0) { $0 + $1.calories }
        let protein = entries.reduce(0) { $0 + $1.proteinG }
        XCTAssertEqual(calories, 150, accuracy: 2)
        XCTAssertEqual(protein, 12, accuracy: 1)
        XCTAssertTrue(entries.contains { $0.name.lowercased().contains("cinnamon") || $0.name.lowercased().contains("catalina") })
        XCTAssertTrue(entries.contains { $0.name.lowercased().contains("almond") })
        XCTAssertEqual(catalog.queries, ["catalina crunch"])
    }

    func testQuestBarUsesTheChocolateChipLabel() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "Quest bar")
        XCTAssertEqual(meal.calories, 190, accuracy: 1)
        XCTAssertEqual(meal.proteinG, 21, accuracy: 0.5)
        XCTAssertEqual(meal.carbsG, 22, accuracy: 0.5)
        XCTAssertEqual(meal.fatG, 8, accuracy: 0.5)
        XCTAssertTrue(meal.name.lowercased().contains("quest"))
        XCTAssertFalse(meal.name.lowercased().contains("serving chips"))
        XCTAssertEqual(catalog.queries, ["quest bar"])
    }

    func testTwoQuestBarsScaleTheLabelServing() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "2 quest bars")
        XCTAssertEqual(meal.calories, 380, accuracy: 1)
        XCTAssertEqual(meal.proteinG, 42, accuracy: 0.5)
    }

    func testChipotleChickenBowlUsesTheRestaurantBuild() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "Chipotle chicken bowl")
        XCTAssertEqual(meal.calories, 785, accuracy: 1)
        XCTAssertEqual(meal.proteinG, 52, accuracy: 0.5)
        XCTAssertEqual(meal.carbsG, 73, accuracy: 0.5)
        XCTAssertEqual(meal.fatG, 30, accuracy: 0.5)
        XCTAssertTrue(meal.name.lowercased().contains("chipotle"))
        XCTAssertEqual(meal.source, .restaurant)
        XCTAssertTrue(catalog.queries.isEmpty)
    }

    func testFairlifeProteinShakeIsNotChocolateMilk() async {
        let shake = await FoodAnalysisService.resolveMealForLogging(from: "Fairlife protein shake")
        XCTAssertEqual(shake.calories, 150, accuracy: 1)
        XCTAssertEqual(shake.proteinG, 30, accuracy: 0.5)
        XCTAssertEqual(shake.carbsG, 4, accuracy: 0.5)
        XCTAssertEqual(shake.fatG, 2.5, accuracy: 0.3)
        XCTAssertTrue(shake.name.lowercased().contains("shake"))
        XCTAssertTrue(catalog.queries.isEmpty)

        catalog.queries.removeAll()
        let milk = await FoodAnalysisService.resolveMealForLogging(from: "Fairlife")
        XCTAssertEqual(milk.calories, 140, accuracy: 1)
        XCTAssertEqual(milk.proteinG, 13, accuracy: 0.5)
        XCTAssertTrue(catalog.queries.isEmpty)
    }

    func testDavesKillerBreadStaysOnTheSliceLabel() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "Dave's Killer Bread 21 grain")
        XCTAssertEqual(meal.calories, 110, accuracy: 0.5)
        XCTAssertEqual(meal.proteinG, 5, accuracy: 0.2)
        XCTAssertEqual(meal.carbsG, 22, accuracy: 0.2)
        XCTAssertEqual(meal.fatG, 1.5, accuracy: 0.2)
        XCTAssertTrue(catalog.queries.isEmpty, "USDA per-100 g bread must not replace the 110 kcal slice")
    }

    func testCatalinaDressingIsNotAcceptedAsTheCereal() async {
        catalog.responses = ["catalina crunch": [Self.catalinaDressing]]
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "Catalina Crunch")
        XCTAssertEqual(meal.calories, 242, accuracy: 1)
        XCTAssertEqual(meal.proteinG, 8, accuracy: 0.1)
        XCTAssertFalse(meal.name.lowercased().contains("dressing"))
    }

    func testCloseProductsAskInsteadOfGuessing() async {
        catalog.responses = [
            "mystery munch": [
                hit("Mystery Munch Original", brand: "Mystery", calories: 100, protein: 4, carbs: 12, fat: 3, serving: "1 pack"),
                hit("Mystery Munch Spicy", brand: "Mystery", calories: 400, protein: 8, carbs: 40, fat: 22, serving: "1 pack"),
            ],
        ]
        let outcome = await FoodAnalysisService.resolveFoodLog(from: "mystery munch")
        XCTAssertTrue(outcome.needsConfirmation)
        XCTAssertGreaterThanOrEqual(outcome.choices.count, 2)
        let calories = outcome.choices.map(\.meal.calories).sorted()
        XCTAssertEqual(calories.first ?? 0, 100, accuracy: 1)
        XCTAssertEqual(calories.last ?? 0, 400, accuracy: 1)
    }

    func testGenericFoodsDoNotSearchTheBrandCatalog() {
        XCTAssertFalse(BrandedFoodResolver.shouldSearchCatalog("I had raw honey"))
        XCTAssertFalse(BrandedFoodResolver.shouldSearchCatalog("6 oz chicken"))
        XCTAssertFalse(BrandedFoodResolver.shouldSearchCatalog("8 fl oz whole milk"))
        XCTAssertTrue(BrandedFoodResolver.shouldSearchCatalog("Catalina Crunch"))
        XCTAssertTrue(BrandedFoodResolver.shouldSearchCatalog("catalena crunch"))
    }

    func testMilkLookupStaysOnTheCupWeight() async {
        let meal = await FoodAnalysisService.resolveMealForLogging(from: "8 fl oz whole milk")
        XCTAssertEqual(meal.calories, 61 * 244 / 100, accuracy: 2)
        XCTAssertTrue(catalog.queries.isEmpty)
    }

    func testUSDASearchNutrientsAreScaledToTheLabelServing() {
        let food: [String: Any] = [
            "description": "CINNAMON TOAST CEREAL, CINNAMON TOAST",
            "brandName": "CATALINA CRUNCH",
            "brandOwner": "Catalina Snacks Inc.",
            "servingSize": 36.0,
            "servingSizeUnit": "GRM",
            "householdServingFullText": "1/2 cup",
            "foodNutrients": [
                ["nutrientId": 1008, "nutrientName": "Energy", "unitName": "KCAL", "value": 306.0] as [String: Any],
                ["nutrientId": 1003, "nutrientName": "Protein", "unitName": "G", "value": 30.6] as [String: Any],
                ["nutrientId": 1005, "nutrientName": "Carbohydrate, by difference", "unitName": "G", "value": 38.9] as [String: Any],
                ["nutrientId": 1004, "nutrientName": "Total lipid (fat)", "unitName": "G", "value": 13.9] as [String: Any],
            ],
        ]
        let serving = USDAFoodDataService.brandedServing(fromSearchFood: food)
        XCTAssertEqual(serving?.perServing.calories ?? 0, 110.16, accuracy: 0.5)
        XCTAssertEqual(serving?.perServing.proteinG ?? 0, 11.016, accuracy: 0.2)
        XCTAssertEqual(serving?.perServing.carbsG ?? 0, 14.0, accuracy: 0.2)
        XCTAssertEqual(serving?.perServing.fatG ?? 0, 5.0, accuracy: 0.2)
        XCTAssertLessThan(serving?.perServing.calories ?? 999, 150, "Per-100 g energy must not be logged as the serving")
        XCTAssertTrue(serving?.name.lowercased().contains("catalina") == true)
        XCTAssertTrue(serving?.name.lowercased().contains("cinnamon") == true)

        var missing = food
        missing["servingSize"] = 0
        XCTAssertNil(USDAFoodDataService.brandedServing(fromSearchFood: missing))
    }

    func testLookupReplacesAGenericGuessButNotAnEqualGuess() {
        let guess = MealPayload(name: "Catalina Crunch", calories: 242, proteinG: 8, carbsG: 30, fatG: 10, source: .genericEstimate)
        let labeled = MealPayload(
            name: "Catalina Crunch Cinnamon Toast",
            calories: 110,
            proteinG: 11,
            carbsG: 14,
            fatG: 5,
            isLabelBacked: true,
            source: .usda
        )
        XCTAssertTrue(FoodAnalysisService.lookupShouldReplace(original: guess, resolved: labeled))
        let stillGuessing = MealPayload(name: "Something", calories: 242, proteinG: 8, carbsG: 30, fatG: 10, source: .genericEstimate)
        XCTAssertFalse(FoodAnalysisService.lookupShouldReplace(original: guess, resolved: stillGuessing))
    }

    private static let catalinaDressing = hit(
        "Catalina Dressing",
        brand: "Kraft",
        calories: 120,
        protein: 0,
        carbs: 8,
        fat: 10,
        serving: "2 tbsp (30 g)"
    )

    private static let fixtures: [String: [BrandedFoodHit]] = [
        "catalina crunch": [
            catalinaDressing,
            hit(
                "Cinnamon Toast Cereal",
                brand: "Catalina Crunch",
                calories: 110,
                protein: 11,
                carbs: 14,
                fat: 5,
                serving: "1/2 cup (36 g)"
            ),
            hit(
                "Dark Chocolate Cereal",
                brand: "Catalina Crunch",
                calories: 150,
                protein: 11,
                carbs: 15,
                fat: 6,
                serving: "1/2 cup (36 g)"
            ),
            hit(
                "Cinnamon Toast Cereal",
                brand: "Catalina Crunch",
                calories: 225,
                protein: 14,
                carbs: 20,
                fat: 9,
                serving: "1 portion"
            ),
        ],
        "quest bar": [
            hit(
                "Chocolate Chip Protein Bar",
                brand: "Quest",
                calories: 190,
                protein: 21,
                carbs: 22,
                fat: 8,
                serving: "1 bar (60 g)"
            ),
            hit("Fruit Snacks", brand: "Sea Quest", calories: 100, protein: 1, carbs: 22, fat: 1, serving: "1 bag"),
            hit("Protein Chips", brand: "Quest", calories: 140, protein: 18, carbs: 5, fat: 6, serving: "1 bag (32 g)"),
            hit("Vanilla Protein Bar", brand: "Quest", calories: 180, protein: 20, carbs: 22, fat: 7, serving: "1 bar (60 g)"),
        ],
    ]

    private static func hit(
        _ name: String,
        brand: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        serving: String
    ) -> BrandedFoodHit {
        BrandedFoodHit(
            name: name,
            brand: brand,
            perServing: MacroTotals(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat),
            servingDescription: serving,
            barcode: nil,
            source: .usda
        )
    }
}

private final class ScriptedBrandCatalog: BrandedFoodCatalog {
    var queries: [String] = []
    var responses: [String: [BrandedFoodHit]]

    init(responses: [String: [BrandedFoodHit]] = [:]) {
        self.responses = responses
    }

    func searchBranded(query: String) async -> [BrandedFoodHit] {
        queries.append(query)
        return responses[query] ?? []
    }
}
