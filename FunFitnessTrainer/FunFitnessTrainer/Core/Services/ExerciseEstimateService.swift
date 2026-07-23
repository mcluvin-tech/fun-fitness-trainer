import Foundation

enum ExerciseEstimateService {
    /// Rough calories burned from a spoken or typed activity description.
    static func estimate(from description: String, weightKg: Double = 75) -> ExercisePayload {
        let text = description.lowercased()
        let minutes = parseDurationMinutes(in: text)
        let miles = parseMiles(in: text)

        if text.contains("run") || text.contains("jog") {
            if let miles {
                let burn = caloriesPerMileRunning(weightKg: weightKg) * miles
                return ExercisePayload(
                    name: miles == 1 ? "1 mile run" : "\(formatNumber(miles)) mile run",
                    caloriesBurned: burn,
                    durationMinutes: miles * 10
                )
            }
            let mins = max(minutes ?? 30, 10)
            return ExercisePayload(
                name: "Run",
                caloriesBurned: calories(met: 9.0, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        if text.contains("walk") {
            if let miles {
                let burn = caloriesPerMileWalking(weightKg: weightKg) * miles
                return ExercisePayload(
                    name: miles == 1 ? "1 mile walk" : "\(formatNumber(miles)) mile walk",
                    caloriesBurned: burn,
                    durationMinutes: miles * 18
                )
            }
            let mins = max(minutes ?? 30, 10)
            return ExercisePayload(
                name: "Walk",
                caloriesBurned: calories(met: 3.5, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        if text.contains("bike") || text.contains("cycl") || text.contains("spin") {
            let mins = max(minutes ?? 30, 10)
            return ExercisePayload(
                name: "Cycling",
                caloriesBurned: calories(met: 6.8, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        if text.contains("swim") {
            let mins = max(minutes ?? 30, 10)
            return ExercisePayload(
                name: "Swim",
                caloriesBurned: calories(met: 7.0, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        if text.contains("hiit") || text.contains("interval") {
            let mins = max(minutes ?? 25, 10)
            return ExercisePayload(
                name: "HIIT",
                caloriesBurned: calories(met: 8.0, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        if text.contains("weight") || text.contains("lift") || text.contains("strength") || text.contains("gym") {
            let mins = max(minutes ?? 45, 15)
            return ExercisePayload(
                name: "Weight training",
                caloriesBurned: calories(met: 5.0, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        if text.contains("yoga") || text.contains("stretch") {
            let mins = max(minutes ?? 30, 10)
            return ExercisePayload(
                name: "Yoga",
                caloriesBurned: calories(met: 3.0, weightKg: weightKg, minutes: mins),
                durationMinutes: mins
            )
        }

        let mins = max(minutes ?? 30, 15)
        return ExercisePayload(
            name: "Workout",
            caloriesBurned: calories(met: 5.5, weightKg: weightKg, minutes: mins),
            durationMinutes: mins
        )
    }

    static func preset(_ preset: ExercisePreset, weightKg: Double = 75) -> ExercisePayload {
        switch preset {
        case .run2Miles:
            let burn = caloriesPerMileRunning(weightKg: weightKg) * 2
            return ExercisePayload(name: "2 mile run", caloriesBurned: burn, durationMinutes: 20)
        case .run30Min:
            return ExercisePayload(
                name: "30 min run",
                caloriesBurned: calories(met: 9.0, weightKg: weightKg, minutes: 30),
                durationMinutes: 30
            )
        case .walk30Min:
            return ExercisePayload(
                name: "30 min walk",
                caloriesBurned: calories(met: 3.5, weightKg: weightKg, minutes: 30),
                durationMinutes: 30
            )
        case .weights45Min:
            return ExercisePayload(
                name: "45 min weights",
                caloriesBurned: calories(met: 5.0, weightKg: weightKg, minutes: 45),
                durationMinutes: 45
            )
        case .bike30Min:
            return ExercisePayload(
                name: "30 min bike",
                caloriesBurned: calories(met: 6.8, weightKg: weightKg, minutes: 30),
                durationMinutes: 30
            )
        }
    }

    // MARK: - MET helpers

    private static func calories(met: Double, weightKg: Double, minutes: Double) -> Double {
        max((met * weightKg * minutes) / 60.0, 25).rounded()
    }

    private static func caloriesPerMileRunning(weightKg: Double) -> Double {
        // ~100 kcal/mile at ~75 kg; scale with body weight.
        (100 * weightKg / 75).rounded()
    }

    private static func caloriesPerMileWalking(weightKg: Double) -> Double {
        (55 * weightKg / 75).rounded()
    }

    private static func parseMiles(in text: String) -> Double? {
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(?:mile|mi)\b"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let value = Double(text[range]) {
            return value
        }
        let words: [(String, Double)] = [
            ("half mile", 0.5), ("half a mile", 0.5),
            ("one mile", 1), ("a mile", 1), ("1 mile", 1),
            ("two mile", 2), ("two miles", 2), ("2 mile", 2), ("2 miles", 2),
            ("three mile", 3), ("three miles", 3),
        ]
        for (phrase, miles) in words where text.contains(phrase) {
            return miles
        }
        return nil
    }

    private static func parseDurationMinutes(in text: String) -> Double? {
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(?:min|mins|minute|minutes)\b"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let value = Double(text[range]) {
            return value
        }
        if text.contains("half hour") || text.contains("30 min") { return 30 }
        if text.contains("hour") && !text.contains("half") {
            if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*hour"#),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let hours = Double(text[range]) {
                return hours * 60
            }
            return 60
        }
        return nil
    }

    private static func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum ExercisePreset: String, CaseIterable, Identifiable {
    case run2Miles = "2 mile run"
    case run30Min = "30 min run"
    case walk30Min = "30 min walk"
    case weights45Min = "45 min weights"
    case bike30Min = "30 min bike"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .run2Miles, .run30Min: return "figure.run"
        case .walk30Min: return "figure.walk"
        case .weights45Min: return "dumbbell.fill"
        case .bike30Min: return "bicycle"
        }
    }
}
