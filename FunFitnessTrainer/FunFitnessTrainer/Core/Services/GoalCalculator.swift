import Foundation

/// Daily calorie adjustment per pound of body-weight change per week (~3,500 kcal per lb).
private let kcalPerLbPerWeek: Double = 3500.0 / 7.0

enum MacroGoalKind: String, Identifiable, Hashable {
    case calories, protein, carbs, fat

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .calories: return "Cal"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        }
    }
}

struct MacroGoalExplanation: Identifiable, Equatable {
    let kind: MacroGoalKind
    let title: String
    let subtitle: String
    let body: String

    var id: MacroGoalKind { kind }
}

struct FitnessPlan: Equatable {
    let goalType: GoalType
    /// Signed: negative = losing lb/week, positive = gaining, zero = maintain.
    let weeklyLbChange: Double
    let weeksToGoal: Double?
    let maintenanceCalories: Double
    /// Target before the optional "a little lower" nudge.
    let calculatedCalories: Double
    /// Calories removed from the calculated target. Zero means the plan number.
    let calorieNudge: Double
    /// Largest nudge still allowed without crossing the calorie floor.
    let maxCalorieNudge: Double
    let targetCalories: Double
    let dailyCalorieDelta: Double
    let macros: MacroGoalPayload
    let dietStyle: DietStyle
    let coachStyleName: String
    let coachSummary: String
    let macroAdvice: String
}

enum GoalCalculator {
    /// V1 protein: 1.0 g per lb of current bodyweight for every goal.
    /// 1.1 g/lb was a cutting flourish, not a required product rule — 193g at 175 lb
    /// is hard to hit and doesn't improve adherence. 1.0 g/lb sits at the top of the
    /// practical 0.8–1.0 range for fat loss / muscle retention.
    static let proteinGramsPerLb: Double = 1.0
    /// How far under the calculated target someone can pull the goal.
    static let maxManualCalorieNudge: Double = 300
    static let calorieNudgeStep: Double = 25

    /// Lean-eating philosophy inspired by coaches like Patrick Murphy & Duffy Gaver.
    static let leanCoachPhilosophy = """
    Stay lean with high protein (~1 g per lb bodyweight), mostly whole foods, plenty of vegetables, \
    lean meats, fish, eggs, and Greek yogurt. Skip junk, liquid calories, and oversized portions. \
    Carbs around training; fats from olive oil, nuts, avocado in moderation. Simple, disciplined, repeatable.
    """

    // MARK: - Public

    static func recommendedMacros(for settings: UserSettings) -> MacroGoalPayload {
        buildPlan(for: settings).macros
    }

    /// Structured plan facts for Larry chat (cloud + offline).
    static func coachPlanContext(
        for settings: UserSettings,
        exerciseCalorieBonus: Double = 0
    ) -> [String: Any] {
        let plan = buildPlan(for: settings)
        let weightLb = (settings.weightKg * kgToLb).rounded()
        let goalLb = (settings.effectiveGoalWeightKg * kgToLb).rounded()
        let heightIn = (settings.heightCm / 2.54).rounded()
        let foodTarget = plan.targetCalories
        let trackedExercise = max(0, exerciseCalorieBonus).rounded()

        var payload: [String: Any] = [
            "formula": "Mifflin-St Jeor BMR × activity multiplier, then ±(~3500 kcal per lb ÷ 7) for weekly rate",
            "sex": settings.sex.rawValue,
            "age": settings.age,
            "height_cm": settings.heightCm.rounded(),
            "height_in": heightIn,
            "weight_kg": settings.weightKg.rounded(toPlaces: 1),
            "weight_lb": weightLb,
            "goal_weight_kg": settings.effectiveGoalWeightKg.rounded(toPlaces: 1),
            "goal_weight_lb": goalLb,
            "activity": settings.activity.displayName,
            "activity_multiplier": settings.activity.rawValue,
            "goal_type": plan.goalType.rawValue,
            "diet_style": plan.dietStyle.rawValue,
            "diet_style_name": plan.dietStyle.displayName,
            "diet_macro_split": plan.dietStyle.macroHint,
            "weekly_lb_change": plan.weeklyLbChange.rounded(toPlaces: 2),
            "bmr_estimate": bmr(for: settings).rounded(),
            "maintenance_calories": plan.maintenanceCalories,
            "daily_calorie_delta": plan.dailyCalorieDelta,
            "calculated_calories_before_nudge": plan.calculatedCalories,
            "calorie_nudge": plan.calorieNudge,
            "max_calorie_nudge": plan.maxCalorieNudge,
            "base_food_target_calories": foodTarget,
            "exercise_calories_tracked_today": trackedExercise,
            "exercise_bonus_calories_today": 0,
            "exercise_increases_food_target": false,
            "effective_calories_today": foodTarget,
            "protein_g": plan.macros.proteinG,
            "carbs_g": plan.macros.carbsG,
            "fat_g": plan.macros.fatG,
            "protein_per_lb": proteinGramsPerLb,
            "calorie_floor": settings.sex == .female ? 1400 : 1600,
            "macro_advice": plan.macroAdvice,
            "philosophy": leanCoachPhilosophy,
        ]
        if let weeks = plan.weeksToGoal {
            payload["weeks_to_goal"] = (weeks * 10).rounded() / 10
        }
        return payload
    }

