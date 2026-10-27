import Foundation
import XCTest
@testable import FunFitnessTrainer

/// Locks calorie math that used to multiply the wrong unit, treat kJ as kcal, or drop a digit in a food name into the serving count.
final class CalorieAccuracyTests: XCTestCase {

    // MARK: - Staples and quantity

    func testProductNameDigitsAreNotAServingCount() {
        let one = StapleNutritionDatabase.scale(for: "Dave's 21 Whole Grains")
        XCTAssertEqual(one?.totals.calories ?? 0, 110, accuracy: 0.5)
        let two = StapleNutritionDatabase.scale(for: "2 slices of Dave's 21 Whole Grains")
        XCTAssertEqual(two?.totals.calories ?? 0, 220, accuracy: 0.5)
    }

    func testThreeEggsStayOneEggTimesThree() {
        let eggs = StapleNutritionDatabase.scale(for: "3 eggs")
        XCTAssertEqual(eggs?.totals.calories ?? 0, 216, accuracy: 1)
    }

    func testMilkUsesCupWeightNotACountOfServings() {
        let eight = StapleNutritionDatabase.scale(for: "8 fl oz whole milk")
        XCTAssertEqual(eight?.totals.calories ?? 0, 61 * 244 / 100, accuracy: 2)
        XCTAssertLessThan(eight?.totals.calories ?? 0, 200)

        let sixteen = StapleNutritionDatabase.scale(for: "16 fl oz milk")
        XCTAssertEqual(sixteen?.totals.calories ?? 0, 61 * 244 / 100 * 2, accuracy: 3)
        XCTAssertLessThan(sixteen?.totals.calories ?? 9999, 400)
    }

    func testOrangeJuiceMillilitersUseDensityNotAServingCount() {
        let juice = StapleNutritionDatabase.scale(for: "200 ml orange juice")
        let grams = 248.0 * (200.0 / FoodUnit.mlPerCup)
        XCTAssertEqual(juice?.totals.calories ?? 0, 45 * grams / 100, accuracy: 2)
        XCTAssertLessThan(juice?.totals.calories ?? 9999, 150)
    }

    func testGreekYogurtGramsAreNotCups() {
        let hundred = StapleNutritionDatabase.scale(for: "100 g Greek yogurt")
        XCTAssertEqual(hundred?.totals.calories ?? 0, 100.0 * 100 / 170, accuracy: 1)
        XCTAssertEqual(hundred?.totals.proteinG ?? 0, 17.0 * 100 / 170, accuracy: 0.5)

        let sixOz = StapleNutritionDatabase.scale(for: "6 oz Greek yogurt")
        XCTAssertEqual(sixOz?.totals.calories ?? 0, 100, accuracy: 2)
    }

    func testOliveOilTablespoonAndOunce() {
        let tbsp = StapleNutritionDatabase.scale(for: "1 tbsp olive oil")
        XCTAssertEqual(tbsp?.totals.calories ?? 0, 119, accuracy: 0.5)
        let ounce = StapleNutritionDatabase.scale(for: "1 oz olive oil")
        let expected = 119 * FoodUnit.gramsPerOunce / 13.5
        XCTAssertEqual(ounce?.totals.calories ?? 0, expected, accuracy: 1)
    }

    func testCupOfSpinachIsNotCupOfRice() {
        let spinach = StapleNutritionDatabase.scale(for: "1 cup spinach")
        XCTAssertLessThan(spinach?.totals.calories ?? 99, 20)
        let rice = StapleNutritionDatabase.scale(for: "1 cup rice")
        XCTAssertEqual(rice?.totals.calories ?? 0, 205, accuracy: 1)
    }

    func testChickenOuncesStayOnThe100GramReference() {
        let six = StapleNutritionDatabase.scale(for: "6 oz chicken")
        let sixGrams = 6 * FoodUnit.gramsPerOunce
        XCTAssertEqual(six?.totals.calories ?? 0, 165 * sixGrams / 100, accuracy: 0.5)
        let eight = StapleNutritionDatabase.scale(for: "8 oz chicken")
        XCTAssertEqual(eight?.totals.calories ?? 0, (six?.totals.calories ?? 0) * 8 / 6, accuracy: 0.5)
    }

