import XCTest
@testable import FunFitnessTrainer

final class LarryReactionEngineTests: XCTestCase {
    private let goal = MacroGoalPayload(calories: 2117, proteinG: 175, carbsG: 230, fatG: 70)

    // MARK: - Nutrition is about the room left, not the food name

    func testIceCreamEarlyInTheDayIsNeutral() {
        let category = judge(
            delta: MacroTotals(calories: 420, proteinG: 7, carbsG: 48, fatG: 22),
            previous: MacroTotals(calories: 280, proteinG: 18, carbsG: 30, fatG: 10)
        )
        XCTAssertEqual(category, .neutral)
    }

    func testIceCreamThatBlowsTheLastHundredCaloriesIsADisaster() {
        let category = judge(
            delta: MacroTotals(calories: 500, proteinG: 8, carbsG: 55, fatG: 26),
            previous: MacroTotals(calories: 2017, proteinG: 110, carbsG: 200, fatG: 60)
        )
        XCTAssertEqual(category, .disaster)
    }

    func testSameDessertMacrosStayNeutralWhenTheDayStillHasRoom() {
        let early = judge(
            delta: MacroTotals(calories: 200, proteinG: 10, carbsG: 24, fatG: 9),
            previous: MacroTotals(calories: 1176, proteinG: 116, carbsG: 120, fatG: 40)
        )
        XCTAssertEqual(early, .neutral)
    }

    func testBurgerThatCoversNeededProteinInsideCaloriesIsGreat() {
        let category = judge(
            delta: MacroTotals(calories: 650, proteinG: 42, carbsG: 40, fatG: 28),
            previous: MacroTotals(calories: 1200, proteinG: 80, carbsG: 110, fatG: 40)
        )
        XCTAssertEqual(category, .great)
    }

    func testHelpfulProteinMealThatIsNotABlowoutIsGood() {
        let category = judge(
            delta: MacroTotals(calories: 220, proteinG: 28, carbsG: 8, fatG: 6),
            previous: MacroTotals(calories: 900, proteinG: 50, carbsG: 80, fatG: 30)
        )
        XCTAssertEqual(category, .good)
    }

    func testHighCaloriesWithWeakProteinAgainstATightRemainderIsQuestionable() {
        let category = judge(
            delta: MacroTotals(calories: 550, proteinG: 8, carbsG: 70, fatG: 22),
            previous: MacroTotals(calories: 1500, proteinG: 70, carbsG: 140, fatG: 40)
        )
        XCTAssertEqual(category, .questionable)
    }

    func testMeaningfulOvershootIsBad() {
        let category = judge(
            delta: MacroTotals(calories: 400, proteinG: 6, carbsG: 45, fatG: 18),
            previous: MacroTotals(calories: 1900, proteinG: 90, carbsG: 180, fatG: 55)
        )
        XCTAssertEqual(category, .bad)
    }

    func testTinyAddOnWhenAlreadyOverDoesNotBecomeADisaster() {
        let category = judge(
            delta: MacroTotals(calories: 30, proteinG: 0, carbsG: 7, fatG: 0),
            previous: MacroTotals(calories: 2500, proteinG: 140, carbsG: 250, fatG: 80)
        )
        XCTAssertEqual(category, .neutral)
    }

    func testMissingGoalUsesPortionAndProteinNotAFoodLabel() {
        let lean = LarryNutritionJudge.category(
            delta: MacroTotals(calories: 420, proteinG: 48, carbsG: 4, fatG: 8),
            previous: .init(),
            goal: nil
        )
        let heavy = LarryNutritionJudge.category(
            delta: MacroTotals(calories: 1500, proteinG: 12, carbsG: 160, fatG: 70),
            previous: .init(),
            goal: nil
        )
        XCTAssertEqual(lean, .great)
        XCTAssertEqual(heavy, .disaster)
    }

    // MARK: - Emotion, pose, motion

    func testCategoriesMapToDistinctEmotions() {
        XCTAssertEqual(LarryEmotion.forCategory(.great), .excited)
        XCTAssertEqual(LarryEmotion.forCategory(.good), .confident)
        XCTAssertEqual(LarryEmotion.forCategory(.neutral), .neutral)
        XCTAssertEqual(LarryEmotion.forCategory(.questionable), .skeptical)
        XCTAssertEqual(LarryEmotion.forCategory(.bad), .disappointed)
        XCTAssertEqual(LarryEmotion.forCategory(.disaster), .shocked)
    }