    /// Larry-voiced explanation of how today's calorie target was chosen.
    static func larryPlanExplanation(
        for settings: UserSettings,
        exerciseCalorieBonus: Double = 0
    ) -> String {
        let cal = explanation(
            for: .calories,
            settings: settings,
            exerciseCalorieBonus: exerciseCalorieBonus
        )
        let protein = explanation(
            for: .protein,
            settings: settings,
            exerciseCalorieBonus: exerciseCalorieBonus
        )
        return "Here's the math, not vibes: \(cal.body) \(protein.body) Macros don't lie. People do."
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short title + Larry-voiced body for why a single macro target is set.
    static func explanation(
        for kind: MacroGoalKind,
        settings: UserSettings,
        exerciseCalorieBonus: Double = 0,
        displayedGoal: MacroGoalPayload? = nil
    ) -> MacroGoalExplanation {
        let plan = buildPlan(for: settings)
        let macros = displayedGoal ?? plan.macros
        let weightLb = Int((settings.weightKg * kgToLb).rounded())
        let goalLb = Int((settings.effectiveGoalWeightKg * kgToLb).rounded())
        let usesImperial = settings.usesImperialUnits
        let weightBit = usesImperial ? "\(weightLb) lb" : "\(Int(settings.weightKg.rounded())) kg"
        let goalBit = usesImperial ? "\(goalLb) lb" : "\(Int(settings.effectiveGoalWeightKg.rounded())) kg"
        let bmrVal = Int(bmr(for: settings).rounded())
        let maint = Int(plan.maintenanceCalories)
        let delta = Int(plan.dailyCalorieDelta)
        let trackedExercise = Int(max(0, exerciseCalorieBonus).rounded())
        let shownCals = Int(macros.calories.rounded())
        let proteinG = Int(macros.proteinG.rounded())
        let carbsG = Int(macros.carbsG.rounded())
        let fatG = Int(macros.fatG.rounded())
        let proteinPerLb = weightLb > 0 ? macros.proteinG / Double(weightLb) : proteinGramsPerLb
        let fatPercent = Int(((Double(fatG) * 9) / max(Double(shownCals), 1) * 100).rounded())
        let floor = Int(calorieFloor(for: settings.sex))
        let dietName = plan.dietStyle.displayName

        switch kind {
        case .calories:
            var paceLine = ""
            switch plan.goalType {
            case .lose:
                paceLine = "You're cutting ~\(String(format: "%.1f", abs(plan.weeklyLbChange))) lb/week, so I pull about \(abs(delta)) cal off maintenance."
            case .gain:
                paceLine = "You're building ~\(String(format: "%.1f", plan.weeklyLbChange)) lb/week, so I add about \(delta) cal on top of maintenance."
            case .maintain:
                paceLine = "You're maintaining, so the target sits on maintenance. No surplus, no deficit games."
            }

            var weeksLine = ""
            if let weeks = plan.weeksToGoal, weeks >= 1 {
                weeksLine = " At that pace, goal weight (\(goalBit)) is roughly \(Int(weeks.rounded())) weeks out."
            }

            var bonusLine = ""
            if plan.calorieNudge >= calorieNudgeStep {
                bonusLine = " The formula lands at \(Int(plan.calculatedCalories)). You pulled it \(Int(plan.calorieNudge)) cal lower, so today is \(shownCals)."
            } else {
                bonusLine = " That lands at \(shownCals) for today."
            }
            if trackedExercise > 0 {
                bonusLine += " Logged or Health activity (\(trackedExercise) cal) is tracked, but it does not add calories to eat. Activity is already in your TDEE."
            }

            let dietLine = " \(dietName) doesn't change this calorie math. It changes the split: \(plan.dietStyle.macroHint)."

            let body = """
            At \(weightBit) with \(settings.activity.displayName.lowercased()) activity, Mifflin St Jeor BMR is ~\(bmrVal) and maintenance is ~\(maint). \
            \(paceLine)\(weeksLine) We also keep a floor of \(floor) so you don't starve the machine.\(bonusLine)\(dietLine)
            """
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            return MacroGoalExplanation(
                kind: .calories,
                title: "Why \(shownCals.formatted()) calories?",
                subtitle: "\(dietName) · your daily energy budget",
                body: body
            )

        case .protein:
            let body = """
            Protein is locked at ~\(String(format: "%.1f", proteinPerLb)) g per lb of current bodyweight (\(weightBit)). \
            That's \(proteinG)g. High enough to protect muscle while you \(plan.goalType == .lose ? "cut" : plan.goalType == .gain ? "build" : "maintain"), \
            simple enough to hit with real food. Protein first, then fill the rest.
            """
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            return MacroGoalExplanation(
                kind: .protein,
                title: "Why \(proteinG)g protein?",
                subtitle: "Muscle and satiety first",
                body: body
            )

        case .fat:
            let fatSource: String = {
                switch plan.dietStyle {
                case .balanced:
                    return "enough from olive oil, nuts, avocado, and eggs, without crowding out protein and carbs"
                case .keto:
                    return "fat fills the calories after protein and a small carb allowance"
                case .carnivore:
                    return "fat fills the calories after protein, since carbs are zero"
                case .paleo:
                    return "fat stays higher from meat, eggs, olive oil, nuts, and avocado, and carbs take what's left"
                }
            }()
            let body = """
            Fat is about \(fatPercent)% of your calorie target, \(fatG)g, so hormones, joints, and satiety stay covered. \
            For \(plan.goalType.displayName.lowercased()) on \(dietName), that share is intentional: \(fatSource).
            """
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            return MacroGoalExplanation(
                kind: .fat,
                title: "Why \(fatG)g fat?",
                subtitle: "Hormones and staying power",
                body: body
            )

        case .carbs:
            let body: String = {
                switch plan.dietStyle {
                case .keto:
                    return """
                    Keto locks carbs near \(carbsG)g so the rest of the \(shownCals) calories come from protein (\(proteinG)g) and fat (\(fatG)g). \
                    That low cap is the diet, not a guess about training fuel.
                    """
                case .carnivore:
                    return """
                    Carnivore sets carbs at \(carbsG)g. Protein (\(proteinG)g) and fat (\(fatG)g) cover the \(shownCals) calories. \
                    Nothing here is reserved for bread, fruit, or plants.
                    """
                case .paleo:
                    return """
                    After protein (\(proteinG)g) and the higher paleo fat target (\(fatG)g), carbs take the remainder, \(carbsG)g today. \
                    Think plants and tubers, not the drive thru.
                    """
                case .balanced:
                    return """
                    Carbs fill whatever calories are left after protein (\(proteinG)g) and fat (\(fatG)g). That's \(carbsG)g today \
                    (never below 50g). They fuel training and recovery; keep more of them around workouts and stick to whole-food sources when you can.
                    """
                }
            }()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            let carbSubtitle: String = {
                switch plan.dietStyle {
                case .keto, .carnivore: return "Set by your \(dietName) choice"
                case .paleo: return "What's left after protein and fat"
                case .balanced: return "Training fuel from the remainder"
                }
            }()

            return MacroGoalExplanation(
                kind: .carbs,
                title: "Why \(carbsG)g carbs?",
                subtitle: carbSubtitle,
                body: body
            )
        }
    }

    static func buildPlan(for settings: UserSettings) -> FitnessPlan {
        let currentLb = settings.weightKg * kgToLb
        let goalLb = settings.effectiveGoalWeightKg * kgToLb
        let goalType = settings.resolvedGoalType
        let weeklyLb = settings.weeklyLbChangeTarget ?? recommendedWeeklyLbChange(
            currentLb: currentLb,
            goalLb: goalLb,
            goalType: goalType
        )

        let maintenance = maintenanceCalories(for: settings)
        let dailyDelta = weeklyLb * kcalPerLbPerWeek
        let floor = calorieFloor(for: settings.sex)
        let ceiling = maintenance + 750
        let calculated = min(max(maintenance + dailyDelta, floor), ceiling)
        let maxNudge = calorieNudgeLimit(calculated: calculated, floor: floor)
        let nudge = min(settings.resolvedCalorieNudge, maxNudge)
        let target = calculated - nudge

        let macros = macrosForDiet(
            settings: settings,
            targetCalories: target,
            goalType: goalType
        )

        let weeks: Double? = {
            guard goalType != .maintain, abs(weeklyLb) > 0.05 else { return nil }
            let diffLb = abs(goalLb - currentLb)
            guard diffLb >= 1 else { return nil }
            return diffLb / abs(weeklyLb)
        }()

        let style = coachStyle(for: goalType, diet: settings.dietStyle)

        return FitnessPlan(
            goalType: goalType,
            weeklyLbChange: weeklyLb,
            weeksToGoal: weeks,
            maintenanceCalories: maintenance.rounded(),
            calculatedCalories: calculated.rounded(),
            calorieNudge: nudge.rounded(),
            maxCalorieNudge: maxNudge,
            targetCalories: target.rounded(),
            dailyCalorieDelta: dailyDelta.rounded(),
            macros: macros,
            dietStyle: settings.dietStyle,
            coachStyleName: style.name,
            coachSummary: style.summary,
            macroAdvice: style.macroAdvice(goalType)
        )
    }

    /// Suggested lb/week toward goal (negative = loss, positive = gain).
    static func recommendedWeeklyLbChange(
        currentLb: Double,
        goalLb: Double,
        goalType: GoalType
    ) -> Double {
        let diff = goalLb - currentLb
        if abs(diff) < 1 { return 0 }

        switch goalType {
        case .maintain:
            return 0
        case .lose:
            let maxSafe = min(2.0, max(0.5, currentLb * 0.01))
            let pace = min(maxSafe, max(0.5, abs(diff) / 12))
            return -pace
        case .gain:
            let pace = min(0.75, max(0.25, abs(diff) / 16))
            return pace
        }
    }

    // MARK: - TDEE

    private static func calorieFloor(for sex: Sex) -> Double {
        sex == .female ? 1400 : 1600
    }

    /// Largest 25-cal step still above the floor, capped at 300.
    private static func calorieNudgeLimit(calculated: Double, floor: Double) -> Double {
        let raw = min(maxManualCalorieNudge, max(0, calculated - floor))
        return (raw / calorieNudgeStep).rounded(.down) * calorieNudgeStep
    }

    private static func bmr(for settings: UserSettings) -> Double {
        switch settings.sex {
        case .male:
            return 10 * settings.weightKg + 6.25 * settings.heightCm - 5 * Double(settings.age) + 5
        case .female:
            return 10 * settings.weightKg + 6.25 * settings.heightCm - 5 * Double(settings.age) - 161
        }
    }

    private static func maintenanceCalories(for settings: UserSettings) -> Double {
        bmr(for: settings) * settings.activity.rawValue
    }

    // MARK: - Celebrity-trainer style macros (Murphy / Gaver inspired)

    /// High-protein default, with carb and fat shares that follow the chosen diet.
    private static func macrosForDiet(
        settings: UserSettings,
        targetCalories: Double,
        goalType: GoalType
    ) -> MacroGoalPayload {
        let currentLb = settings.weightKg * kgToLb
        let proteinG = (currentLb * proteinGramsPerLb).rounded()

        switch settings.dietStyle {
        case .balanced:
            let fatPercent: Double
            switch goalType {
            case .lose: fatPercent = 0.28
            case .gain: fatPercent = 0.25
            case .maintain: fatPercent = 0.27
            }
            let fatG = (targetCalories * fatPercent / 9).rounded()
            let carbsG = max(50, (targetCalories - proteinG * 4 - fatG * 9) / 4).rounded()
            return snapToCalories(
                MacroGoalPayload(
                    calories: targetCalories.rounded(),
                    proteinG: proteinG,
                    carbsG: carbsG,
                    fatG: fatG
                ),
                minimumFatG: 40,
                minimumCarbsG: 50
            )

        case .keto:
            return allocateMacros(
                calories: targetCalories,
                proteinG: proteinG,
                carbsG: 30,
                minimumFatG: max(45, currentLb * 0.35),
                minimumCarbsG: 20
            )

        case .paleo:
            let fatG = (targetCalories * 0.38 / 9).rounded()
            let carbsG = max(60, ((targetCalories - proteinG * 4 - fatG * 9) / 4).rounded())
            let fittedFat = max(40, ((targetCalories - proteinG * 4 - carbsG * 4) / 9).rounded())
            return snapToCalories(
                MacroGoalPayload(
                    calories: targetCalories.rounded(),
                    proteinG: proteinG,
                    carbsG: carbsG,
                    fatG: fittedFat
                ),
                minimumFatG: 40,
                minimumCarbsG: 60
            )

        case .carnivore:
            return allocateMacros(
                calories: targetCalories,
                proteinG: proteinG,
                carbsG: 0,
                minimumFatG: max(45, currentLb * 0.4),
                minimumCarbsG: 0
            )
        }
    }

    /// Protein and carbs are preferred targets. Fat absorbs the rest, and protein gives way if fat would collapse.
    private static func allocateMacros(
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        minimumFatG: Double,
        minimumCarbsG: Double
    ) -> MacroGoalPayload {
        var protein = max(0, proteinG)
        var carbs = max(minimumCarbsG, carbsG)
        var fat = (calories - protein * 4 - carbs * 4) / 9

        if fat < minimumFatG {
            let needed = (minimumFatG - max(fat, 0)) * 9
            let carbSlack = max(0, carbs - minimumCarbsG) * 4
            let fromCarbs = min(needed, carbSlack)
            carbs -= fromCarbs / 4
            let still = needed - fromCarbs
            if still > 0 {
                protein = max(0, protein - still / 4)
            }
            fat = max(0, (calories - protein * 4 - carbs * 4) / 9)
        }

        return snapToCalories(
            MacroGoalPayload(
                calories: calories.rounded(),
                proteinG: protein.rounded(),
                carbsG: carbs.rounded(),
                fatG: fat.rounded()
            ),
            minimumFatG: minimumFatG,
            minimumCarbsG: minimumCarbsG
        )
    }

    /// 4/4/9 must land on the calorie target. A heavy cut can otherwise keep 1 g/lb protein
    /// and the carb floor, and the gram targets add up to more calories than the plan.
    private static func snapToCalories(
        _ macros: MacroGoalPayload,
        minimumFatG: Double,
        minimumCarbsG: Double
    ) -> MacroGoalPayload {
        var protein = max(0, macros.proteinG.rounded())
        var carbs = max(0, macros.carbsG.rounded())
        var fat = max(0, macros.fatG.rounded())
        let target = macros.calories.rounded()
        let minFat = max(0, minimumFatG.rounded())
        let minCarbs = max(0, minimumCarbsG.rounded())

        func energy() -> Double {
            protein * 4 + carbs * 4 + fat * 9
        }

        for _ in 0..<80 {
            let diff = energy() - target
            if abs(diff) <= 4 { break }
            if diff > 0 {
                if fat > minFat {
                    fat -= 1
                } else if carbs > minCarbs {
                    carbs -= 1
                } else if protein > 0 {
                    protein -= 1
                } else {
                    break
                }
            } else if fat < 250 {
                fat += 1
            } else if carbs < 800 {
                carbs += 1
            } else {
                protein += 1
            }
        }

        return MacroGoalPayload(calories: target, proteinG: protein, carbsG: carbs, fatG: fat)
    }

    private static func coachStyle(for goalType: GoalType, diet: DietStyle) -> CoachStyle {
        CoachStyle(
            name: LarryMcQuade.name,
            summary: """
            \(LarryMcQuade.title): \(diet.displayName) eating, counted macros, real food, and no excuses.
            """,
            macroAdvice: { type in
                switch diet {
                case .keto:
                    return "Larry says: keto keeps carbs near 30g. Protein stays around 1 g per lb, and fat fills the rest. Don't turn it into a cheese-and-excuses contest."
                case .carnivore:
                    return "Larry says: carnivore means meat, eggs, and fat. Carbs sit at zero. Hit the protein and stop negotiating with a bun."
                case .paleo:
                    return "Larry says: paleo is high protein, more fat, and carbs from plants, not the drive thru. Same calorie target, cleaner split."
                case .balanced:
                    switch type {
                    case .lose:
                        return "Larry says: protein at ~1 g per lb, veggies on lock, and don't slash calories below your plan. Macros don't lie. People do."
                    case .gain:
                        return "Larry says: ~1 g protein per lb, quality carbs for recovery, healthy fats. Lean gains beat dirty bulking every time, baby."
                    case .maintain:
                        return "Larry says: ~1 g protein per lb, mostly whole foods. Adjust portions before you overhaul everything."
                    }
                }
            }
        )
    }

    private struct CoachStyle {
        let name: String
        let summary: String
        let macroAdvice: (GoalType) -> String
    }

    static let kgToLb = 2.2046226218
    static let lbToKg = 1.0 / kgToLb
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
