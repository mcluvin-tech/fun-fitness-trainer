import Foundation
import SwiftData
import XCTest
@testable import FunFitnessTrainer

/// Regression tests for photo → macro estimation.
/// These lock the chicken+rice save path and the 1-count / 100g collapse.
final class PhotoMacroPipelineTests: XCTestCase {

    // MARK: - Ground truth (USDA-style staples already in the app)

    /// 6 oz cooked chicken breast vs 100g reference (165 kcal / 31g protein).
    private var sixOzCookedChicken: MacroTotals {
        let grams = 6 * FoodUnit.gramsPerOunce
        return MacroTrackingEngine.scale(
            MacroTotals(calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6),
            by: grams / 100
        )
    }

    private var oneCupRice: MacroTotals {
        MacroTotals(calories: 205, proteinG: 4.3, carbsG: 45, fatG: 0.4)
    }

    private var threeEggs: MacroTotals {
        MacroTrackingEngine.scale(
            MacroTotals(calories: 72, proteinG: 6.3, carbsG: 0.4, fatG: 4.8),
            by: 3
        )
    }

    private var oneTbspOil: MacroTotals {
        MacroTotals(calories: 119, proteinG: 0, carbsG: 0, fatG: 13.5)
    }

    // MARK: 1. Photo chicken + rice must not lose protein on save

    func testPhotoChickenAndRiceDoesNotLoseProteinDuringSave() throws {
        let analysis = FoodAnalysisResult(
            calories: 720,
            proteinG: 45,
            carbsG: 80,
            fatG: 18,
            items: ["chicken breast", "white rice"],
            confidence: 0.72,
            assumptions: ["Visual plate estimate"],
            labelDetected: false,
            source: .cloudAI
        )

        let confirmed = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        let entries = confirmed.entriesForLogging()
        let savedProtein = entries.reduce(0) { $0 + $1.proteinG }
        let savedCalories = entries.reduce(0) { $0 + $1.calories }

        XCTAssertGreaterThan(
            savedProtein,
            30,
            "Chicken + rice photo must not collapse protein. Got \(savedProtein)g across \(entries.map { "\($0.name)=\($0.proteinG)" })"
        )
        XCTAssertGreaterThan(savedCalories, 250)
        XCTAssertNotEqual(
            savedProtein,
            45,
            "GPT's 45g protein must not be the authoritative saved value when staples match."
        )

        let context = try inMemoryContext()
        let meals = MealLogging.insertReturningMeals(confirmed, into: context)
        let fetched = fetchMeals(context)
        XCTAssertEqual(fetched.count, meals.count)
        XCTAssertEqual(fetched.reduce(0) { $0 + $1.proteinG }, savedProtein, accuracy: 0.01)
        XCTAssertEqual(fetched.reduce(0) { $0 + $1.calories }, savedCalories, accuracy: 0.01)
    }

    // MARK: 2. Explicit ounces scale the 100g chicken reference