    func testReplyToneDrivesEmotionInsteadOfDefaultingHappy() {
        XCTAssertEqual(
            LarryEmotion.fromReply("HELL YEAH. That's what I'm talking about."),
            .excited
        )
        XCTAssertEqual(
            LarryEmotion.fromReply("Brother... what are we doing?"),
            .disappointed
        )
        XCTAssertEqual(LarryEmotion.fromReply("GOOD LORD."), .shocked)
        XCTAssertEqual(
            LarryEmotion.fromReply("Interesting strategy, champ."),
            .skeptical
        )
        XCTAssertEqual(
            LarryEmotion.fromReply("Sure, I can help with that."),
            .neutral
        )
    }

    func testNeutralDessertDoesNotUseHorrifiedDonutArt() {
        let horrified: Set<LarryVoicePose> = [.donutShock, .donutGlare, .donutCrush, .donut, .disbelief, .yell]
        for seed in 0..<6 {
            let pose = LarryPoseSelector.pose(for: .neutral, seed: seed, flavorText: "Ice Cream")
            XCTAssertFalse(horrified.contains(pose))
        }
    }

    func testDisasterDessertCanUseExistingShockArt() {
        let allowed: Set<LarryVoicePose> = [.donutShock, .donutCrush, .disbelief]
        for seed in 0..<6 {
            let pose = LarryPoseSelector.pose(for: .shocked, seed: seed, flavorText: "Ice Cream")
            XCTAssertTrue(allowed.contains(pose))
        }
    }

    func testExcitedPoseStaysInThePositiveCatalog() {
        let allowed: Set<LarryVoicePose> = [.cheering, .thumbsUp, .flex]
        for seed in 0..<6 {
            let pose = LarryPoseSelector.pose(for: .excited, seed: seed, flavorText: "Chicken breast")
            XCTAssertTrue(allowed.contains(pose))
        }
    }

    func testMotionsMatchEmotionsAndStayShort() {
        XCTAssertEqual(LarryReactionMotion.forEmotion(.excited), .popBounce)
        XCTAssertEqual(LarryReactionMotion.forEmotion(.confident), .scaleNod)
        XCTAssertEqual(LarryReactionMotion.forEmotion(.neutral), .fade)
        XCTAssertEqual(LarryReactionMotion.forEmotion(.skeptical), .tilt)
        XCTAssertEqual(LarryReactionMotion.forEmotion(.disappointed), .headShake)
        XCTAssertEqual(LarryReactionMotion.forEmotion(.shocked), .recoil)

        for motion in [LarryReactionMotion.popBounce, .scaleNod, .fade, .tilt, .headShake, .recoil] {
            let end = motion.keyframes.last?.time ?? 0
            XCTAssertGreaterThanOrEqual(end, 0.5)
            XCTAssertLessThanOrEqual(end, 1.2)
        }
    }

    // MARK: - Quotes

    func testQuotesRotateThroughACategoryBeforeRepeating() {
        var picker = LarryQuotePicker(randomIndex: { _ in 0 })
        let pool = LarryQuoteBank.lines(for: .neutral)
        var seen: [String] = []
        for _ in pool {
            seen.append(picker.pick(for: .neutral))
        }
        XCTAssertEqual(Set(seen).count, pool.count)
        let next = picker.pick(for: .neutral)
        XCTAssertNotEqual(next, seen.last)
        XCTAssertTrue(pool.contains(next))
    }

    func testTwinkieIsPissedEvenWhenTheDayStillHasRoom() {
        let presentation = present(
            mealName: "Twinkie",
            delta: MacroTotals(calories: 140, proteinG: 1, carbsG: 23, fatG: 4.5),
            previous: MacroTotals(calories: 400, proteinG: 30, carbsG: 40, fatG: 15)
        )
        XCTAssertEqual(presentation.category, .bad)
        XCTAssertEqual(presentation.emotion, .disappointed)
        XCTAssertEqual(presentation.quote, "That's going straight to your thighs.")
        XCTAssertTrue(presentation.pose.isNegative)
    }

