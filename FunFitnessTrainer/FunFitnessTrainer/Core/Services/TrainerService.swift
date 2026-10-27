import Foundation

struct ChatMessageDTO: Codable {
    let role: String
    let content: String
}

struct TrainerChatResponse: Codable {
    let reply: String
    let replies: [String]?
    let suggested_goal: MacroGoalPayload?
    let suggested_meal: MealPayload?
    let suggested_exercise: ExercisePayload?
    /// When true, the client deletes today's food + exercise log entries.
    let clear_todays_log: Bool?

    init(
        reply: String,
        replies: [String]?,
        suggested_goal: MacroGoalPayload?,
        suggested_meal: MealPayload?,
        suggested_exercise: ExercisePayload? = nil,
        clear_todays_log: Bool? = nil
    ) {
        self.reply = reply
        self.replies = replies
        self.suggested_goal = suggested_goal
        self.suggested_meal = suggested_meal
        self.suggested_exercise = suggested_exercise
        self.clear_todays_log = clear_todays_log
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = try c.decode(String.self, forKey: .reply)
        replies = try c.decodeIfPresent([String].self, forKey: .replies)
        suggested_goal = try? c.decode(MacroGoalPayload.self, forKey: .suggested_goal)
        suggested_meal = try? c.decode(MealPayload.self, forKey: .suggested_meal)
        suggested_exercise = try? c.decode(ExercisePayload.self, forKey: .suggested_exercise)
        clear_todays_log = try c.decodeIfPresent(Bool.self, forKey: .clear_todays_log)
    }

