import Foundation

/// How Larry looks and moves. Separate from the nutrition score so chat
/// can share the same faces without a meal attached.
enum LarryEmotion: String, Equatable, CaseIterable {
    case excited
    case confident
    case neutral
    case skeptical
    case disappointed
    case shocked
    case encouraging

    static func forCategory(_ category: LarryReactionCategory) -> LarryEmotion {
        switch category {
        case .great: return .excited
        case .good: return .confident
        case .neutral: return .neutral
        case .questionable: return .skeptical
        case .bad: return .disappointed
        case .disaster: return .shocked
        }
    }

    /// Poses already in the asset catalog. Order is the rotation order.
    var poses: [LarryVoicePose] {
        switch self {
        case .excited:
            return [.cheering, .thumbsUp, .flex]
        case .confident:
            return [.thumbsUp, .pointing, .flex]
        case .neutral:
            return [.zen, .idle, .talking]
        case .skeptical:
            return [.skeptical, .scowl, .stern]
        case .disappointed:
            return [.sigh, .disappointed, .reject]
        case .shocked:
            return [.disbelief, .surprised, .yell]
        case .encouraging:
            return [.sincere, .pointing, .veggies]
        }
    }

    /// Reads the tone of something Larry (or the user) just said.
    /// Empty or generic copy stays neutral instead of defaulting to a grin.
    static func fromReply(_ text: String) -> LarryEmotion {
        detected(in: text) ?? .neutral
    }

    static func detected(in text: String) -> LarryEmotion? {
        let normalized = text.lowercased()
        guard normalized.count >= 3 else { return nil }

        var best: LarryEmotion?
        var bestScore = 1
        for (emotion, phrases) in signals {
            let score = phrases.reduce(0) { partial, item in
                partial + (containsPhrase(normalized, item.phrase) ? item.weight : 0)
            }
            if score > bestScore {
                bestScore = score
                best = emotion
            }
        }
        return best
    }

    private static let signals: [(LarryEmotion, [(phrase: String, weight: Int)])] = [
        (.shocked, [
            ("good lord", 6),
            ("put the fork", 6),
            ("bigger calorie", 6),
            ("budget is on fire", 5),
            ("are you kidding", 5),
            ("oh my god", 5),
            ("what the", 4),
            ("no way", 3),
            ("hold on", 3),
            ("didn't catch", 3),
        ]),
        (.disappointed, [
            ("straight to your thighs", 6),
            ("what are we doing", 6),
            ("did not train", 6),
            ("currently screaming", 5),
            ("that one hurt", 4),
            ("off the plan", 4),
            ("come on", 3),
        ]),
        (.skeptical, [
            ("interesting strategy", 6),
            ("bold move", 5),
            ("have questions", 5),
            ("lotta calories", 5),
            ("i'm watching", 4),
            ("watching you", 4),
            ("you sure", 3),
        ]),
        (.excited, [
            ("hell yeah", 6),
            ("that's what i'm talking", 6),
            ("protein acquired", 5),
            ("now we're building", 5),
            ("that's a win", 4),
            ("let's go", 4),
        ]),
        (.encouraging, [
            ("you got this", 5),
            ("little bitch", 4),
            ("lock in", 4),
            ("don't quit", 4),
            ("real talk", 4),
            ("grandma", 3),
            ("discipline", 3),
            ("we can fix", 3),
            ("keep going", 3),
        ]),
        (.confident, [
            ("not flashy", 5),
            ("keep the train", 4),
            ("good call", 4),
            ("on track", 3),
            ("not terrible", 3),
            ("acceptable", 3),
            ("solid.", 3),
            ("solid ", 3),
            ("respectable", 3),
        ]),
        (.neutral, [
            ("i've seen worse", 5),
            ("we'll allow", 5),
            ("allow it", 4),
            ("not a win", 4),
            ("macros shrugged", 4),
            ("i suppose", 3),
            ("alright", 2),
        ]),
    ]

    private static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        text.contains(phrase)
    }
}

/// Picks a catalog pose for an emotion. Dessert artwork is only a costume
/// for a reaction that was already negative — it never decides the score.
enum LarryPoseSelector {
    static func pose(for emotion: LarryEmotion, seed: Int, flavorText: String = "") -> LarryVoicePose {
        let pool = flavoredPoses(for: emotion, flavorText: flavorText)
        guard !pool.isEmpty else { return .talking }
        return pool[index(seed: seed, count: pool.count)]
    }

    static func seed(for text: String) -> Int {
        text.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    }

    private static func flavoredPoses(for emotion: LarryEmotion, flavorText: String) -> [LarryVoicePose] {
        guard LarryVoicePose.mentionsDessert(flavorText) else { return emotion.poses }
        switch emotion {
        case .skeptical:
            return [.donutGlare, .skeptical, .scowl]
        case .disappointed:
            return [.donut, .sigh, .disappointed]
        case .shocked:
            return [.donutShock, .donutCrush, .disbelief]
        default:
            return emotion.poses
        }
    }

    private static func index(seed: Int, count: Int) -> Int {
        let mixed = seed == Int.min ? 0 : abs(seed)
        return mixed % count
    }
}
