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

    init(
        reply: String,
        replies: [String]?,
        suggested_goal: MacroGoalPayload?,
        suggested_meal: MealPayload?,
        suggested_exercise: ExercisePayload? = nil
    ) {
        self.reply = reply
        self.replies = replies
        self.suggested_goal = suggested_goal
        self.suggested_meal = suggested_meal
        self.suggested_exercise = suggested_exercise
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = try c.decode(String.self, forKey: .reply)
        replies = try c.decodeIfPresent([String].self, forKey: .replies)
        suggested_goal = try c.decodeIfPresent(MacroGoalPayload.self, forKey: .suggested_goal)
        suggested_meal = try c.decodeIfPresent(MealPayload.self, forKey: .suggested_meal)
        suggested_exercise = try c.decodeIfPresent(ExercisePayload.self, forKey: .suggested_exercise)
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
            .filter { !$0.isEmpty }
    }

    /// Removes backend-only MEAL_JSON / GOAL_JSON / EXERCISE_JSON blocks from user-facing text.
    private static func stripStructuredBlocks(_ text: String) -> String {
        var result = text
        for prefix in ["MEAL_JSON:", "GOAL_JSON:", "EXERCISE_JSON:"] {
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
        weightKg: Double = 75
    ) async -> TrainerChatResponse {
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
                weightKg: weightKg
            )
        } catch {
            return applyAutoMealLogIfNeeded(
                offlineResponse(
                    mode: mode,
                    messages: messages,
                    consumed: consumed,
                    goal: goal,
                    remaining: remaining,
                    phrases: phrases,
                    weightKg: weightKg
                ),
                messages: messages
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
        weightKg: Double = 75
    ) async throws -> TrainerChatResponse {
        guard AppConfig.hasBackend else {
            return offlineResponse(
                mode: mode,
                messages: messages,
                consumed: consumed,
                goal: goal,
                remaining: remaining,
                phrases: phrases,
                weightKg: weightKg
            )
        }

        let remainingPayload = remaining ?? (goal.map {
            DaySummaryService.remaining(consumed: consumed, goal: $0)
        })

        let context: [String: Any] = [
            "trainer_voice": trainerVoice,
            "phrases": phrases,
            "goal": goal.map { goalDict($0) } as Any,
            "consumed": macroDict(consumed),
            "remaining": remainingPayload.map { macroDict($0) } as Any,
            "coach_philosophy": GoalCalculator.leanCoachPhilosophy,
            "goal_type": goalType ?? "lose",
            "local_hour": Calendar.current.component(.hour, from: Date()),
            "eating_clean_today": goal.map { hasEatenCleanToday(consumed: consumed, goal: $0) } ?? false,
            "exercise_calories_burned": exerciseCaloriesBurned,
            "weight_kg": weightKg,
        ]

        let body: [String: Any] = [
            "mode": mode,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "context": context,
        ]

        let data = try await SupabaseService.shared.invokeFunction(name: "trainer-chat", body: body)
        let response = try parseChatResponse(data)
        return applyAutoMealLogIfNeeded(response, messages: messages)
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
        }
        let partial = try JSONDecoder().decode(Partial.self, from: data)
        return TrainerChatResponse(
            reply: partial.reply,
            replies: partial.replies,
            suggested_goal: partial.suggested_goal,
            suggested_meal: partial.suggested_meal,
            suggested_exercise: partial.suggested_exercise
        )
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
        weightKg: Double = 75
    ) -> TrainerChatResponse {
        let lastUser = messages.last(where: { $0.role == "user" })?.content ?? ""
        let text = lastUser.lowercased()
        var suggestedMeal: MealPayload?

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
            let source = FoodItemNaming.loggedFoodDescription(from: raw) ?? raw
            suggestedMeal = FoodAnalysisService.estimateOffline(from: source)
            return TrainerChatResponse(
                reply: offlineLogReply(for: suggestedMeal!),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: suggestedMeal,
                suggested_exercise: nil
            )
        }

        if looksLikeConfirmedFoodLog(text) {
            let source = FoodItemNaming.loggedFoodDescription(from: lastUser) ?? lastUser
            suggestedMeal = FoodAnalysisService.estimateOffline(from: source)
            return TrainerChatResponse(
                reply: offlineLogReply(for: suggestedMeal!),
                replies: nil,
                suggested_goal: goal,
                suggested_meal: suggestedMeal,
                suggested_exercise: nil
            )
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

        if looksLikeMealSuggestion(text), let goal, let remaining {
            let reply = leanMealSuggestions(remaining: remaining, goal: goal)
            return TrainerChatResponse(reply: reply, replies: nil, suggested_goal: goal, suggested_meal: nil, suggested_exercise: nil)
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
        "Logged — \(exercise.name): ~\(Int(exercise.caloriesBurned)) cal burned. That's +\(Int(exercise.caloriesBurned)) on your target. Earn your food."
    }

    private static func looksLikeConfirmedFoodLog(_ text: String) -> Bool {
        let triggers = [
            "i had ", "i ate ", "i drank ", "i've had ", "ive had ", "i've drank ", "ive drank ",
            "just ate", "just had", "just drank", "already ate", "already had", "already drank",
            "log my ", "log this meal", "log this food", "log this drink", "add it to my log",
        ]
        return triggers.contains { text.contains($0) }
    }

    /// When Larry omits MEAL_JSON but the user already ate/drank something, log locally.
    private static func applyAutoMealLogIfNeeded(
        _ response: TrainerChatResponse,
        messages: [ChatMessageDTO]
    ) -> TrainerChatResponse {
        guard response.suggested_meal == nil else { return response }
        guard let lastUser = messages.last(where: { $0.role == "user" })?.content else { return response }
        let text = lastUser.lowercased()

        let shouldLog: Bool
        if looksLikeFoodConfirmation(text) {
            shouldLog = foodDescriptionFromContext(messages) != nil
        } else {
            shouldLog = looksLikeConfirmedFoodLog(text) && !looksLikeHypotheticalFood(text)
        }
        guard shouldLog else { return response }

        let source = foodDescriptionFromContext(messages)
            ?? FoodItemNaming.loggedFoodDescription(from: lastUser)
            ?? lastUser
        let meal = FoodAnalysisService.estimateOffline(from: source)
        var replies = response.chatReplies
        let logBubble = offlineLogReply(for: meal)
        replies = replies.filter { !isPreviewLogPrompt($0) }
        if !replies.contains(where: { $0.localizedCaseInsensitiveContains("logged") }) {
            replies.append(logBubble)
        }
        return TrainerChatResponse(
            reply: replies.first ?? logBubble,
            replies: replies.count > 1 ? replies : nil,
            suggested_goal: response.suggested_goal,
            suggested_meal: meal,
            suggested_exercise: response.suggested_exercise
        )
    }

    private static func isPreviewLogPrompt(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("if you eat it") || lower.contains("if you drink it")
            || lower.contains("say the word and i'll log")
    }

    private static func looksLikeHypotheticalFood(_ text: String) -> Bool {
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
        if looksLikeConfirmedFoodLog(text) { return false }
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
            "rice", "salad", "twix", "candy", "donut", "doughnut",
        ]
        return foods.contains { text.contains($0) }
    }

    private static func looksLikeFoodConfirmation(_ text: String) -> Bool {
        let triggers = [
            "log it", "log that", "yes log", "yeah log", "okay log", "ok log",
            "go ahead and log", "go ahead log", "i'm logging", "im logging",
            "add it", "count it", "yes add", "yeah add", "log them", "log those",
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
            if looksLikeHypotheticalFood(text) || looksLikeConfirmedFoodLog(text) {
                if let logged = FoodItemNaming.loggedFoodDescription(from: msg.content) {
                    return logged
                }
                return msg.content
            }
        }
        return nil
    }

    private static func offlineLogReply(for meal: MealPayload) -> String {
        let entries = meal.entriesForLogging()
        let sourceNote = meal.isLabelBacked ? " (Open Food Facts)" : ""
        if entries.count > 1 {
            let summary = entries.map { "\($0.name): ~\(Int($0.calories)) cal" }.joined(separator: " · ")
            return "Logged \(entries.count) items\(sourceNote), baby — \(summary). Macros don't lie!"
        }
        let one = entries.first ?? meal
        return "Logged it\(sourceNote), baby — \(one.name): ~\(Int(one.calories)) cal, \(Int(one.proteinG))g protein. Macros don't lie!"
    }

    private static func offlineHypotheticalReplies(
        estimate: MealPayload,
        remaining: MacroTotals?,
        utterance: String,
        consumed: MacroTotals,
        goal: MacroGoalPayload?
    ) -> [String] {
        let entry = estimate.entriesForLogging().first ?? estimate
        let cal = Int(entry.calories)
        let protein = Int(entry.proteinG)
        let fat = Int(entry.fatG)
        let lower = utterance.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let eatingClean = goal.map { hasEatenCleanToday(consumed: consumed, goal: $0, hour: hour) } ?? false

        var message1: String
        if FoodItemNaming.isBeverage(lower) {
            let roast = liquidCaloriesRoast(for: lower, eatingClean: eatingClean)
            message1 = "~\(cal) cal for \(protein)g protein and \(fat)g fat — \(roast)"
        } else if isJunkFood(lower) {
            let roast = junkFoodRoast(eatingClean: eatingClean)
            message1 = "~\(cal) cal, \(protein)g protein, \(Int(entry.carbsG))g carbs, \(fat)g fat — \(roast)"
        } else if protein >= 20 {
            message1 = "~\(cal) cal, \(protein)g protein, \(fat)g fat — real food. I suppose that's acceptable."
        } else {
            message1 = "~\(cal) cal, \(protein)g protein, \(fat)g fat — not terrible, but make it count."
        }

        if let remaining {
            let afterCal = Int(remaining.calories - entry.calories)
            if afterCal >= 0 {
                message1 += " You'd still have ~\(afterCal) cal left after."
            } else {
                message1 += " That'd put you ~\(-afterCal) cal over today."
            }
        }

        let message2 = hypotheticalLogPrompt(for: lower)
        return [message1, message2]
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
            return "Liquid calories — skinny or sugar-free is barely acceptable. Macros don't lie."
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
        let cal = Int(entry.calories)
        let protein = Int(entry.proteinG)
        let carbs = Int(entry.carbsG)
        let fat = Int(entry.fatG)
        let lower = utterance.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let eatingClean = goal.map { hasEatenCleanToday(consumed: consumed, goal: $0, hour: hour) } ?? false

        var message = "A \(entry.name) runs about ~\(cal) cal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat."

        if let remaining {
            let afterCal = Int(remaining.calories - entry.calories)
            if afterCal >= 0 {
                message += " That'd leave you ~\(afterCal) cal for the rest of today."
            } else {
                message += " That alone puts you ~\(-afterCal) cal over your plan."
            }
        }

        if isJunkFood(lower) {
            message += " \(junkFoodRoast(eatingClean: eatingClean))"
        }

        return [message]
    }

    private static func junkFoodRoast(eatingClean: Bool) -> String {
        if eatingClean {
            return "You've been eating clean today — don't blow it now. Let's not be a little bitch and destroy our gains!"
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
            "big mac", "bigmac", "mcdonald", "twix", "candy", "chocolate bar",
            "cookie", "donut", "doughnut", "chips", "soda", "ice cream", "pizza", "burger", "fries",
        ]
        return junk.contains { text.contains($0) }
    }

    private static func looksLikeMealSuggestion(_ text: String) -> Bool {
        let triggers = [
            "what else", "what can i eat", "what should i eat", "what to eat",
            "meal idea", "meal suggestion", "hungry", "snack idea", "still eat",
        ]
        return triggers.contains { text.contains($0) }
    }

    private static func leanMealSuggestions(remaining: MacroTotals, goal: MacroGoalPayload) -> String {
        let cal = Int(remaining.calories)
        let protein = Int(remaining.proteinG)
        var options: [String] = []

        if remaining.proteinG >= 25 {
            options.append("grilled chicken or fish with roasted veggies (~\(min(400, cal)) cal, high protein)")
        }
        if remaining.proteinG >= 15 {
            options.append("Greek yogurt with berries (~\(min(250, cal)) cal)")
        }
        if remaining.calories >= 300 {
            options.append("egg whites + whole eggs scramble with spinach (~\(min(350, cal)) cal)")
        }
        if options.isEmpty {
            options.append("a lean protein shake or cottage cheese to close your protein gap")
        }

        let list = options.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
        return "You've got ~\(cal) cal and \(protein)g protein left today. Murphy/Gaver style — whole foods, no junk: \(list). Discipline tastes better than regret, baby."
    }

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
                return "Listen — rough days happen. Your grandma didn't skip leg day, and neither do we. Hit protein when you can, log what you can. You showed up. That counts, baby."
            }
            if (text.contains("macro") || text.contains("protein") || text.contains("calorie"))
                && !looksLikeFoodMacroQuery(text) && !looksLikeHypotheticalFood(text) {
                if let goal {
                    return "Alright, macros don't lie — people do. Your plan today: ~\(Int(goal.calories)) cal, \(Int(goal.proteinG))g protein, \(Int(goal.carbsG))g carbs, \(Int(goal.fatG))g fat. So far you've logged \(Int(consumed.calories)) cal. Let's stop being a little bitch and start counting!"
                }
            }
            if text.contains("eat") || text.contains("food") || text.contains("hungry") {
                return "Protein-forward and simple wins: eggs, chicken, Greek yogurt — real food, baby. Log it and we adjust from there. Discipline tastes better than regret."
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
                return "Larry here, offline. Fact one: target ~\(Int(goal.calories)) calories and \(Int(goal.proteinG)) grams protein today. Fact two: you've logged \(Int(consumed.calories)) calories and \(Int(consumed.proteinG)) grams protein so far. Tap the mic and keep talking, baby."
            }
            return "Larry McQuade, offline. Log a meal so I can hit you with real macro numbers."
        }

        if mode == "morning" || mode == "chat" {
            if let goal {
                return "What's up! Larry McQuade here — offline mode, but I'm still watching. Your targets: ~\(Int(goal.calories)) cal and \(Int(goal.proteinG))g protein today. What do you need?"
            }
            return LarryMcQuade.tagline + " What's on your mind?"
        }

        if consumed.proteinG < 50 {
            return "Your grandma didn't skip leg day — and your muscles are sending a strongly worded email about protein."
        }
        return "Fine. You're logging. Don't get comfortable — macros don't lie."
    }
}