    /// One or more Larry chat bubbles to show (splits on MSG_SPLIT when needed).
    var chatReplies: [String] {
        let raw: [String]
        if let replies, !replies.isEmpty {
            raw = replies
        } else if reply.contains("\nMSG_SPLIT\n") {
            raw = reply
                .components(separatedBy: "\nMSG_SPLIT\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            raw = [reply]
        }
        return raw
            .map(Self.stripStructuredBlocks)
            .map(LarrySpeechStyle.clean)
            .filter { !$0.isEmpty }
    }

    /// One spoken reply for the Duolingo-style talk screen.
    var spokenReply: String {
        chatReplies.joined(separator: " ")
    }

    /// Removes backend-only MEAL_JSON / GOAL_JSON / EXERCISE_JSON / CLEAR_LOG blocks from user-facing text.
    private static func stripStructuredBlocks(_ text: String) -> String {
        var result = text
        for prefix in ["MEAL_JSON:", "GOAL_JSON:", "EXERCISE_JSON:", "CLEAR_LOG:"] {
            while let markerRange = result.range(of: prefix) {
                guard let braceStart = result[markerRange.upperBound...].firstIndex(of: "{") else {
                    result.removeSubrange(markerRange.lowerBound..<result.endIndex)
                    break
                }
                var depth = 0
                var inString = false
                var escape = false
                var blockEnd = braceStart

                for index in result[braceStart...].indices {
                    let ch = result[index]
                    if inString {
                        if escape {
                            escape = false
                        } else if ch == "\\" {
                            escape = true
                        } else if ch == "\"" {
                            inString = false
                        }
                        continue
                    }
                    if ch == "\"" {
                        inString = true
                    } else if ch == "{" {
                        depth += 1
                    } else if ch == "}" {
                        depth -= 1
                        if depth == 0 {
                            blockEnd = result.index(after: index)
                            break
                        }
                    }
                }
                let before = String(result[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let after = String(result[blockEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                result = [before, after].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TrainerService {
    /// User-facing chat — never throws; falls back to offline coach replies.
    static func chatSafely(
        mode: String,
        messages: [ChatMessageDTO],
        trainerVoice: String,
        phrases: [String],
        goal: MacroGoalPayload?,
        consumed: MacroTotals,
        remaining: MacroTotals? = nil,
        goalType: String? = nil,
        exerciseCaloriesBurned: Double = 0,
        weightKg: Double = 75,
        stepsToday: Double? = nil,
        stepGoal: Int = 10_000,
        settings: UserSettings? = nil
    ) async -> TrainerChatResponse {
        if let clear = clearLogResponseIfRequested(messages: messages) {
            return clear
        }
        if let plan = planExplanationResponseIfRequested(
            messages: messages,
            settings: settings,
            exerciseCaloriesBurned: exerciseCaloriesBurned,
            goal: goal
        ) {
            return plan
        }
        let lastUser = messages.last(where: { $0.role == "user" })?.content ?? ""
        let lowered = lastUser.lowercased()
        if looksLikeOpenMealAsk(lowered) {
            let resolvedGoal = goal ?? MacroGoalPayload(calories: 2000, proteinG: 150, carbsG: 180, fatG: 60)
            let left = remaining ?? goal.map { DaySummaryService.remaining(consumed: consumed, goal: $0) }
                ?? MacroTotals(calories: 800, proteinG: 50, carbsG: 70, fatG: 25)
            let pack = mealSuggestionPack(remaining: left, goal: resolvedGoal, utterance: lowered)
            return TrainerChatResponse(
                reply: pack.spoken,
                replies: nil,
                suggested_goal: resolvedGoal,
                suggested_meal: nil,
                suggested_exercise: nil
            )
        }
        do {
            return try await chat(
                mode: mode,
                messages: messages,
                trainerVoice: trainerVoice,
                phrases: phrases,
                goal: goal,
                consumed: consumed,
                remaining: remaining,
                goalType: goalType,
                exerciseCaloriesBurned: exerciseCaloriesBurned,
                weightKg: weightKg,
                stepsToday: stepsToday,
                stepGoal: stepGoal,
                settings: settings
            )
        } catch {
            return await applyAutoMealLogIfNeeded(
                offlineResponse(
                    mode: mode,
                    messages: messages,
                    consumed: consumed,
                    goal: goal,
                    remaining: remaining,
                    phrases: phrases,
                    weightKg: weightKg,
                    settings: settings,
                    exerciseCaloriesBurned: exerciseCaloriesBurned
                ),
                messages: messages,
                mode: mode
            )
        }
    }

    static func chat(
        mode: String,
        messages: [ChatMessageDTO],
        trainerVoice: String,
        phrases: [String],
        goal: MacroGoalPayload?,
        consumed: MacroTotals,
        remaining: MacroTotals? = nil,
        goalType: String? = nil,
        exerciseCaloriesBurned: Double = 0,
        weightKg: Double = 75,
        stepsToday: Double? = nil,
        stepGoal: Int = 10_000,
        settings: UserSettings? = nil
    ) async throws -> TrainerChatResponse {
        if let clear = clearLogResponseIfRequested(messages: messages) {
            return clear
        }
        if let plan = planExplanationResponseIfRequested(
            messages: messages,
            settings: settings,
            exerciseCaloriesBurned: exerciseCaloriesBurned,
            goal: goal
        ) {
            return plan
        }
        guard AppConfig.hasBackend else {
            return await applyAutoMealLogIfNeeded(
                offlineResponse(
                    mode: mode,
                    messages: messages,
                    consumed: consumed,
                    goal: goal,
                    remaining: remaining,
                    phrases: phrases,
                    weightKg: weightKg,
                    settings: settings,
                    exerciseCaloriesBurned: exerciseCaloriesBurned
                ),
                messages: messages,
                mode: mode
            )
        }

        let remainingPayload = remaining ?? (goal.map {
            DaySummaryService.remaining(consumed: consumed, goal: $0)
        })

        var context: [String: Any] = [
            "trainer_voice": trainerVoice,
            "phrases": phrases,
            "goal": goal.map { goalDict($0) } as Any,
            "consumed": macroDict(consumed),
            "remaining": remainingPayload.map { macroDict($0) } as Any,
            "coach_philosophy": GoalCalculator.leanCoachPhilosophy,
            "goal_type": goalType ?? settings?.resolvedGoalType.rawValue ?? "lose",
            "local_hour": Calendar.current.component(.hour, from: Date()),
            "eating_clean_today": goal.map { hasEatenCleanToday(consumed: consumed, goal: $0) } ?? false,
            "exercise_calories_burned": exerciseCaloriesBurned,
            "weight_kg": settings?.weightKg ?? weightKg,
            "step_goal": stepGoal,
        ]
        if let stepsToday {
            context["steps_today"] = Int(stepsToday)
        }
        if let settings {
            context["fitness_plan"] = GoalCalculator.coachPlanContext(
                for: settings,
                exerciseCalorieBonus: exerciseCaloriesBurned
            )
            context["plan_explanation"] = GoalCalculator.larryPlanExplanation(
                for: settings,
                exerciseCalorieBonus: exerciseCaloriesBurned
            )
        }

        let body: [String: Any] = [
            "mode": mode,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "context": context,
        ]

        let data = try await SupabaseService.shared.invokeFunction(name: "trainer-chat", body: body, retries: 1)
        var response = try parseChatResponse(data)
        if response.clear_todays_log == true {
            return TrainerChatResponse(
                reply: response.reply,
                replies: response.replies,
                suggested_goal: nil,
                suggested_meal: nil,
                suggested_exercise: nil,
                clear_todays_log: true
            )
        }
        response = await applyAutoMealLogIfNeeded(response, messages: messages, mode: mode)
        return response
    }

    static func reaction(
        tag: PhraseTag,
        phrases: [TrainerPhrase],
        trainerVoice: String,
        goal: MacroGoalPayload?,
        consumed: MacroTotals
    ) async throws -> String {
        let sample = phrases.filter { $0.tag == tag || $0.tag == .general }.map(\.text)
        let response = try await chat(
            mode: "reaction",
            messages: [ChatMessageDTO(role: "user", content: "Give a one-liner for tag: \(tag.rawValue)")],
            trainerVoice: trainerVoice,
            phrases: sample,
            goal: goal,
            consumed: consumed
        )
        return response.reply
    }

    private static func parseChatResponse(_ data: Data) throws -> TrainerChatResponse {
        if let decoded = try? JSONDecoder().decode(TrainerChatResponse.self, from: data) {
            return decoded
        }

        // Backend may omit suggested_meal on older deploys — decode flexibly.
        struct Partial: Codable {
            let reply: String
            let replies: [String]?
            let suggested_goal: MacroGoalPayload?
            let suggested_meal: MealPayload?
            let suggested_exercise: ExercisePayload?
            let clear_todays_log: Bool?
        }
        let partial = try JSONDecoder().decode(Partial.self, from: data)
        return TrainerChatResponse(
            reply: partial.reply,
            replies: partial.replies,
            suggested_goal: partial.suggested_goal,
            suggested_meal: partial.suggested_meal,
            suggested_exercise: partial.suggested_exercise,
            clear_todays_log: partial.clear_todays_log
        )
    }

    /// Deterministic wipe for voice/text — do not rely on the model for destructive actions.
    private static func clearLogResponseIfRequested(messages: [ChatMessageDTO]) -> TrainerChatResponse? {
        guard let lastUser = messages.last(where: { $0.role == "user" })?.content else { return nil }
        guard looksLikeClearTodaysLog(lastUser.lowercased()) else { return nil }
        return TrainerChatResponse(
            reply: "Wiped today's log. Meals and workouts. Blank slate. Don't screw it up this time.",
            replies: nil,
            suggested_goal: nil,
            suggested_meal: nil,
            suggested_exercise: nil,
            clear_todays_log: true
        )
    }

    private static func planExplanationResponseIfRequested(
        messages: [ChatMessageDTO],
        settings: UserSettings?,
        exerciseCaloriesBurned: Double,
        goal: MacroGoalPayload?
    ) -> TrainerChatResponse? {
        guard let settings else { return nil }
        guard let lastUser = messages.last(where: { $0.role == "user" })?.content else { return nil }
        guard looksLikePlanExplanationQuestion(lastUser.lowercased()) else { return nil }
        return TrainerChatResponse(
            reply: GoalCalculator.larryPlanExplanation(
                for: settings,
                exerciseCalorieBonus: exerciseCaloriesBurned
            ),
            replies: nil,
            suggested_goal: goal,
            suggested_meal: nil,
            suggested_exercise: nil
        )
    }

    private static func looksLikeClearTodaysLog(_ text: String) -> Bool {
        let triggers = [
            "clear my log", "clear the log", "clear today's log", "clear todays log",
            "clear my food log", "clear the food log", "clear my meal log",
            "wipe my log", "wipe the log", "wipe today's log", "wipe todays log",
            "reset my log", "reset the log", "reset today's log", "reset todays log",
            "delete my log", "delete the log", "delete today's log", "delete todays log",
            "empty my log", "empty the log", "start my log over", "start the log over",
            "clear all my meals", "delete all my meals", "remove all my meals",
            "clear everything from my log", "wipe everything from my log",
            "clear my entire log", "clear the entire log", "clear the whole log",
            "wipe my entire log", "wipe the whole log",
        ]
        return triggers.contains { text.contains($0) }
    }

    /// "How did you choose my calories / for my weight / explain my targets"
    private static func looksLikePlanExplanationQuestion(_ text: String) -> Bool {
        let triggers = [
            "how did you choose", "how do you choose", "how did you pick", "how do you pick",
            "how did you set", "how do you set", "how did you calculate", "how do you calculate",
            "how are my calories", "how were my calories", "why are my calories", "why is my calorie",
            "why is my target", "why are my macros", "why is my protein",
            "explain my calories", "explain my macros", "explain my target", "explain my plan",
            "how you chose my", "how you choose my", "chose my calories", "choose my calories",
            "how he chose", "how larry chose", "how did larry", "how does larry",
            "based on my weight", "for my weight", "from my weight",
            "how my calories", "where do my calories", "where did my calories",
            "what is my bmr", "what's my bmr", "whats my bmr",
            "what is my tdee", "what's my tdee", "whats my tdee",
            "what is my maintenance", "what's my maintenance", "whats my maintenance",
            "how was my goal", "how were my goals", "how is my goal calculated",
            "how my goal was", "how my targets", "how my target",
        ]
        guard triggers.contains(where: { text.contains($0) }) else { return false }
        // Avoid treating food-logging lines as plan questions.
        if looksLikeConfirmedFoodLog(text) || looksLikeCurrentFoodConsumption(text) { return false }
        return true
    }

    private static func looksLikeFitnessQuestion(_ text: String) -> Bool {
        if looksLikePlanExplanationQuestion(text) { return true }
        if looksLikeConfirmedFoodLog(text) || looksLikeCurrentFoodConsumption(text) { return false }
        if looksLikeFoodMacroQuery(text) || looksLikeHypotheticalFood(text) { return false }
        if looksLikeMealSuggestion(text) { return false }

        let questionish = text.contains("?")
            || text.hasPrefix("how ")
            || text.hasPrefix("what ")
            || text.hasPrefix("why ")
            || text.hasPrefix("should i ")
            || text.hasPrefix("can i ")
            || text.contains("how much")
            || text.contains("how often")
            || text.contains("how many")

        let topics = [
            "protein", "calorie", "macro", "deficit", "surplus", "bulk", "cut", "cutting",
            "workout", "work out", "lifting", "lift ", "weights", "cardio", "steps",
            "muscle", "fat loss", "lose weight", "gain weight", "gain muscle",
            "maintenance", "bmr", "tdee", "activity level", "rest day",
            "how much protein", "protein per", "grams of protein",
            "should i train", "should i lift", "should i do cardio",
            "refeed", "cheat day", "water weight", "scale weight",
            "fitness", "training", "progressive overload",
        ]
        guard topics.contains(where: { text.contains($0) }) else { return false }
        return questionish || topics.contains(where: {
            text.contains("about \($0)") || text.contains("tell me about")
        })
    }

    private static func offlineFitnessReply(
        text: String,
        settings: UserSettings?,
        goal: MacroGoalPayload?,
        remaining: MacroTotals?,
        exerciseCaloriesBurned: Double
    ) -> String {
        if looksLikePlanExplanationQuestion(text), let settings {
            return GoalCalculator.larryPlanExplanation(
                for: settings,
                exerciseCalorieBonus: exerciseCaloriesBurned
            )
        }

        if text.contains("protein") {
            let weightLb = Int(((settings?.weightKg ?? 75) * GoalCalculator.kgToLb).rounded())
            let target = goal.map { Int($0.proteinG) }
            let perLb = String(format: "%.1f", GoalCalculator.proteinGramsPerLb)
            if let target {
                return "Protein target is ~\(target)g, about \(perLb) g per lb at \(weightLb) lb. Hit it with eggs, chicken, fish, Greek yogurt. Miss it and you're just decorating the gym."
            }
            return "Aim ~\(perLb) g protein per lb bodyweight. Real food first. Macros don't lie."
        }

        if text.contains("cardio") || text.contains("steps") {
            return "Cardio and steps are tracked, but they don't add extra food. Your calorie target already includes your activity level. Keep lifting and hitting protein."
        }

        if text.contains("lift") || text.contains("workout") || text.contains("train") || text.contains("muscle") {
            return "Lift heavy enough to progress, eat your protein, and sleep. Fancy programs don't beat consistency. Logging the work is for the record, not extra snacks."
        }

        if text.contains("deficit") || text.contains("cut") || text.contains("lose weight") || text.contains("fat loss") {
            if let goal {
                return "Fat loss is a calorie deficit plus high protein. Your plan is ~\(MacroTrackingEngine.displayCalories(goal.calories)) cal and \(MacroTrackingEngine.displayGrams(goal.proteinG))g protein. Stay under that without crashing below the floor. Patience beats crash diets."
            }
            return "Fat loss = consistent deficit + high protein + lifting. Crash cuts make you a little bitch on the scale next week."
        }

        if text.contains("bulk") || text.contains("surplus") || text.contains("gain") {
            return "Lean gains: small surplus, high protein, progressive overload. Dirty bulking just makes your jeans tighter, not your lifts."
        }

        if let remaining, let goal {
            return "Fitness isn't complicated: hit ~\(MacroTrackingEngine.displayGrams(goal.proteinG))g protein, land near ~\(MacroTrackingEngine.displayCalories(goal.calories)) cal, train. You've got ~\(MacroTrackingEngine.displayCalories(remaining.calories)) cal and \(MacroTrackingEngine.displayGrams(remaining.proteinG))g protein left today. Ask how I set your calories if you want the math."
        }

        if let goal {
            return "Plan today: ~\(MacroTrackingEngine.displayCalories(goal.calories)) cal, \(MacroTrackingEngine.displayGrams(goal.proteinG))g protein. Ask how I chose those numbers for your weight if you want the formula. Mifflin St Jeor, not fairy dust."
        }

        return "Ask me how I set your calories, protein targets, cutting vs building, or training. I'll give you the math, not motivational posters."
    }

    private static func goalDict(_ g: MacroGoalPayload) -> [String: Any] {
        macroDict(MacroTotals(
            calories: g.calories,
            proteinG: g.proteinG,
            carbsG: g.carbsG,
            fatG: g.fatG
        ))
    }

    private static func macroDict(_ m: MacroTotals) -> [String: Any] {
        [
            "calories": m.calories,
            "protein_g": m.proteinG,
            "carbs_g": m.carbsG,
            "fat_g": m.fatG,
        ]
    }

    private static func offlineResponse(
        mode: String,
        messages: [ChatMessageDTO],
        consumed: MacroTotals,
        goal: MacroGoalPayload?,
        remaining: MacroTotals?,
        phrases: [String],
        weightKg: Double = 75,
        settings: UserSettings? = nil,
        exerciseCaloriesBurned: Double = 0
    ) -> TrainerChatResponse {
        let lastUser = messages.last(where: { $0.role == "user" })?.content ?? ""
        let text = lastUser.lowercased()
        var suggestedMeal: MealPayload?

        if looksLikeClearTodaysLog(text) {
            return TrainerChatResponse(
                reply: "Wiped today's log. Meals and workouts. Blank slate. Don't screw it up this time.",
                replies: nil,
                suggested_goal: nil,
                suggested_meal: nil,
                suggested_exercise: nil,
                clear_todays_log: true
            )
        }

        if looksLikePlanExplanationQuestion(text), let settings {
            return TrainerChatResponse(
                reply: GoalCalculator.larryPlanExplanation(
                    for: settings,
                    exerciseCalorieBonus: exerciseCaloriesBurned
                ),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: nil,
                suggested_exercise: nil
            )
        }

        if looksLikeExerciseLog(text) {
            let estimate = ExerciseEstimateService.estimate(from: lastUser, weightKg: weightKg)
            return TrainerChatResponse(
                reply: offlineExerciseLogReply(for: estimate),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: nil,
                suggested_exercise: estimate
            )
        }

        if looksLikeFoodConfirmation(text) {
            let raw = foodDescriptionFromContext(messages) ?? lastUser
            let source = FoodItemNaming.foodMentionForLogging(from: raw) ?? raw
            suggestedMeal = FoodAnalysisService.estimateOffline(from: source)
            return TrainerChatResponse(
                reply: offlineLogReply(for: suggestedMeal!),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: suggestedMeal,
                suggested_exercise: nil
            )
        }

        if looksLikeConfirmedFoodLog(text) || looksLikeCurrentFoodConsumption(text) {
            let source = FoodItemNaming.foodMentionForLogging(from: lastUser) ?? lastUser
            suggestedMeal = FoodAnalysisService.estimateOffline(from: source)
            return TrainerChatResponse(
                reply: offlineLogReply(for: suggestedMeal!),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: suggestedMeal,
                suggested_exercise: nil
            )
        }

        if looksLikeMealSuggestion(text), let goal, let remaining {
            let reply = leanMealSuggestions(remaining: remaining, goal: goal, utterance: text)
            return TrainerChatResponse(reply: reply, replies: nil, suggested_goal: goal, suggested_meal: nil, suggested_exercise: nil)
        }

        if looksLikeHypotheticalFood(text) {
            let estimate = FoodAnalysisService.estimateOffline(from: lastUser)
            let replyParts = offlineHypotheticalReplies(
                estimate: estimate,
                remaining: remaining,
                utterance: lastUser,
                consumed: consumed,
                goal: goal
            )
            return TrainerChatResponse(
                reply: replyParts[0],
                replies: replyParts,
                suggested_goal: goal,
                suggested_meal: nil,
                suggested_exercise: nil
            )
        }

        if looksLikeFoodMacroQuery(text) {
            let estimate = FoodAnalysisService.estimateOffline(from: lastUser)
            let replyParts = offlineFoodMacroQueryReplies(
                estimate: estimate,
                remaining: remaining,
                utterance: lastUser,
                consumed: consumed,
                goal: goal
            )
            return TrainerChatResponse(
                reply: replyParts[0],
                replies: replyParts.count > 1 ? replyParts : nil,
                suggested_goal: goal,
                suggested_meal: nil,
                suggested_exercise: nil
            )
        }

        if looksLikeFitnessQuestion(text) {
            return TrainerChatResponse(
                reply: offlineFitnessReply(
                    text: text,
                    settings: settings,
                    goal: goal,
                    remaining: remaining,
                    exerciseCaloriesBurned: exerciseCaloriesBurned
                ),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: nil,
                suggested_exercise: nil
            )
        }

        return TrainerChatResponse(
            reply: offlineReply(mode: mode, messages: messages, consumed: consumed, goal: goal, phrases: phrases),
            replies: nil,
            suggested_goal: goal,
            suggested_meal: nil,
            suggested_exercise: nil
        )
    }

    private static func looksLikeExerciseLog(_ text: String) -> Bool {
        let triggers = [
            "i ran", "i run", "just ran", "went for a run", "went running",
            "i walked", "just walked", "went for a walk",
            "i biked", "i cycled", "went biking", "went cycling",
            "worked out", "i worked out", "just worked out", "hit the gym",
            "lifted weights", "i lifted", "did cardio", "did hiit",
            "swam", "i swam", "played basketball", "played soccer",
        ]
        guard triggers.contains(where: { text.contains($0) }) else { return false }
        return !looksLikeHypotheticalFood(text)
    }

    private static func offlineExerciseLogReply(for exercise: ExercisePayload) -> String {
        "Logged \(FoodItemNaming.stripDashes(exercise.name)). About \(Int(exercise.caloriesBurned)) calories burned. That's on the record. It doesn't add extra food to today's target."
    }

    private static func looksLikeConfirmedFoodLog(_ text: String) -> Bool {
        let triggers = [
            "i also had ", "i also ate ", "i also drank ", "also had ", "also ate ", "also drank ",
            "i had ", "i ate ", "i drank ", "i've had ", "ive had ", "i've drank ", "ive drank ",
            "just ate", "just had", "just drank", "already ate", "already had", "already drank",
            "log my ", "log this meal", "log this food", "log this drink", "add it to my log",
        ]
        return triggers.contains { text.contains($0) }
    }

    /// In-progress consumption: "I'm having Fairlife…" should log (or resolve on "log that").
    private static func looksLikeCurrentFoodConsumption(_ text: String) -> Bool {
        let triggers = [
            "i'm having ", "im having ", "i am having ",
            "i'm drinking ", "im drinking ", "i am drinking ",
            "i'm eating ", "im eating ", "i am eating ",
        ]
        return triggers.contains { text.contains($0) }
    }

    /// Typed chat and the mic share this lookup. Speech transcripts may still carry
    /// a trailing period or a one-letter miss ("Katalina", "Krunch") when they get here.
    static func resolveLoggedFood(from utterance: String) async -> FoodLookupOutcome {
        let spoken = FoodItemNaming.normalizedSpeechTranscript(utterance)
        let source = FoodItemNaming.foodMentionForLogging(from: spoken) ?? spoken
        return await FoodAnalysisService.resolveFoodLog(from: source)
    }

    /// When Larry omits MEAL_JSON — or re-logs an old meal on confirmation — fix locally.
    /// Also reconciles GPT MEAL_JSON so "3 eggs" never stores 1-egg calories.
    /// A spoken or typed food is resolved before it is returned, so the saved meal is not the 242 kcal placeholder.
    private static func applyAutoMealLogIfNeeded(
        _ response: TrainerChatResponse,
        messages: [ChatMessageDTO],
        mode: String
    ) async -> TrainerChatResponse {
        guard let lastUser = messages.last(where: { $0.role == "user" })?.content else { return response }
        let text = lastUser.lowercased()
        if FoodLogCorrection.looksLikeCorrection(lastUser) {
            // Chat view edits the existing row; do not attach a second meal.
            return TrainerChatResponse(
                reply: response.reply,
                replies: response.replies,
                suggested_goal: response.suggested_goal,
                suggested_meal: nil,
                suggested_exercise: response.suggested_exercise,
                clear_todays_log: response.clear_todays_log
            )
        }
        let contextFood = foodDescriptionFromContext(messages)

        // "log that" / "make sure you log that" → always use the latest food mention.
        // The model often re-emits an earlier meal (chicken/chips) instead of Fairlife.
        if looksLikeFoodConfirmation(text), let source = contextFood {
            let outcome = await resolveLoggedFood(from: source)
            let meal = FoodAnalysisService.applyUserStatedMacros(outcome.meal, from: lastUser)
            return responseByAttachingMeal(response, meal: meal, forceLogBubble: true)
        }

        if let gptMeal = response.suggested_meal {
            let completed = FoodAnalysisService.completingMissingFoods(gptMeal, from: lastUser)
            let portioned = FoodAnalysisService.applyingSpokenPortions(
                FoodAnalysisService.reconcileMealPayload(completed),
                utterance: lastUser
            )
            var meal = FoodAnalysisService.applyUserStatedMacros(portioned, from: lastUser)
            if meal.source != .userProvided, meal.source != .userLabel,
               let better = await loggedFoodReplacing(meal, utterance: lastUser) {
                meal = better
            }
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "E",
                location: "TrainerService.applyAutoMealLogIfNeeded",
                message: "reconciled model meal",
                data: [
                    "utterance": lastUser,
                    "gptCalories": gptMeal.calories,
                    "gptProtein": gptMeal.proteinG,
                    "gptSource": gptMeal.source.rawValue,
                    "finalCalories": meal.calories,
                    "finalProtein": meal.proteinG,
                    "finalCarbs": meal.carbsG,
                    "finalFat": meal.fatG,
                    "finalSource": meal.source.rawValue,
                ]
            )
            // #endregion
            // The model often stops after two foods (eggs + toast) and drops the rest of the sentence.
            if meal.entriesForLogging().count > gptMeal.entriesForLogging().count {
                return responseByAttachingMeal(response, meal: meal, forceLogBubble: true)
            }
            if meal != gptMeal {
                return TrainerChatResponse(
                    reply: spokenNutritionReply(for: meal, logged: true),
                    replies: nil,
                    suggested_goal: response.suggested_goal,
                    suggested_meal: meal,
                    suggested_exercise: response.suggested_exercise,
                    clear_todays_log: response.clear_todays_log
                )
            }
            return response
        }

        let shouldLog: Bool
        if looksLikeFoodConfirmation(text) {
            shouldLog = false
        } else {
            shouldLog = (looksLikeConfirmedFoodLog(text) || looksLikeCurrentFoodConsumption(text))
                && !looksLikeHypotheticalFood(text)
        }
        guard shouldLog else {
            if let spoken = await spokenBrandMeal(mode: mode, utterance: lastUser, text: text) {
                return responseByAttachingMeal(response, meal: spoken, forceLogBubble: false)
            }
            return response
        }

        let source = contextFood
            ?? FoodItemNaming.foodMentionForLogging(from: lastUser)
            ?? lastUser
        let outcome = await resolveLoggedFood(from: source)
        let meal = FoodAnalysisService.applyUserStatedMacros(outcome.meal, from: lastUser)
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "E",
            location: "TrainerService.applyAutoMealLogIfNeeded",
            message: "attached offline estimate because model sent no meal",
            data: [
                "source": source,
                "calories": meal.calories,
                "protein": meal.proteinG,
                "carbs": meal.carbsG,
                "fat": meal.fatG,
                "mealSource": meal.source.rawValue,
            ]
        )
        // #endregion
        return responseByAttachingMeal(response, meal: meal, forceLogBubble: false)
    }

    /// A real lookup replaces the offline 242 kcal guess. A miss leaves that guess alone.
    private static func loggedFoodReplacing(_ meal: MealPayload, utterance: String) async -> MealPayload? {
        let outcome = await resolveLoggedFood(from: utterance)
        let resolved = FoodAnalysisService.applyUserStatedMacros(outcome.meal, from: utterance)
        guard outcome.needsConfirmation || FoodAnalysisService.lookupShouldReplace(original: meal, resolved: resolved) else {
            return nil
        }
        return resolved
    }

    /// The mic often hears only the product name. That still logs, through the same resolver as typed food.
    private static func spokenBrandMeal(mode: String, utterance: String, text: String) async -> MealPayload? {
        guard mode == "voice" else { return nil }
        guard !text.contains("?") else { return nil }
        guard !looksLikeHypotheticalFood(text), !looksLikeFoodMacroQuery(text), !looksLikeMealSuggestion(text) else {
            return nil
        }
        let source = FoodItemNaming.foodMentionForLogging(from: utterance) ?? utterance
        guard BrandedFoodResolver.shouldSearchCatalog(source) else { return nil }
        let outcome = await resolveLoggedFood(from: utterance)
        guard outcome.meal.isLabelBacked || outcome.needsConfirmation else { return nil }
        return FoodAnalysisService.applyUserStatedMacros(outcome.meal, from: utterance)
    }

    private static func responseByAttachingMeal(
        _ response: TrainerChatResponse,
        meal: MealPayload,
        forceLogBubble: Bool
    ) -> TrainerChatResponse {
        if LarryJunkFood.goesStraightToTheThighs(meal.name)
            || meal.entriesForLogging().contains(where: { LarryJunkFood.goesStraightToTheThighs($0.name) }) {
            return TrainerChatResponse(
                reply: offlineLogReply(for: meal),
                replies: nil,
                suggested_goal: response.suggested_goal,
                suggested_meal: meal,
                suggested_exercise: response.suggested_exercise,
                clear_todays_log: response.clear_todays_log
            )
        }
        var replies = response.chatReplies
        let logBubble = offlineLogReply(for: meal)
        replies = replies.filter { !isPreviewLogPrompt($0) }
        let mentionsLogged = replies.contains { $0.localizedCaseInsensitiveContains("logged") }
        if forceLogBubble {
            // Drop wrong "Logged chicken/chips…" prose from the model; keep non-log chatter.
            replies = replies.filter { !$0.localizedCaseInsensitiveContains("logged") }
            replies.append(logBubble)
        } else if !mentionsLogged {
            replies.append(logBubble)
        }
        return TrainerChatResponse(
            reply: replies.first ?? logBubble,
            replies: replies.count > 1 ? replies : nil,
            suggested_goal: response.suggested_goal,
            suggested_meal: meal,
            suggested_exercise: response.suggested_exercise,
            clear_todays_log: response.clear_todays_log
        )
    }

    private static func isPreviewLogPrompt(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("if you eat it") || lower.contains("if you drink it")
            || lower.contains("say the word and i'll log")
    }

    private static func looksLikeHypotheticalFood(_ text: String) -> Bool {
        if looksLikeOpenMealAsk(text) { return false }
        let triggers = [
            "thinking about", "thinking of", "thought about",
            "considering", "wondering if",
            "will that be", "would that be", "should i eat", "should i have",
            "can i eat", "can i have", "could i eat", "could i have",
            "what if i eat", "what if i have", "what happens if",
            "want to have", "wanna have", "gonna have", "going to have",
            "plan to have", "planning on", "might have", "would it be ok",
            "good for my macro", "fit my macro", "is it ok if", "am i allowed",
        ]
        return triggers.contains { text.contains($0) }
    }

    private static func looksLikeFoodMacroQuery(_ text: String) -> Bool {
        if looksLikeConfirmedFoodLog(text) || looksLikeCurrentFoodConsumption(text) { return false }
        if looksLikeDailyMacroStatusQuestion(text) { return false }
        if FoodItemNaming.extractFoodReference(from: text) != nil { return true }
        let triggers = [
            "estimated macro", "estimate macro", "macros for a", "macros for an",
            "macro estimate", "how many calories in", "calories in a", "calories in an",
            "nutrition for a", "nutrition for an",
        ]
        guard triggers.contains(where: { text.contains($0) }) else { return false }
        return mentionsKnownFood(text)
    }

    private static func mentionsKnownFood(_ text: String) -> Bool {
        let foods = [
            "big mac", "bigmac", "burger", "mcdonald", "pizza", "fries",
            "egg", "chicken", "salmon", "fish", "yogurt", "toast", "bread",
            "rice", "salad", "twix", "twinkie", "candy", "donut", "doughnut",
            "fairlife", "fair life", "chocolate milk", "nesquik",
        ]
        return foods.contains { text.contains($0) }
    }

    private static func looksLikeFoodConfirmation(_ text: String) -> Bool {
        let triggers = [
            "log it", "log that", "yes log", "yeah log", "okay log", "ok log",
            "go ahead and log", "go ahead log", "i'm logging", "im logging",
            "add it", "count it", "yes add", "yeah add", "log them", "log those",
            "make sure you log", "please log", "log this",
        ]
        return triggers.contains { text.contains($0) }
    }

    private static func looksLikeDailyMacroStatusQuestion(_ text: String) -> Bool {
        let patterns = [
            "what are my macro", "what's my macro", "whats my macro",
            "how are my macro", "my macros today", "macros today",
            "how much have i eaten", "how much have i had",
        ]
        return patterns.contains { text.contains($0) }
    }

    /// Finds the most recent user message describing food (for "okay log it" follow-ups).
    private static func foodDescriptionFromContext(_ messages: [ChatMessageDTO]) -> String? {
        for msg in messages.reversed() where msg.role == "user" {
            let text = msg.content.lowercased()
            if looksLikeFoodConfirmation(text) { continue }
            if looksLikeHypotheticalFood(text)
                || looksLikeConfirmedFoodLog(text)
                || looksLikeCurrentFoodConsumption(text)
            {
                if let mention = FoodItemNaming.foodMentionForLogging(from: msg.content) {
                    return mention
                }
                return msg.content
            }
            // Bare product mentions ("fairlife chocolate milk one serving") still count.
            if (mentionsKnownFood(text) || FoodItemNaming.isBeverage(text)
                    || FoodItemNaming.extractFoodReference(from: msg.content) != nil),
               let mention = FoodItemNaming.foodMentionForLogging(from: msg.content),
               mention.count >= 4,
               !looksLikeDailyMacroStatusQuestion(text) {
                return mention
            }
        }
        return nil
    }

    private static func offlineLogReply(for meal: MealPayload) -> String {
        let entries = meal.entriesForLogging()
        if entries.contains(where: { LarryJunkFood.goesStraightToTheThighs($0.name) })
            || LarryJunkFood.goesStraightToTheThighs(meal.name) {
            let one = entries.first ?? meal
            let protein = Int(one.proteinG.rounded())
            let proteinUnit = protein == 1 ? "gram" : "grams"
            return "Logged. \(one.name), \(Int(one.calories.rounded())) calories and \(protein) \(proteinUnit) of protein. \(LarryJunkFood.thighLine)"
        }
        let sourceNote = meal.isLabelBacked ? " (Open Food Facts)" : ""
        if entries.count > 1 {
            let summary = entries.map { "\($0.name), about \(MacroTrackingEngine.displayCalories($0.calories)) calories" }.joined(separator: ". ")
            return "Logged \(entries.count) items\(sourceNote), baby. \(summary). Macros don't lie!"
        }
        return spokenNutritionReply(for: meal, logged: true, sourceNote: sourceNote)
    }

    /// States the saved macros. Drinks include carbs so a pint of beer is not described like a latte.
    private static func spokenNutritionReply(for meal: MealPayload, logged: Bool, sourceNote: String = "") -> String {
        let one = meal.entriesForLogging().first ?? meal
        let cal = Int(one.calories.rounded())
        let protein = Int(one.proteinG.rounded())
        let carbs = Int(one.carbsG.rounded())
        let fat = Int(one.fatG.rounded())
        let drink = FoodItemNaming.isBeverage(one.name) || FoodItemNaming.isBeverage(meal.name)
        if logged {
            if drink {
                return "Logged\(sourceNote). \(one.name), about \(cal) calories, \(protein) grams of protein, and \(carbs) grams of carbs. Liquid calories. That's not a protein win."
            }
            return "Logged it\(sourceNote), baby. \(one.name), about \(cal) calories and \(protein) grams of protein. Macros don't lie!"
        }
        return "About \(cal) calories, \(protein) grams of protein, \(carbs) grams of carbs, and \(fat) grams of fat."
    }

    private static func offlineHypotheticalReplies(
        estimate: MealPayload,
        remaining: MacroTotals?,
        utterance: String,
        consumed: MacroTotals,
        goal: MacroGoalPayload?
    ) -> [String] {
        let entry = estimate.entriesForLogging().first ?? estimate
        let cal = MacroTrackingEngine.displayCalories(entry.calories)
        let protein = MacroTrackingEngine.displayGrams(entry.proteinG)
        let fat = MacroTrackingEngine.displayGrams(entry.fatG)
        let lower = utterance.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let eatingClean = goal.map { hasEatenCleanToday(consumed: consumed, goal: $0, hour: hour) } ?? false

        var message: String
        if FoodItemNaming.isBeverage(lower) {
            let roast = liquidCaloriesRoast(for: lower, eatingClean: eatingClean)
            message = "About \(cal) calories, \(protein) grams of protein, \(MacroTrackingEngine.displayGrams(entry.carbsG)) grams of carbs, and \(fat) grams of fat. \(roast)"
        } else if isJunkFood(lower) {
            let roast = junkFoodRoast(eatingClean: eatingClean, utterance: lower)
            message = "About \(cal) calories, \(protein) grams of protein, \(MacroTrackingEngine.displayGrams(entry.carbsG)) grams of carbs, \(fat) grams of fat. \(roast)"
        } else if protein >= 20 {
            message = "About \(cal) calories, \(protein) grams of protein, \(fat) grams of fat. Real food. I suppose that's acceptable."
        } else {
            message = "About \(cal) calories, \(protein) grams of protein, \(fat) grams of fat. Not terrible, but make it count."
        }

        if let remaining {
            let afterCal = MacroTrackingEngine.displayCalories(remaining.calories - entry.calories)
            if afterCal >= 0 {
                message += " You'd still have about \(afterCal) calories left after."
            } else {
                message += " That'd put you about \(-afterCal) calories over today."
            }
        }

        message += " \(hypotheticalLogPrompt(for: lower))"
        return [message]
    }

    private static func hypotheticalLogPrompt(for text: String) -> String {
        if FoodItemNaming.isBeverage(text) {
            return "If you drink it, say the word and I'll log it, bitch."
        }
        return "If you eat it, say the word and I'll log it, bitch."
    }

    private static func liquidCaloriesRoast(for text: String, eatingClean: Bool) -> String {
        if isFattyDrink(text) {
            return junkFoodRoast(eatingClean: eatingClean)
        }
        if FoodItemNaming.isBeverage(text) {
            return "Liquid calories. Skinny or sugar-free is barely acceptable. Macros don't lie."
        }
        return junkFoodRoast(eatingClean: eatingClean)
    }

    private static func isFattyDrink(_ text: String) -> Bool {
        let fatty = [
            "frappuccino", "milkshake", "whole milk", "whip", "mocha", "breve",
            "cream", "bulletproof", "butter coffee",
        ]
        return fatty.contains { text.contains($0) }
    }

    private static func offlineFoodMacroQueryReplies(
        estimate: MealPayload,
        remaining: MacroTotals?,
        utterance: String,
        consumed: MacroTotals,
        goal: MacroGoalPayload?
    ) -> [String] {
        let entry = estimate.entriesForLogging().first ?? estimate
        let cal = MacroTrackingEngine.displayCalories(entry.calories)
        let protein = MacroTrackingEngine.displayGrams(entry.proteinG)
        let carbs = MacroTrackingEngine.displayGrams(entry.carbsG)
        let fat = MacroTrackingEngine.displayGrams(entry.fatG)
        let lower = utterance.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let eatingClean = goal.map { hasEatenCleanToday(consumed: consumed, goal: $0, hour: hour) } ?? false

        var message = "A \(entry.name) runs about ~\(cal) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat."

        if let remaining {
            let afterCal = MacroTrackingEngine.displayCalories(remaining.calories - entry.calories)
            if afterCal >= 0 {
                message += " That'd leave you ~\(afterCal) cal for the rest of today."
            } else {
                message += " That alone puts you ~\(-afterCal) cal over your plan."
            }
        }

        if isJunkFood(lower) {
            message += " \(junkFoodRoast(eatingClean: eatingClean, utterance: lower))"
        }

        return [message]
    }

    private static func junkFoodRoast(eatingClean: Bool, utterance: String = "") -> String {
        if LarryJunkFood.goesStraightToTheThighs(utterance) {
            return LarryJunkFood.thighLine
        }
        if eatingClean {
            return "You've been eating clean today. Don't blow it now. Let's not be a little bitch and destroy our gains!"
        }
        return "That's fattening junk that'll wreck your cut. Let's not be a little bitch and destroy our gains!"
    }

    /// True when it's late enough in the day and logged macros show disciplined eating.
    private static func hasEatenCleanToday(
        consumed: MacroTotals,
        goal: MacroGoalPayload,
        hour: Int = Calendar.current.component(.hour, from: Date())
    ) -> Bool {
        guard consumed.calories >= 300 else { return false }
        guard hour >= 15 else { return false }
        let calRatio = consumed.calories / max(goal.calories, 1)
        let proteinRatio = consumed.proteinG / max(goal.proteinG, 1)
        return calRatio >= 0.35 && calRatio <= 0.92 && proteinRatio >= 0.50
    }

    private static func isJunkFood(_ text: String) -> Bool {
        let junk = [
            "big mac", "bigmac", "mcdonald", "twix", "twinkie", "candy", "chocolate bar",
            "cookie", "donut", "doughnut", "chips", "soda", "ice cream", "pizza", "burger", "fries",
        ]
        return junk.contains { text.contains($0) }
    }

    /// Public so CoachChat can render dinner cards without waiting on the model.
    static func isOpenMealAsk(_ text: String) -> Bool {
        looksLikeOpenMealAsk(text.lowercased())
    }

    private static func looksLikeOpenMealAsk(_ text: String) -> Bool {
        if looksLikeConfirmedFoodLog(text) || looksLikeCurrentFoodConsumption(text) { return false }
        let asking = text.contains("what") || text.contains("should") || text.contains("recommend")
            || text.contains("idea") || text.contains("?")
        let mealTime = text.contains("dinner") || text.contains("tonight") || text.contains("for the night")
            || text.contains("breakfast") || text.contains("lunch") || text.contains("snack")
            || text.contains("brunch") || text.contains("dessert") || text.contains("sweet tooth")
        if asking && mealTime { return true }
        let triggers = [
            "what should i eat", "what can i eat", "what do i eat", "what to eat",
            "what should i have", "what can i have", "what do i have",
            "what's for dinner", "whats for dinner", "what for dinner",
            "what's for breakfast", "whats for breakfast", "what's for lunch", "whats for lunch",
            "what's for dessert", "whats for dessert", "what for dessert",
            "dinner idea", "breakfast idea", "lunch idea", "snack idea", "dessert idea",
            "ideas for dinner", "ideas for breakfast", "ideas for lunch", "ideas for dessert",
            "meal idea", "meal suggestion",
            "eat tonight", "for dinner tonight", "dinner tonight", "for the night",
            "what else", "still eat", "hungry",
        ]
        return triggers.contains { text.contains($0) }
    }

    private static func looksLikeMealSuggestion(_ text: String) -> Bool {
        looksLikeOpenMealAsk(text)
    }

    enum MealSlot: Equatable {
        case breakfast
        case lunch
        case dinner
        case snack
        case dessert
        case general

        var optionsLabel: String {
            switch self {
            case .breakfast: return "Breakfast options"
            case .lunch: return "Lunch options"
            case .dinner: return "Dinner options"
            case .snack: return "Snack options"
            case .dessert: return "Dessert options that won't bury your cut"
            case .general: return "Meal options"
            }
        }
    }

    struct DinnerPlate: Identifiable, Equatable {
        let id: String
        let name: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int

        init(name: String, calories: Int, protein: Int, carbs: Int, fat: Int) {
            self.id = name
            self.name = name
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }
    }

    struct MealSuggestionPack: Equatable {
        let header: String
        let spoken: String
        let plates: [DinnerPlate]
        let slot: MealSlot

        /// Kept for older call sites that still check evening.
        var evening: Bool { slot == .dinner }
    }

    static func mealSlot(for utterance: String, hour: Int = Calendar.current.component(.hour, from: Date())) -> MealSlot {
        let text = utterance.lowercased()
        if text.contains("dessert") || text.contains("sweet tooth") || text.contains("something sweet") {
            return .dessert
        }
        if text.contains("breakfast") || text.contains("brunch") { return .breakfast }
        if text.contains("lunch") { return .lunch }
        if text.contains("snack") { return .snack }
        if text.contains("dinner") || text.contains("tonight") || text.contains("for the night") {
            return .dinner
        }
        switch hour {
        case 0..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        default: return .dinner
        }
    }

    static func mealSuggestionPack(
        remaining: MacroTotals,
        goal: MacroGoalPayload,
        utterance: String
    ) -> MealSuggestionPack {
        let caloriesLeft = max(Int(remaining.calories.rounded()), 0)
        let proteinLeft = max(Int(remaining.proteinG.rounded()), 0)
        let slot = mealSlot(for: utterance)
        let catalog = plates(for: slot)
        let calorieSlack = slot == .dessert || slot == .snack ? 20 : 40
        var fits = catalog.filter { $0.calories <= caloriesLeft + calorieSlack }
        if fits.count < 2 {
            fits = catalog.filter { $0.calories <= max(caloriesLeft, 120) + calorieSlack }.sorted { $0.calories < $1.calories }
        }
        let chosen = Array(fits.prefix(3))
        if chosen.isEmpty {
            let spoken = larryMealEmptyLine(slot: slot, caloriesLeft: caloriesLeft, proteinLeft: proteinLeft)
            return MealSuggestionPack(header: spoken, spoken: spoken, plates: [], slot: slot)
        }
        let header = larryMealHeader(slot: slot, caloriesLeft: caloriesLeft, proteinLeft: proteinLeft)
        let spoken = "\(header) Pick one and say you're having it. I'll log it. Macros don't lie."
        return MealSuggestionPack(header: header, spoken: spoken, plates: chosen, slot: slot)
    }

    private static func larryMealHeader(slot: MealSlot, caloriesLeft: Int, proteinLeft: Int) -> String {
        let bank: [String]
        switch slot {
        case .breakfast:
            bank = [
                "Breakfast. Not brunch chaos. You've got about \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Eat like you mean it.",
                "Morning fuel. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Let's stop being a little bitch and start counting our macros!",
            ]
        case .lunch:
            bank = [
                "Lunch. Midday. No excuses. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Hit protein or I get loud.",
                "About \(caloriesLeft) calories and \(proteinLeft) grams of protein left for lunch. Real food. Your grandma didn't skip leg day.",
            ]
        case .dinner:
            bank = [
                "Dinner. Finish strong. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Don't blow it now.",
                "Night meal. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Discipline tastes better than regret, baby.",
            ]
        case .snack:
            bank = [
                "Snack. Keep it tight. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Don't turn this into a buffet.",
                "About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. A snack, not a second dinner. Macros don't lie.",
            ]
        case .dessert:
            bank = [
                "Dessert. Fine. But we're doing it my way. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. No Twinkies. Let's not be a little bitch and destroy our gains!",
                "You want something sweet. I want you to keep your cut. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. These desserts still work for macros.",
            ]
        case .general:
            bank = [
                "About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. Whole foods. No junk. Pick something that doesn't embarrass me.",
            ]
        }
        return bank.randomElement() ?? bank[0]
    }

    private static func larryMealEmptyLine(slot: MealSlot, caloriesLeft: Int, proteinLeft: Int) -> String {
        if slot == .dessert {
            return "Dessert? With \(caloriesLeft) calories left? You're out of runway. Water, black coffee, or brush your teeth and call it a night. Macros don't lie."
        }
        return "You're cooked on calories. About \(caloriesLeft) calories and \(proteinLeft) grams of protein left. If you still eat, keep it tiny. Discipline tastes better than regret, baby."
    }

    private static func leanMealSuggestions(remaining: MacroTotals, goal: MacroGoalPayload, utterance: String) -> String {
        mealSuggestionPack(remaining: remaining, goal: goal, utterance: utterance).spoken
    }

    private static func plates(for slot: MealSlot) -> [DinnerPlate] {
        switch slot {
        case .breakfast: return breakfastPlates
        case .lunch: return lunchPlates
        case .dinner: return dinnerPlates
        case .snack: return snackPlates
        case .dessert: return dessertPlates
        case .general: return lunchPlates
        }
    }

    private static let breakfastPlates: [DinnerPlate] = [
        DinnerPlate(name: "Egg white scramble with spinach and turkey sausage", calories: 320, protein: 38, carbs: 8, fat: 12),
        DinnerPlate(name: "Greek yogurt, berries, and a scoop of whey", calories: 280, protein: 40, carbs: 22, fat: 4),
        DinnerPlate(name: "Overnight oats with egg whites and banana", calories: 360, protein: 28, carbs: 48, fat: 6),
        DinnerPlate(name: "Two eggs, egg whites, and Dave's toast", calories: 340, protein: 30, carbs: 24, fat: 14),
        DinnerPlate(name: "Nonfat cottage cheese with pineapple", calories: 200, protein: 26, carbs: 18, fat: 2),
    ]

    private static let lunchPlates: [DinnerPlate] = [
        DinnerPlate(name: "Grilled chicken and a big salad", calories: 420, protein: 48, carbs: 12, fat: 14),
        DinnerPlate(name: "Turkey wrap with veggies, no mayo", calories: 380, protein: 36, carbs: 34, fat: 10),
        DinnerPlate(name: "Tuna on rice cakes with cucumber", calories: 300, protein: 32, carbs: 28, fat: 6),
        DinnerPlate(name: "Lean ground turkey, rice, and broccoli", calories: 450, protein: 42, carbs: 40, fat: 12),
        DinnerPlate(name: "Chicken breast and sweet potato", calories: 400, protein: 46, carbs: 36, fat: 6),
    ]

    private static let dinnerPlates: [DinnerPlate] = [
        DinnerPlate(name: "Grilled chicken, broccoli, and rice", calories: 540, protein: 54, carbs: 48, fat: 8),
        DinnerPlate(name: "Salmon, a salad, and a small potato", calories: 610, protein: 40, carbs: 32, fat: 28),
        DinnerPlate(name: "A turkey burger with no bun and roasted vegetables", calories: 400, protein: 46, carbs: 14, fat: 16),
        DinnerPlate(name: "Shrimp, vegetables, and a half cup of rice", calories: 380, protein: 42, carbs: 28, fat: 8),
        DinnerPlate(name: "Nonfat cottage cheese with cucumber and berries", calories: 220, protein: 28, carbs: 16, fat: 3),
    ]

    private static let snackPlates: [DinnerPlate] = [
        DinnerPlate(name: "Greek yogurt with berries", calories: 180, protein: 20, carbs: 18, fat: 2),
        DinnerPlate(name: "Nonfat cottage cheese with cucumber", calories: 140, protein: 22, carbs: 8, fat: 2),
        DinnerPlate(name: "A Fairlife protein shake", calories: 150, protein: 30, carbs: 4, fat: 2),
        DinnerPlate(name: "Turkey slices and an apple", calories: 200, protein: 24, carbs: 22, fat: 3),
        DinnerPlate(name: "Egg whites and a rice cake", calories: 120, protein: 16, carbs: 12, fat: 0),
    ]

    private static let dessertPlates: [DinnerPlate] = [
        DinnerPlate(name: "Greek yogurt with cocoa powder and berries", calories: 190, protein: 20, carbs: 22, fat: 2),
        DinnerPlate(name: "Protein pudding with a few strawberries", calories: 170, protein: 25, carbs: 12, fat: 3),
        DinnerPlate(name: "Frozen banana blended with whey and ice", calories: 210, protein: 24, carbs: 26, fat: 2),
        DinnerPlate(name: "Nonfat cottage cheese whipped with cinnamon and berries", calories: 160, protein: 24, carbs: 14, fat: 2),
        DinnerPlate(name: "Sugar-free jello with a scoop of casein", calories: 130, protein: 24, carbs: 6, fat: 1),
    ]

    private static func offlineReply(
        mode: String,
        messages: [ChatMessageDTO],
        consumed: MacroTotals,
        goal: MacroGoalPayload?,
        phrases: [String]
    ) -> String {
        if let lastUser = messages.last(where: { $0.role == "user" })?.content {
            let text = lastUser.lowercased()

            if text.contains("tired") || text.contains("hard") || text.contains("bitch") || text.contains("hate") {
                return "Listen. Rough days happen. Your grandma didn't skip leg day, and neither do we. Hit protein when you can, log what you can. You showed up. That counts, baby."
            }
            if (text.contains("macro") || text.contains("protein") || text.contains("calorie"))
                && !looksLikeFoodMacroQuery(text) && !looksLikeHypotheticalFood(text) {
                if let goal {
                    return "Alright. Macros don't lie. People do. Plan today is about \(MacroTrackingEngine.displayCalories(goal.calories)) calories and \(MacroTrackingEngine.displayGrams(goal.proteinG)) grams of protein. You've logged \(MacroTrackingEngine.displayCalories(consumed.calories)) so far. Let's stop being a little bitch and start counting!"
                }
            }
            if text.contains("eat") || text.contains("food") || text.contains("hungry") {
                return "Protein-forward and simple wins. Eggs, chicken, Greek yogurt. Real food, baby. Log it and we adjust from there. Discipline tastes better than regret."
            }
            if text.contains("thank") {
                return "Yeah, yeah. Now go drink some water."
            }
        }

        if let phrase = phrases.randomElement(), !phrase.isEmpty, mode != "morning" {
            return phrase
        }

        if mode == "voice" {
            if let goal {
                return "Larry here, offline. Fact one: target ~\(MacroTrackingEngine.displayCalories(goal.calories)) calories and \(MacroTrackingEngine.displayGrams(goal.proteinG)) grams protein today. Fact two: you've logged \(MacroTrackingEngine.displayCalories(consumed.calories)) calories and \(MacroTrackingEngine.displayGrams(consumed.proteinG)) grams protein so far. Tap the mic and keep talking, baby."
            }
            return "Larry McQuade, offline. Log a meal so I can hit you with real macro numbers."
        }

        if mode == "morning" || mode == "chat" {
            if let goal {
                return "What's up! Larry McQuade here, offline, but I'm still watching. Targets today: about \(MacroTrackingEngine.displayCalories(goal.calories)) calories and \(MacroTrackingEngine.displayGrams(goal.proteinG)) grams of protein. What do you need?"
            }
            return LarryMcQuade.tagline + " What's on your mind?"
        }

        if consumed.proteinG < 50 {
            return "Your grandma didn't skip leg day. And your muscles are sending a strongly worded email about protein."
        }
        return "Fine. You're logging. Don't get comfortable. Macros don't lie."
    }
}