    func testCoffeeOuncesScaleFromATwelveOunceDrink() {
        let sixteen = FoodAnalysisService.estimateOffline(from: "16 oz latte")
        XCTAssertEqual(sixteen.calories, 190 * 16 / 12, accuracy: 1)
        let half = FoodAnalysisService.estimateOffline(from: "half a latte")
        XCTAssertEqual(half.calories, 95, accuracy: 1)
    }

    func testBurgerOuncesAreNotAServingCount() {
        let one = FoodAnalysisService.estimateOffline(from: "8 oz burger")
        XCTAssertEqual(one.calories, 650, accuracy: 1)
        let two = FoodAnalysisService.estimateOffline(from: "2 burgers")
        XCTAssertEqual(two.calories, 1300, accuracy: 1)
    }

    func testMultiItemMealSumsLineItems() {
        let meal = FoodAnalysisService.estimateOffline(from: "3 eggs and 2 slices of Dave's 21")
        XCTAssertEqual(meal.entriesForLogging().count, 2)
        XCTAssertEqual(meal.calories, 216 + 220, accuracy: 1)
    }

    func testRepeatedPhotoTotalsAreNotCountedOncePerItem() {
        let result = FoodAnalysisResult(
            calories: 800,
            proteinG: 40,
            carbsG: 80,
            fatG: 30,
            items: ["zorchpaste", "blorble snack"],
            lineItems: [
                MealLineItem(name: "zorchpaste", calories: 800, proteinG: 40, carbsG: 80, fatG: 30),
                MealLineItem(name: "blorble snack", calories: 800, proteinG: 40, carbsG: 80, fatG: 30),
            ],
            confidence: 0.4,
            assumptions: []
        )
        let meal = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: result)
        XCTAssertEqual(meal.lineItems.count, 2)
        XCTAssertEqual(meal.calories, 242 * 2, accuracy: 1)
        XCTAssertTrue(meal.lineItems.allSatisfy { $0.calories < 300 })
    }

    func testHalfServingScalesBarcodeMacros() {
        let product = BarcodeProductResult(
            barcode: "000",
            name: "Cookie",
            brand: nil,
            servingDescription: "1 cookie",
            imageURL: nil,
            perServing: MacroTotals(calories: 100, proteinG: 1, carbsG: 12, fatG: 5),
            servingQuantityMl: nil
        )
        let payload = FoodAnalysisService.mealPayload(from: product, userDescription: "half a serving")
        XCTAssertEqual(payload.calories, 50, accuracy: 0.01)
        XCTAssertEqual(payload.proteinG, 0.5, accuracy: 0.01)
    }

    func testExplodedPortionDisplayIsRewritten() {
        let yogurt = FoodAnalysisService.displayMacros(
            name: "100 g Greek yogurt",
            calories: 10_000,
            proteinG: 1_700,
            carbsG: 600,
            fatG: 0
        )
        XCTAssertEqual(yogurt.calories, 100.0 * 100 / 170, accuracy: 1)

        let milk = FoodAnalysisService.displayMacros(
            name: "8 fl oz whole milk",
            calories: 488,
            proteinG: 25,
            carbsG: 38,
            fatG: 26
        )
        XCTAssertEqual(milk.calories, 61 * 244 / 100, accuracy: 2)
    }

    // MARK: - Open Food Facts

    func testPerServingCaloriesWinOverPer100g() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Crackers",
            "serving_size": "28 g",
            "serving_quantity": "28",
            "nutriments": [
                "energy-kcal_serving": 140,
                "proteins_serving": 2,
                "carbohydrates_serving": 20,
                "fat_serving": 5,
                "energy-kcal_100g": 500,
            ],
        ], barcode: "111")
        XCTAssertEqual(parsed?.perServing.calories ?? 0, 140, accuracy: 0.1)
    }

    func testMissingServingQuantityUsesTheGramLabel() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Crackers",
            "serving_size": "28 g",
            "nutriments": [
                "energy-kcal_100g": 500,
                "proteins_100g": 8,
                "carbohydrates_100g": 70,
                "fat_100g": 15,
            ],
        ], barcode: "222")
        XCTAssertEqual(parsed?.perServing.calories ?? 0, 140, accuracy: 0.5)
    }

    func testNutritionDataPerServingIsNotDividedBy100() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Bar",
            "serving_size": "30 g",
            "serving_quantity": 30,
            "nutrition_data_per": "serving",
            "nutriments": [
                "energy-kcal": 150,
                "proteins": 10,
                "carbohydrates": 12,
                "fat": 6,
            ],
        ], barcode: "333")
        XCTAssertEqual(parsed?.perServing.calories ?? 0, 150, accuracy: 0.1)
        XCTAssertEqual(parsed?.perServing.proteinG ?? 0, 10, accuracy: 0.1)
    }

    func testKilojoulesCopiedIntoTheKcalFieldAreConverted() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Muesli",
            "serving_size": "50 g",
            "nutriments": [
                "energy-kcal_serving": 1674,
                "energy-kj_serving": 1674,
                "proteins_serving": 8,
                "carbohydrates_serving": 60,
                "fat_serving": 15,
            ],
        ], barcode: "444")
        XCTAssertEqual(parsed?.perServing.calories ?? 0, 1674 / 4.184, accuracy: 1)
    }

    func testZeroKcalWithKilojoulesUsesKilojoules() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Yogurt",
            "serving_size": "150 g",
            "nutriments": [
                "energy-kcal_serving": 0,
                "energy-kj_serving": 628,
                "proteins_serving": 8,
                "carbohydrates_serving": 12,
                "fat_serving": 6,
            ],
        ], barcode: "555")
        XCTAssertEqual(parsed?.perServing.calories ?? 0, 628 / 4.184, accuracy: 1)
    }

    func testDietSodaStaysAtZero() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Diet soda",
            "serving_size": "1 can (12 fl oz)",
            "serving_quantity": 1,
            "nutriments": [
                "energy-kcal_serving": 0,
                "proteins_serving": 0,
                "carbohydrates_serving": 0,
                "fat_serving": 0,
            ],
        ], barcode: "666")
        XCTAssertEqual(parsed?.perServing.calories ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(parsed?.servingQuantityMl ?? 0, 12 * FoodUnit.mlPerFluidOunce, accuracy: 1)
    }

    func testGramServingIsNotTreatedAsMilliliters() {
        let parsed = OpenFoodFactsService.parseProduct([
            "product_name": "Bread",
            "serving_size": "45 g",
            "serving_quantity": 45,
            "nutriments": [
                "energy-kcal_100g": 250,
                "proteins_100g": 9,
                "carbohydrates_100g": 45,
                "fat_100g": 3,
            ],
        ], barcode: "777")
        XCTAssertNil(parsed?.servingQuantityMl)
        XCTAssertEqual(parsed?.perServing.calories ?? 0, 112.5, accuracy: 0.5)
    }

    func testRealBeerCaloriesAreNotTreatedAsKilojoules() {
        let beer = MacroTrackingEngine.normalizedEnergy(
            reportedCalories: 153,
            proteinG: 1.6,
            carbsG: 12.6,
            fatG: 0
        )
        XCTAssertEqual(beer, 153, accuracy: 0.1)
        let oil = MacroTrackingEngine.normalizedEnergy(
            reportedCalories: 884,
            proteinG: 0,
            carbsG: 0,
            fatG: 100
        )
        XCTAssertEqual(oil, 884, accuracy: 0.1)
    }

    func testLabelOCRConvertsKilojoulesAndMislabelledEnergy() {
        let kilojoules = FoodPhotoLocalAnalysis.parseNutritionFacts(from: [
            "Nutrition Facts",
            "Energy 628 kJ",
            "Protein 8g",
            "Total Carbohydrate 20g",
            "Total Fat 2g",
        ])
        XCTAssertEqual(kilojoules?.calories ?? 0, 628 / 4.184, accuracy: 1)

        let copied = FoodPhotoLocalAnalysis.parseNutritionFacts(from: [
            "Nutrition Facts",
            "Calories 1674",
            "Protein 8g",
            "Total Carbohydrate 60g",
            "Total Fat 15g",
        ])
        XCTAssertEqual(copied?.calories ?? 0, 1674 / 4.184, accuracy: 1)
    }

    // MARK: - Goals, days, display

    func testHeavyCutMacrosMatchTheCalorieTarget() {
        let settings = UserSettings(
            sex: .male,
            age: 70,
            heightCm: 160,
            weightKg: 300 * GoalCalculator.lbToKg,
            goalWeightKg: 220 * GoalCalculator.lbToKg,
            weeklyLbChangeTarget: -2,
            activity: .sedentary,
            goalType: .lose,
            dietStyle: .balanced
        )
        let macros = GoalCalculator.recommendedMacros(for: settings)
        let energy = macros.proteinG * 4 + macros.carbsG * 4 + macros.fatG * 9
        XCTAssertLessThanOrEqual(abs(energy - macros.calories), 9)
        XCTAssertLessThanOrEqual(macros.calories, 1600)
    }

    func testNormalMaintainPlanKeepsProteinAndCalorieAgreement() {
        let settings = UserSettings(
            sex: .male,
            age: 30,
            heightCm: 175,
            weightKg: 75,
            activity: .moderate,
            goalType: .maintain,
            dietStyle: .balanced
        )
        let macros = GoalCalculator.recommendedMacros(for: settings)
        let energy = macros.proteinG * 4 + macros.carbsG * 4 + macros.fatG * 9
        XCTAssertLessThanOrEqual(abs(energy - macros.calories), 9)
        XCTAssertEqual(macros.proteinG, (75 * GoalCalculator.kgToLb).rounded(), accuracy: 0.1)
    }

    func testDriftedActivityMultiplierPicksTheNearestLevel() {
        let settings = UserSettings(activity: .moderate)
        settings.activityRaw = 1.54
        XCTAssertEqual(settings.activity, .moderate)
        settings.activityRaw = 1.37
        XCTAssertEqual(settings.activity, .light)
    }

    func testLocalDayBoundaryDoesNotCountThePreviousEvening() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let loggedAt = try XCTUnwrap(formatter.date(from: "2026-10-27T06:30:00Z"))
        let meal = Meal(name: "Late snack", calories: 180, proteinG: 8, carbsG: 12, fatG: 6, loggedAt: loggedAt)
        let oct27 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 15)))
        let oct26 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15)))
        XCTAssertTrue(DaySummaryService.mealsToday(from: [meal], date: oct27, calendar: calendar).isEmpty)
        XCTAssertEqual(DaySummaryService.mealsToday(from: [meal], date: oct26, calendar: calendar).count, 1)
    }

    func testDeletingAMealDropsItFromTheDayTotal() {
        let eggs = Meal(name: "Eggs", calories: 216, proteinG: 18, carbsG: 2, fatG: 15)
        let toast = Meal(name: "Toast", calories: 110, proteinG: 5, carbsG: 22, fatG: 2)
        XCTAssertEqual(DaySummaryService.totals(for: [eggs, toast]).calories, 326, accuracy: 0.1)
        XCTAssertEqual(DaySummaryService.totals(for: [eggs]).calories, 216, accuracy: 0.1)
    }

    func testQuantityChangeScalesEveryMacro() {
        let start = MacroTotals(calories: 110, proteinG: 5, carbsG: 22, fatG: 1.5)
        let doubled = MacroTrackingEngine.scaledForQuantityChange(start, from: 1, to: 2)
        XCTAssertEqual(doubled.calories, 220, accuracy: 0.01)
        XCTAssertEqual(doubled.proteinG, 10, accuracy: 0.01)
        XCTAssertEqual(doubled.fatG, 3, accuracy: 0.01)
    }

    func testLowConfidenceCaloriesRoundToTheNearestCalorie() {
        let text = FoodAnalysisService.formatEstimateForDisplay(280.6, isCalories: true, confidence: .low)
        XCTAssertEqual(text, "281")
    }

    func testStringCalorieJSONDecodes() throws {
        let json = """
        {"name":"Yogurt","calories":"150.5","protein_g":"10","carbs_g":12,"fat_g":"4.5","line_items":[{"name":"Yogurt","calories":"150.5","protein_g":"10","carbs_g":"12","fat_g":4.5}]}
        """.data(using: .utf8)!
        let meal = try JSONDecoder().decode(MealPayload.self, from: json)
        XCTAssertEqual(meal.calories, 150.5, accuracy: 0.01)
        XCTAssertEqual(meal.proteinG, 10, accuracy: 0.01)
        XCTAssertEqual(meal.lineItems.first?.carbsG ?? 0, 12, accuracy: 0.01)
    }
}