    func testGenericTwinkieMacrosDoNotMakeLarryHappy() {
        let presentation = present(
            mealName: "Twinkie",
            delta: MacroTotals(calories: 200, proteinG: 10, carbsG: 15, fatG: 8),
            previous: MacroTotals(calories: 400, proteinG: 30, carbsG: 40, fatG: 15)
        )
        XCTAssertEqual(presentation.category, .bad)
        XCTAssertNotEqual(presentation.emotion, .excited)
        XCTAssertNotEqual(presentation.emotion, .confident)
        XCTAssertTrue(presentation.quote.lowercased().contains("thigh"))
    }

    func testChickenWithRoomStillGetsPraise() {
        let presentation = present(
            mealName: "Chicken breast",
            delta: MacroTotals(calories: 280, proteinG: 53, carbsG: 0, fatG: 6),
            previous: MacroTotals(calories: 400, proteinG: 30, carbsG: 40, fatG: 15)
        )
        XCTAssertEqual(presentation.category, .great)
        XCTAssertEqual(presentation.emotion, .excited)
    }

    func testThighLineReadsAsPissed() {
        XCTAssertEqual(
            LarryEmotion.fromReply("That's going straight to your thighs."),
            .disappointed
        )
    }

    func testEveryCategoryHasSeveralLines() {
        for category in LarryReactionCategory.allCases {
            XCTAssertGreaterThanOrEqual(LarryQuoteBank.lines(for: category).count, 6)
        }
    }

    private func judge(delta: MacroTotals, previous: MacroTotals) -> LarryReactionCategory {
        LarryNutritionJudge.category(delta: delta, previous: previous, goal: goal)
    }

    private func present(mealName: String, delta: MacroTotals, previous: MacroTotals) -> LarryReactionPresentation {
        LarryReactionComposer.present(snapshot: LarryReactionSnapshot(
            mealName: mealName,
            delta: delta,
            previousConsumed: previous,
            newConsumed: previous + delta,
            goal: goal,
            mealsLoggedToday: 2,
            loggedMealCount: 1,
            streakDays: 1
        ))
    }
}

final class VoiceTurnMachineTests: XCTestCase {
    func testLogThenLogAgain() {
        var machine = VoiceTurnMachine()
        let first = machine.beginListening()
        XCTAssertEqual(machine.phase, .listening)
        machine.beginProcessing()
        XCTAssertEqual(machine.phase, .processing)
        XCTAssertTrue(machine.beginSpeaking(for: first))
        XCTAssertEqual(machine.phase, .speaking)

        machine.finishToIdle()
        XCTAssertEqual(machine.phase, .idle)
        let second = machine.beginListening()
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(machine.beginSpeaking(for: first), "The first meal's reply must not take the mic back")
        XCTAssertEqual(machine.phase, .listening)
    }

    func testInterruptWhileSpeakingStartsAnotherListen() {
        var machine = VoiceTurnMachine()
        let spoken = machine.beginListening()
        machine.beginProcessing()
        XCTAssertTrue(machine.beginSpeaking(for: spoken))

        let next = machine.interruptSpeaking()
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertNotEqual(spoken, next)
        XCTAssertFalse(machine.beginSpeaking(for: spoken))
        XCTAssertEqual(machine.phase, .listening)
    }

    func testRecognizerErrorRecoversToIdleAndListensAgain() {
        var machine = VoiceTurnMachine()
        _ = machine.beginListening()
        machine.recoverFromRecognizerError()
        XCTAssertEqual(machine.phase, .idle)

        let again = machine.beginListening()
        XCTAssertEqual(machine.phase, .listening)
        XCTAssertGreaterThan(again, 0)
        machine.beginProcessing()
        machine.recoverFromRecognizerError()
        XCTAssertEqual(machine.phase, .idle)
        _ = machine.beginListening()
        XCTAssertEqual(machine.phase, .listening)
    }

    func testTimeoutResetsAndAllowsTheNextMeal() {
        var machine = VoiceTurnMachine()
        let stuck = machine.beginListening()
        machine.timedOut()
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.beginSpeaking(for: stuck))
        _ = machine.beginListening()
        XCTAssertEqual(machine.phase, .listening)
    }
}
