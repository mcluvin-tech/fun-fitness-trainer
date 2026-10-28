import Foundation

/// Larry's one-liners, grouped by how the meal landed.
/// A picker walks the pool before it repeats a line.
enum LarryQuoteBank {
    static func lines(for category: LarryReactionCategory) -> [String] {
        switch category {
        case .great:
            return [
                "HELL YEAH. That's what I'm talking about.",
                "Protein acquired. Larry approves.",
                "Now we're building something, brother.",
                "That's how you feed the machine.",
                "The macros just nodded. Don't get cocky.",
                "Locked in. That's the good stuff.",
            ]
        case .good:
            return [
                "Solid. Keep the train moving.",
                "Not flashy. Effective.",
                "I'll take it. Do it again.",
                "Clean enough. Stay there.",
                "That one earns a spot on the log.",
                "Respectable. Larry's still watching.",
            ]
        case .neutral:
            return [
                "I've seen worse decisions.",
                "We'll allow it.",
                "Fine. But I'm watching you.",
                "Not a win. Not a crime.",
                "Logged. The macros shrugged.",
                "Alright. Nobody's crying.",
            ]
        case .questionable:
            return [
                "Interesting strategy, champ.",
                "Bold move. The macros have questions.",
                "That's a lotta calories for not a lotta protein.",
                "We can recover. Don't push it.",
                "Larry's eyebrow just filed a complaint.",
                "Explain that one to tomorrow.",
            ]
        case .bad:
            return [
                "Brother... what are we doing?",
                "Larry did not train you for this.",
                "The macros don't lie. And they're currently screaming.",
                "That one hurt the day.",
                "We're off the plan. Own it and adjust.",
                "I felt that in my headband.",
            ]
        case .disaster:
            return [
                "GOOD LORD.",
                "Put the fork down, Rocky.",
                "We're gonna need a bigger calorie budget.",
                "The macros just left the chat.",
                "Brother. The budget is on fire.",
                "That's not a snack. That's a sequel.",
            ]
        }
    }
}

struct LarryQuotePicker {
    private var recent: [LarryReactionCategory: [String]] = [:]
    var randomIndex: (Int) -> Int

    init(randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.randomIndex = randomIndex
    }

    mutating func pick(for category: LarryReactionCategory) -> String {
        let pool = LarryQuoteBank.lines(for: category)
        guard !pool.isEmpty else { return "Logged." }

        let used = recent[category] ?? []
        let unused = pool.filter { !used.contains($0) }
        let source: [String]
        if unused.isEmpty {
            let last = used.last
            let fresh = pool.filter { $0 != last }
            source = fresh.isEmpty ? pool : fresh
        } else {
            source = unused
        }

        let raw = randomIndex(source.count)
        let index = source.isEmpty ? 0 : ((raw % source.count) + source.count) % source.count
        let choice = source[index]

        if unused.isEmpty {
            recent[category] = [choice]
        } else {
            recent[category] = used + [choice]
        }
        return choice
    }
}

enum LarryQuoteMemory {
    private static var picker = LarryQuotePicker()

    static func pick(for category: LarryReactionCategory) -> String {
        picker.pick(for: category)
    }
}
