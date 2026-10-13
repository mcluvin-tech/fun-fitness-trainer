import Foundation

/// The finished reaction: score, face, line, and motion, already chosen.
struct LarryReactionPresentation: Equatable {
    var category: LarryReactionCategory
    var emotion: LarryEmotion
    var quote: String
    var pose: LarryVoicePose
    var motion: LarryReactionMotion
}

/// Wires the judge, the emotion, the quote bank, and the motion together
/// so the confirmation screen only has to draw the result.
/// Snack cakes Larry refuses to score as a win, even when the day still has calorie room.
enum LarryJunkFood {
    static let thighLine = "That's going straight to your thighs."

    static func goesStraightToTheThighs(_ name: String) -> Bool {
        name.lowercased().contains("twinkie")
    }
}

enum LarryReactionComposer {
    static func present(snapshot: LarryReactionSnapshot) -> LarryReactionPresentation {
        let macroCategory = LarryNutritionJudge.category(
            delta: snapshot.delta,
            previous: snapshot.previousConsumed,
            goal: snapshot.goal
        )
        let junk = LarryJunkFood.goesStraightToTheThighs(snapshot.mealName)
        let category: LarryReactionCategory = junk
            ? (macroCategory == .disaster ? .disaster : .bad)
            : macroCategory
        let emotion = LarryEmotion.forCategory(category)
        let rawQuote = junk ? LarryJunkFood.thighLine : LarryQuoteMemory.pick(for: category)
        let quote = LarrySpeechStyle.clean(rawQuote)
        let seed = LarryPoseSelector.seed(for: snapshot.mealName + snapshot.id.uuidString)
        let pose = LarryPoseSelector.pose(for: emotion, seed: seed, flavorText: snapshot.mealName)
        return LarryReactionPresentation(
            category: category,
            emotion: emotion,
            quote: quote,
            pose: pose,
            motion: LarryReactionMotion.forEmotion(emotion)
        )
    }
}