    func testExplicitOuncesScaleChickenReference() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "6 oz cooked chicken"))
        XCTAssertEqual(scaled.totals.calories, sixOzCookedChicken.calories, accuracy: 1)
        XCTAssertEqual(scaled.totals.proteinG, sixOzCookedChicken.proteinG, accuracy: 1)
        XCTAssertEqual(scaled.portion.unit, .ounce)
        XCTAssertEqual(scaled.portion.amount, 6, accuracy: 0.01)
    }

    func testEightOuncesIsNotTheSixOunceDefault() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "8 oz cooked chicken breast"))
        let expectedGrams = 8 * FoodUnit.gramsPerOunce
        XCTAssertEqual(scaled.totals.proteinG, 31 * expectedGrams / 100, accuracy: 1)
        XCTAssertGreaterThan(scaled.totals.proteinG, sixOzCookedChicken.proteinG + 5)
    }

    // MARK: 3. Eggs / count foods

    func testTwinkieUsesHostessLabelNotGenericProtein() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "a twinkie"))
        XCTAssertEqual(scaled.totals.calories, 140, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.proteinG, 1, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.carbsG, 23, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.fatG, 4.5, accuracy: 0.5)

        let logged = FoodAnalysisService.estimateOffline(from: "I had a twinkie")
        let entry = try XCTUnwrap(logged.entriesForLogging().first)
        XCTAssertEqual(entry.calories, 140, accuracy: 0.5)
        XCTAssertEqual(entry.proteinG, 1, accuracy: 0.5)
        XCTAssertLessThan(entry.proteinG, 3, "A Twinkie must not be logged as a 10g protein win.")
    }

    func testTwoTwinkiesScaleByCount() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "2 twinkies"))
        XCTAssertEqual(scaled.totals.calories, 280, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.proteinG, 2, accuracy: 0.5)
    }

    func testEggsScaleByCount() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "3 eggs"))
        XCTAssertEqual(scaled.totals.calories, threeEggs.calories, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.proteinG, threeEggs.proteinG, accuracy: 0.5)
    }

    // MARK: 4. Rice / cup foods

    func testRiceScalesByCup() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "1 cup white rice"))
        XCTAssertEqual(scaled.totals.calories, oneCupRice.calories, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.proteinG, oneCupRice.proteinG, accuracy: 0.5)
    }

    // MARK: 5. Oils use tbsp

    func testOilScalesByTablespoon() throws {
        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "1 tbsp olive oil"))
        XCTAssertEqual(scaled.totals.calories, oneTbspOil.calories, accuracy: 0.5)
        XCTAssertEqual(scaled.totals.fatG, oneTbspOil.fatG, accuracy: 0.5)
        XCTAssertEqual(scaled.portion.unit, .tablespoon)
    }

    func testOilIsNotAutoAddedToCookedMeals() {
        let analysis = FoodAnalysisResult(
            calories: 400,
            proteinG: 50,
            carbsG: 0,
            fatG: 8,
            items: ["cooked chicken breast"],
            lineItems: [
                MealLineItem(
                    name: "cooked chicken breast",
                    calories: 0,
                    proteinG: 0,
                    carbsG: 0,
                    fatG: 0,
                    quantity: 6,
                    unit: "oz",
                    preparationState: "cooked"
                ),
            ],
            confidence: 0.6,
            assumptions: ["Cooking fat not visible"],
            labelDetected: false,
            source: .cloudAI
        )
        let resolved = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        let names = resolved.entriesForLogging().map { $0.name.lowercased() }
        XCTAssertFalse(names.contains(where: { $0.contains("oil") || $0.contains("butter") }))
        XCTAssertEqual(resolved.entriesForLogging().count, 1)
    }

    // MARK: 6. Label / barcode nutrition is not overwritten

    func testLabelBackedNutritionIsNotReplacedByStaple() {
        let payload = MealPayload(
            name: "3 Eggs",
            calories: 140,
            proteinG: 13,
            carbsG: 13,
            fatG: 4.5,
            isLabelBacked: true,
            source: .manufacturer,
            confidence: .high
        )
        let reconciled = FoodAnalysisService.reconcileMealPayload(payload)
        XCTAssertEqual(reconciled.calories, 140, accuracy: 0.01)
        XCTAssertEqual(reconciled.proteinG, 13, accuracy: 0.01)
        XCTAssertEqual(reconciled.source, .manufacturer)
    }

    func testKettleBagBarcodeIgnoresTheLotCodeAndKeepsTheProductName() {
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: [
                "910001039152",
                "12357-4PPC",
                "JALAPEÑO",
                "84114 12357",
                "2",
            ]),
            "084114123572",
            "The number above the bars is a lot code. The UPC is 0 84114 12357 2, with the 0 printed off the white label."
        )
        XCTAssertNil(FoodPhotoLocalAnalysis.gtinIfValid("910001039152"))

        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: [
                "Total Fat 0g",
                "Total Carb. 25g",
                "0",
                "49000 06101",
            ]),
            "049000061017",
            "The Coke can prints the check digit off the bars. 0 49000 06101 still restores it."
        )
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: ["49000 06101"]),
            "049000061017",
            "When the can hides both guard digits, the middle groups are still the Coke UPC."
        )

        let analysis = FoodAnalysisResult(
            calories: 150,
            proteinG: 2,
            carbsG: 15,
            fatG: 9,
            items: ["Kettle Brand, Potato Chips Jalapeño"],
            confidence: 0.95,
            assumptions: ["Barcode 0084114123572"],
            labelDetected: true,
            barcode: "0084114123572",
            source: .barcode
        )
        let resolved = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        XCTAssertEqual(resolved.name, "Kettle Brand, Potato Chips Jalapeño")
        XCTAssertEqual(resolved.entriesForLogging().first?.name, "Kettle Brand, Potato Chips Jalapeño")
        XCTAssertEqual(resolved.calories, 150, accuracy: 0.01)
        XCTAssertEqual(resolved.fatG, 9, accuracy: 0.01)
        XCTAssertNotEqual(resolved.name, "1 Serving Chips")
    }

    func testBarcodePhotoResultStaysManufacturer() {
        let analysis = FoodAnalysisResult(
            calories: 110,
            proteinG: 5,
            carbsG: 22,
            fatG: 1.5,
            items: ["Dave's Killer Bread"],
            confidence: 0.95,
            assumptions: ["Barcode 013764005043"],
            labelDetected: true,
            barcode: "013764005043",
            source: .barcode
        )
        let resolved = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        XCTAssertEqual(resolved.calories, 110, accuracy: 0.01)
        XCTAssertEqual(resolved.proteinG, 5, accuracy: 0.01)
        XCTAssertTrue(resolved.isLabelBacked)
        XCTAssertEqual(resolved.source, .manufacturer)
    }

    // MARK: 7. Saved macros equal confirmed / reconciled macros

    func testSavedMacrosEqualConfirmedReconciledMacros() throws {
        let analysis = cloudPlate(
            items: ["chicken breast", "white rice"],
            lineItems: [
                MealLineItem(name: "cooked chicken breast", calories: 400, proteinG: 40, carbsG: 0, fatG: 10, quantity: 6, unit: "oz", preparationState: "cooked"),
                MealLineItem(name: "white rice", calories: 300, proteinG: 5, carbsG: 65, fatG: 1, quantity: 1, unit: "cup"),
            ]
        )
        let confirmed = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        let context = try inMemoryContext()
        let inserted = MealLogging.insertReturningMeals(confirmed, into: context)
        let fetched = fetchMeals(context)

        XCTAssertEqual(inserted.count, fetched.count)
        XCTAssertEqual(
            inserted.reduce(0) { $0 + $1.calories },
            confirmed.entriesForLogging().reduce(0) { $0 + $1.calories },
            accuracy: 0.01
        )
        XCTAssertEqual(
            fetched.reduce(0) { $0 + $1.proteinG },
            confirmed.entriesForLogging().reduce(0) { $0 + $1.proteinG },
            accuracy: 0.01
        )
    }

    // MARK: 8. Photo and voice with the same line items match

    func testPhotoAndVoiceEquivalentLineItemsReconcileTheSame() {
        let lineItems = [
            MealLineItem(name: "cooked chicken breast", calories: 999, proteinG: 999, carbsG: 0, fatG: 0, quantity: 6, unit: "oz", preparationState: "cooked"),
            MealLineItem(name: "white rice", calories: 999, proteinG: 999, carbsG: 0, fatG: 0, quantity: 1, unit: "cup"),
        ]
        let photo = FoodAnalysisService.resolvedMeal(
            fromPhotoAnalysis: cloudPlate(items: ["chicken", "rice"], lineItems: lineItems)
        )
        let voice = FoodAnalysisService.reconcileMealPayload(
            MealPayload(
                name: "Meal",
                calories: 999,
                proteinG: 999,
                carbsG: 0,
                fatG: 0,
                lineItems: lineItems,
                source: .genericEstimate,
                confidence: .low
            )
        )
        let photoTotals = totals(photo.entriesForLogging())
        let voiceTotals = totals(voice.entriesForLogging())
        XCTAssertEqual(photoTotals.calories, voiceTotals.calories, accuracy: 1)
        XCTAssertEqual(photoTotals.proteinG, voiceTotals.proteinG, accuracy: 1)
        XCTAssertEqual(photoTotals.calories, sixOzCookedChicken.calories + oneCupRice.calories, accuracy: 2)
    }

    // MARK: 9. Missing quantity is not 1 count / 100g

    func testUnspecifiedChickenIsNotOneCountAgainst100g() throws {
        let portion = FoodQuantity.parse(from: "chicken")
        XCTAssertEqual(portion.amount, 1, accuracy: 0.01)
        XCTAssertEqual(portion.unit, .count, "Current parser treats bare 'chicken' as 1 count — that must not scale against 100g.")

        let scaled = try XCTUnwrap(StapleNutritionDatabase.scale(for: "chicken"))
        let collapsed = 165.0 / 100.0
        XCTAssertGreaterThan(
            scaled.totals.calories,
            100,
            "Bare 'chicken' collapsed to \(scaled.totals.calories) kcal (1 count / 100g ≈ \(collapsed))."
        )
        XCTAssertGreaterThan(scaled.totals.proteinG, 20)
        XCTAssertTrue(
            scaled.assumptions.contains(where: { $0.lowercased().contains("assumed") }),
            "Default plate portion must be an explicit assumption. Got: \(scaled.assumptions)"
        )
    }

    func testLegacyPhotoItemsArrayDoesNotCollapseChickenProtein() {
        let payload = MealPayload(
            name: "Meal",
            calories: 720,
            proteinG: 45,
            carbsG: 80,
            fatG: 18,
            items: ["chicken breast", "white rice"],
            source: .genericEstimate,
            confidence: .low
        )
        let entries = payload.entriesForLogging()
        let protein = entries.reduce(0) { $0 + $1.proteinG }
        XCTAssertGreaterThan(
            protein,
            30,
            "MealConfirmView.save used entriesForLogging() on GPT items[]. Chicken protein was \(protein)g."
        )
    }

    // MARK: 10. Existing meal rows remain readable

    func testExistingMealHistoryRemainsCompatible() throws {
        let context = try inMemoryContext()
        let legacy = Meal(
            name: "Legacy sandwich",
            calories: 450,
            proteinG: 28,
            carbsG: 40,
            fatG: 18,
            isEstimate: true,
            quantity: 1,
            unit: "serving",
            nutritionSource: "generic_estimate",
            nutritionConfidence: "medium"
        )
        context.insert(legacy)
        try context.save()

        let fetched = fetchMeals(context)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].calories, 450)
        XCTAssertEqual(fetched[0].proteinG, 28)
        XCTAssertEqual(fetched[0].sourceKind, .genericEstimate)
        XCTAssertEqual(fetched[0].confidenceKind, .medium)
    }

    func testVisionLineItemQuantityIsPreferredOverDefault() throws {
        let analysis = cloudPlate(
            items: ["chicken"],
            lineItems: [
                MealLineItem(
                    name: "cooked chicken breast",
                    calories: 10,
                    proteinG: 1,
                    carbsG: 0,
                    fatG: 0,
                    quantity: 8,
                    unit: "oz",
                    preparationState: "cooked"
                ),
            ]
        )
        let resolved = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        let entry = try XCTUnwrap(resolved.entriesForLogging().first)
        let expected = 31 * (8 * FoodUnit.gramsPerOunce) / 100
        XCTAssertEqual(entry.proteinG, expected, accuracy: 1.5)
        XCTAssertGreaterThan(entry.calories, 200, "GPT's 10 kcal must not win over the USDA 8 oz scale.")
        XCTAssertNotEqual(entry.calories, 10, accuracy: 0.5)
    }

    func testClippedVitaCocoUPCIsRecoveredFromPrintedDigits() {
        let lines = [
            "GLUTEN FREE",
            "Taste and color may vary. Once opened, keep",
            "refrigerated and consume within 7 days.",
            "8",
            "98999 01181",
            "3",
        ]
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: lines),
            "898999011813",
            "Spaced UPC under the bars must be joined. Open Food Facts has this Vita Coco code."
        )
    }

    func testMisreadCheckDigitOnCartonEdgeIsRepaired() {
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: ["8 98999 01181 8"]),
            "898999011813"
        )
        XCTAssertFalse(FoodPhotoLocalAnalysis.acceptedBarcode("123456789013"))
        XCTAssertTrue(FoodPhotoLocalAnalysis.acceptedBarcode("898999011813"))
        XCTAssertTrue(FoodPhotoLocalAnalysis.acceptedBarcode("0898999011813"))
    }

    func testUPCCheckDigitCutOffTheFrameIsRestored() {
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: ["8 98999 01181"]),
            "898999011813"
        )
    }

    func testQuestBarUPCRestoresCheckDigitWhenLotCodeFollows() {
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: [
                "8 88849 01158",
                "400771 • HB-CAC-TLCUS072125",
            ]),
            "888849011582",
            "The check digit sits on the crimped edge. The lot code under the bars must not block recovery."
        )
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: [
                "8 88849 01158 2",
                "400771 • HB-CAC-TLCUS072125",
            ]),
            "888849011582"
        )
        XCTAssertFalse(FoodPhotoLocalAnalysis.acceptedBarcode("400771"))
        XCTAssertTrue(FoodPhotoLocalAnalysis.acceptedBarcode("400771", allowsShortUPCE: true))
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.preferredScan([
                .init(raw: "400771", isUPCE: false),
                .init(raw: "888849011582", isUPCE: false),
            ]),
            "888849011582"
        )
    }

    func testKirklandCanUPCRestoresTheLeadingDigit() {
        XCTAssertEqual(
            FoodPhotoLocalAnalysis.barcodeDigits(in: [
                "ITM. / ART. 1925833",
                "96633 83142 2",
                "25V120778",
            ]),
            "196633831422",
            "The number-system digit is printed outside the bars. Open Food Facts stores this as 0196633831422."
        )
    }

    func testKirklandSparklingOrangeLabelReadsTenCalories() {
        let lines = [
            "SPARKLING ORANGE",
            "Contains 0% Juice",
            "Nutrition Facts",
            "1 serving per container",
            "Serving size",
            "1 Can (12 fl oz)",
            "Amount Per Serving",
            "Calories",
            "10",
            "% Daily Value*",
            "Total Fat 0g",
            "Sodium 100mg",
            "Total Carbohydrate 1g",
            "Total Sugars 0g",
            "Includes 0g Added Sugars",
            "Protein 0g",
        ]
        let parsed = FoodPhotoLocalAnalysis.parseNutritionFacts(from: lines)
        XCTAssertEqual(parsed?.calories, 10)
        XCTAssertEqual(parsed?.proteinG, 0)
        XCTAssertEqual(parsed?.carbsG, 1)
        XCTAssertEqual(parsed?.fatG, 0)
    }

    func testGarbledCanLabelStillReadsCalories() {
        let lines = [
            "Mutrition Facts",
            "rAlories",
            "10",
            "Total Fat 0g",
            "Teal Carbohydrate 1g",
            "Pretein 0g",
        ]
        let parsed = FoodPhotoLocalAnalysis.parseNutritionFacts(from: lines)
        XCTAssertEqual(parsed?.calories, 10)
        XCTAssertEqual(parsed?.carbsG, 1)
        XCTAssertEqual(parsed?.proteinG, 0)
        XCTAssertEqual(parsed?.fatG, 0)
    }

    func testIQBarUPCBeatsTheArticleNumber() {
        let lines = ["ITM. / ART. 1788968", "8 50004 55486 9", "FSC C002550"]
        XCTAssertEqual(FoodPhotoLocalAnalysis.barcodeDigits(in: lines), "850004554869")
        XCTAssertNil(FoodPhotoLocalAnalysis.barcodeDigits(in: ["ITM. / ART. 1788968"]))
    }

    func testBarcodeNormalizationKeepsProductCodes() {
        XCTAssertEqual(FoodPhotoLocalAnalysis.normalizedBarcode("012345678905"), "012345678905")
        XCTAssertEqual(FoodPhotoLocalAnalysis.normalizedBarcode("013764005043"), "013764005043")
        XCTAssertEqual(OpenFoodFactsBarcode.sameProduct("0013764005043", "013764005043"), true)
        XCTAssertNil(FoodPhotoLocalAnalysis.normalizedBarcode("not-a-code"))
    }

    func testPartialLogKeepsClementinesAndApple() {
        let partial = MealPayload(
            name: "Meal",
            calories: 474,
            proteinG: 25,
            carbsG: 61,
            fatG: 20,
            items: ["2 eggs", "3 slices Dave's toast"],
            lineItems: [
                MealLineItem(name: "2 eggs", calories: 144, proteinG: 13, carbsG: 1, fatG: 10),
                MealLineItem(name: "3 slices Dave's toast", calories: 330, proteinG: 12, carbsG: 60, fatG: 6),
            ]
        )
        let utterance = "I had two eggs and three slices of Dave's toast, clementines, and an apple"
        let completed = FoodAnalysisService.completingMissingFoods(partial, from: utterance)
        let names = completed.entriesForLogging().map { $0.name.lowercased() }

        XCTAssertEqual(completed.entriesForLogging().count, 4, "Got \(names)")
        XCTAssertTrue(names.contains { $0.contains("egg") })
        XCTAssertTrue(names.contains { $0.contains("toast") || $0.contains("dave") })
        XCTAssertTrue(names.contains { $0.contains("clementine") }, "Missing clementines in \(names)")
        XCTAssertTrue(names.contains { $0.contains("apple") }, "Missing apple in \(names)")
        XCTAssertEqual(names.filter { $0.contains("egg") }.count, 1)
    }

    func testOfflineBreakfastListLogsEveryFood() {
        let utterance = "I had two eggs and three slices of Dave's toast, clementines, and an apple"
        let names = FoodAnalysisService.estimateOffline(from: utterance).entriesForLogging().map { $0.name.lowercased() }
        XCTAssertEqual(names.count, 4, "Got \(names)")
        XCTAssertTrue(names.contains { $0.contains("clementine") })
        XCTAssertTrue(names.contains { $0.contains("apple") })
    }

    func testRawHoneyFallsThroughGenericEstimateUntilLookup() async {
        let offline = FoodAnalysisService.estimateOffline(from: "I had raw honey")
        let resolved = await FoodAnalysisService.resolveMealForLogging(from: "I had raw honey")
        let entry = offline.entriesForLogging().first
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "A",
            location: "PhotoMacroPipelineTests.testRawHoney",
            message: "raw honey offline vs lookup",
            data: [
                "offlineCalories": entry?.calories ?? -1,
                "offlineProtein": entry?.proteinG ?? -1,
                "offlineCarbs": entry?.carbsG ?? -1,
                "offlineFat": entry?.fatG ?? -1,
                "offlineSource": entry?.source.rawValue ?? "",
                "resolvedCalories": resolved.calories,
                "resolvedProtein": resolved.proteinG,
                "resolvedCarbs": resolved.carbsG,
                "resolvedFat": resolved.fatG,
                "resolvedSource": resolved.source.rawValue,
                "resolvedName": resolved.name,
                "labelBacked": resolved.isLabelBacked,
            ]
        )
        // #endregion
        XCTAssertEqual(entry?.calories ?? 0, 200, "Offline placeholder stays 200 until lookup")
        XCTAssertEqual(entry?.proteinG ?? 0, 10)
        XCTAssertEqual(resolved.source, .usda, "Raw honey should come from USDA, not the 200/10 placeholder")
        XCTAssertLessThan(resolved.proteinG, 1, "Honey is not a protein food")
        XCTAssertGreaterThan(resolved.calories, 50)
        XCTAssertLessThan(resolved.calories, 80, "1 tbsp honey is about 64 kcal, not 200")
        await AgentDebugLog.flush()
    }

    func testAlsoHadStillLogsFruit() {
        let names = FoodAnalysisService.estimateOffline(from: "I also had clementines and an apple")
            .entriesForLogging()
            .map { $0.name.lowercased() }
        XCTAssertEqual(names.count, 2, "Got \(names)")
        XCTAssertTrue(names.contains { $0.contains("clementine") })
        XCTAssertTrue(names.contains { $0.contains("apple") })
        let clementines = FoodQuantity.parse(from: "clementines")
        XCTAssertEqual(clementines.amount, 1, "clementines must not be read as ten")
    }

    func testItemsArrayDoesNotDropFoodsAfterLineItems() {
        let payload = MealPayload(
            name: "Meal",
            calories: 474,
            proteinG: 25,
            carbsG: 61,
            fatG: 20,
            items: ["2 eggs", "3 slices Dave's toast", "clementines and an apple"],
            lineItems: [
                MealLineItem(name: "2 eggs", calories: 144, proteinG: 13, carbsG: 1, fatG: 10),
                MealLineItem(name: "3 slices Dave's toast", calories: 330, proteinG: 12, carbsG: 60, fatG: 6),
            ]
        )
        let names = payload.entriesForLogging().map { $0.name.lowercased() }
        XCTAssertTrue(names.contains { $0.contains("clementine") }, "Got \(names)")
        XCTAssertTrue(names.contains { $0.contains("apple") }, "Got \(names)")
        XCTAssertEqual(names.filter { $0.contains("egg") }.count, 1)
    }

    func testConfirmScreenValuesMatchWhatWouldBeSaved() {
        let analysis = cloudPlate(
            items: ["chicken breast", "white rice"],
            lineItems: [
                MealLineItem(name: "cooked chicken breast", calories: 647, proteinG: 41, carbsG: 0, fatG: 12, quantity: 6, unit: "oz", preparationState: "cooked"),
                MealLineItem(name: "white rice", calories: 300, proteinG: 4, carbsG: 65, fatG: 1, quantity: 1, unit: "cup"),
            ]
        )
        let confirmed = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: analysis)
        let saved = totals(confirmed.entriesForLogging())
        XCTAssertEqual(confirmed.calories, saved.calories, accuracy: 0.01)
        XCTAssertEqual(confirmed.proteinG, saved.proteinG, accuracy: 0.01)
        XCTAssertNotEqual(confirmed.calories, 647, accuracy: 0.5)
    }

    // MARK: - Helpers

    private func cloudPlate(items: [String], lineItems: [MealLineItem]) -> FoodAnalysisResult {
        FoodAnalysisResult(
            calories: 647,
            proteinG: 45,
            carbsG: 80,
            fatG: 18,
            items: items,
            lineItems: lineItems,
            confidence: 0.7,
            assumptions: [],
            labelDetected: false,
            source: .cloudAI
        )
    }

    func testUPCAAndEAN13AreTheSameGroceryBarcode() {
        XCTAssertEqual(BarcodeNormalization.normalizedBarcode("898999011813"), "898999011813")
        XCTAssertEqual(BarcodeNormalization.normalizedBarcode("0898999011813"), "898999011813")
        XCTAssertEqual(BarcodeNormalization.normalizedBarcode(" 898999011813 "), "898999011813")
        XCTAssertEqual(BarcodeNormalization.normalizedBarcode("8 98999 01181 3"), "898999011813")

        let fromUPC = BarcodeNormalization.lookupCandidates(for: "898999011813")
        XCTAssertEqual(fromUPC, ["898999011813", "0898999011813"])

        let fromEAN = BarcodeNormalization.lookupCandidates(for: "0898999011813")
        XCTAssertTrue(fromEAN.contains("898999011813"))
        XCTAssertTrue(fromEAN.contains("0898999011813"))
        XCTAssertEqual(fromEAN.count, 2)
    }

    private func totals(_ entries: [MealPayload]) -> MacroTotals {
        MacroTrackingEngine.recipeTotals(entries.map {
            MacroTotals(calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        })
    }

    func testPintOfBeerUsesUSDANotCoffeeMacros() {
        let meal = FoodAnalysisService.estimateOffline(from: "I had a pint of beer")
        let entry = meal.entriesForLogging().first
        XCTAssertEqual(entry?.calories ?? -1, 204, accuracy: 1)
        XCTAssertEqual(entry?.proteinG ?? -1, 2.19, accuracy: 0.05)
        XCTAssertEqual(entry?.carbsG ?? -1, 16.85, accuracy: 0.05)
        XCTAssertEqual(entry?.fatG ?? -1, 0, accuracy: 0.01)
        XCTAssertLessThan(entry?.proteinG ?? 99, 3, "A pint of beer must not use the 8 g coffee profile")
        XCTAssertEqual(entry?.name.lowercased(), "pint of beer")
    }

    func testBeerLabelDoesNotStackOunces() {
        let messy = "16 oz oz oz oz oz pint of beer"
        let cleaned = FoodItemNaming.canonicalName(for: messy)
        XCTAssertEqual(cleaned.lowercased(), "pint of beer")
        var again = cleaned
        for _ in 0..<5 {
            again = FoodItemNaming.canonicalName(for: again)
        }
        XCTAssertEqual(again.lowercased(), "pint of beer")
        XCTAssertFalse(again.lowercased().contains("oz"))
    }

    func testCanOfBeerIsTwelveOunces() {
        let meal = FoodAnalysisService.estimateOffline(from: "I had a beer")
        let entry = meal.entriesForLogging().first
        XCTAssertEqual(entry?.calories ?? -1, 153, accuracy: 1)
        XCTAssertEqual(entry?.proteinG ?? -1, 1.64, accuracy: 0.05)
        XCTAssertEqual(entry?.carbsG ?? -1, 12.64, accuracy: 0.05)
    }

    func testCupOfSpinachIsNotCupOfRice() {
        let spinach = FoodAnalysisService.estimateOffline(from: "I had a cup of spinach")
        let rice = FoodAnalysisService.estimateOffline(from: "I had a cup of rice")
        let spinachEntry = spinach.entriesForLogging().first
        XCTAssertLessThan(spinachEntry?.calories ?? 999, 20)
        XCTAssertGreaterThan(rice.calories, 180)
        XCTAssertGreaterThan(rice.calories, (spinachEntry?.calories ?? 0) * 5)
    }

    func testTablespoonOfOilIsNotSalsa() {
        let oil = FoodAnalysisService.estimateOffline(from: "I had a tablespoon of olive oil")
        let salsa = FoodAnalysisService.estimateOffline(from: "I had a tablespoon of salsa")
        XCTAssertEqual(oil.calories, 119, accuracy: 1)
        XCTAssertLessThan(salsa.calories, 15)
    }

    func testPintOfBlondeBeerUsesAlcoholProfile() {
        let meal = FoodAnalysisService.estimateOffline(from: "I had a pint of blonde beer")
        XCTAssertGreaterThan(meal.calories, 180)
        XCTAssertLessThan(meal.calories, 240)
        XCTAssertLessThan(meal.proteinG, 3)
        XCTAssertGreaterThan(meal.carbsG, 14)
        XCTAssertLessThan(meal.carbsG, 22)
    }

    func testImplausibleSpinachIsRejected() {
        let bogus = MealPayload(name: "1 cup spinach", calories: 180, proteinG: 8, carbsG: 20, fatG: 4, source: .genericEstimate)
        let fixed = FoodAnalysisService.reconcileEstimate(bogus)
        XCTAssertLessThan(fixed.calories, 20)
        XCTAssertFalse(FoodEstimateGate.isPlausible(text: "1 cup spinach", calories: 180, proteinG: 2))
        XCTAssertFalse(FoodEstimateGate.isPlausible(text: "6 oz chicken breast", calories: 80, proteinG: 12))
        XCTAssertFalse(FoodEstimateGate.isPlausible(text: "a pint of beer", calories: 15, proteinG: 0))
        XCTAssertFalse(FoodEstimateGate.isPlausible(text: "1 tbsp olive oil", calories: 20, proteinG: 0))
    }

    func testLatteIsStillACoffeeDrink() {
        let meal = FoodAnalysisService.estimateOffline(from: "I had a latte")
        XCTAssertEqual(meal.proteinG, 8, accuracy: 0.1)
        XCTAssertEqual(meal.carbsG, 18, accuracy: 0.1)
    }

    private func inMemoryContext() throws -> ModelContext {
        let schema = Schema([Meal.self, ExerciseLog.self, DailyGoal.self, TrainerPhrase.self, UserSettings.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fetchMeals(_ context: ModelContext) -> [Meal] {
        (try? context.fetch(FetchDescriptor<Meal>())) ?? []
    }
}
