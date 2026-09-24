import SwiftUI
import SwiftData

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context

    @State private var step = 0
    @State private var usesImperial = true
    @State private var currentWeightKg = 74.8
    @State private var goalWeightKg = 70.3
    @State private var weeklyLbChange = -1.0
    @State private var weeklyManuallySet = false
    @State private var trainingFocus: GoalType = .maintain
    @State private var focusChosen = false

    @State private var sex: Sex = .male
    @State private var age = 30
    @State private var heightCm = 175.0
    @State private var heightFt = 5
    @State private var heightIn = 9
    @State private var activity: ActivityLevel = .moderate
    @State private var saveError: String?
    @State private var welcomeQuote = LarryMcQuade.randomWelcomeMessage()

    private let totalSteps = 4

    private var draftSettings: UserSettings {
        UserSettings(
            sex: sex,
            age: age,
            heightCm: heightCmValue,
            weightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            weeklyLbChangeTarget: weeklyLbChange,
            usesImperialUnits: usesImperial,
            activity: activity,
            goalType: activeGoalType,
            trainerVoice: LarryMcQuade.defaultVoice
        )
    }

    private var plan: FitnessPlan {
        GoalCalculator.buildPlan(for: draftSettings)
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Welcome"
        case 1: return "Your weights"
        case 2: return "About you"
        case 3: return "Your plan"
        default: return "Your plan"
        }
    }

    private var primaryButtonTitle: String {
        step < totalSteps - 1 ? "Continue" : "Start training"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    stepContent
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background { HomeDarkBackground() }
            .preferredColorScheme(.dark)
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        advance()
                    } label: {
                        Text(primaryButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccent)

                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .font(.subheadline)
                            .foregroundStyle(BrandTheme.teal)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background {
                    BrandTheme.homeActionBar
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(BrandTheme.purple.opacity(0.35))
                                .frame(height: 1)
                        }
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .toolbar {
                if step == 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { finish() }
                            .font(.subheadline)
                            .foregroundStyle(BrandTheme.teal)
                    }
                }
            }
            .onChange(of: currentWeightKg) { _, _ in syncWeeklyIfNeeded() }
            .onChange(of: goalWeightKg) { _, _ in syncWeeklyIfNeeded() }
            .onAppear {
                syncWeeklyIfNeeded()
                updateHeightCm()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: weightsStep
        case 2: bodyStep
        case 3: planStep
        default: EmptyView()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            LarryHeroImage(portrait: .welcome, maxHeight: 300)

            Text(LarryMcQuade.appName)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandTheme.magenta, BrandTheme.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Meet **\(LarryMcQuade.name)** — \(LarryMcQuade.title.lowercased()). Your 80s gym guru for realistic weight goals, daily calories, and macros. Not medical advice.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(BrandTheme.homeSecondaryText)

            Text("\"\(welcomeQuote)\"")
                .font(.subheadline.weight(.semibold))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(BrandTheme.teal)

            AuthSignInSection()
        }
        .padding(.top, 8)
        .padding(.vertical, 12)
        .background(BrandTheme.homeCard)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [BrandTheme.purple.opacity(0.5), BrandTheme.teal.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var weightsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What are you training for?")
                    .font(.headline)
                    .foregroundStyle(BrandTheme.homePrimaryText)
                Picker("Training focus", selection: focusBinding) {
                    Text("Lose fat").tag(GoalType.lose)
                    Text("Maintain").tag(GoalType.maintain)
                    Text("Make gains").tag(GoalType.gain)
                }
                .pickerStyle(.segmented)
                Text(focusCaption)
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }

            Picker("Units", selection: $usesImperial) {
                Text("lb").tag(true)
                Text("kg").tag(false)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                pieWeightDial(title: "Current weight", value: $currentWeightKg, color: BrandTheme.magenta)
                pieWeightDial(title: "Goal weight", value: $goalWeightKg, color: BrandTheme.teal)
            }

            goalSummaryCard

            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly pace")
                    .font(.headline)
                    .foregroundStyle(BrandTheme.homePrimaryText)

                Text("Based on ~3,500 kcal per pound. We cap pace at a safe, realistic rate.")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)

                if activeGoalType == .maintain {
                    Text("Maintaining — calories stay at maintenance.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                } else {
                    WeeklyPaceSlider(
                        value: $weeklyLbChange,
                        range: weeklySliderRange,
                        step: 0.25,
                        valueLabel: weeklyPaceLabel,
                        onEditingChanged: { editing in
                            if editing { weeklyManuallySet = true }
                        }
                    )
                }
            }
            .padding(16)
            .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func pieWeightDial(title: String, value: Binding<Double>, color: Color) -> some View {
        let displayBinding = Binding<Double>(
            get: {
                usesImperial ? value.wrappedValue * GoalCalculator.kgToLb : value.wrappedValue
            },
            set: { newDisplay in
                value.wrappedValue = usesImperial ? newDisplay * GoalCalculator.lbToKg : newDisplay
            }
        )
        return PieChartDialSlider(
            title: title,
            value: displayBinding,
            range: weightRange,
            step: usesImperial ? 1 : 0.5,
            unit: usesImperial ? "lb" : "kg",
            color: color
        )
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private var bodyStep: some View {
        VStack(spacing: 16) {
            Picker("Sex", selection: $sex) {
                ForEach(Sex.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)

            onboardingRow {
                Stepper("Age: \(age)", value: $age, in: 16...90)
            }

            if usesImperial {
                HStack {
                    Picker("Ft", selection: $heightFt) {
                        ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                    }
                    Picker("In", selection: $heightIn) {
                        ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                    }
                }
                .onChange(of: heightFt) { _, _ in updateHeightCm() }
                .onChange(of: heightIn) { _, _ in updateHeightCm() }
            } else {
                onboardingRow {
                    Stepper("Height: \(Int(heightCm)) cm", value: $heightCm, in: 120...220, step: 1)
                }
            }

            Picker("Activity", selection: $activity) {
                ForEach(ActivityLevel.allCases) { Text($0.displayName).tag($0) }
            }

            if activeGoalType == .maintain {
                Text("Current and goal weight are close — we'll use maintenance calories.")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
        }
        .onAppear { updateHeightCm() }
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                LarryAvatarView(portrait: .programPitch, size: 80)
                    .frame(width: 80)

                LarrySpeechBubble(text: larryProgramPitch, maxLines: nil)
                    .padding(.top, 14)
            }

            planMetricRow(
                title: "Current → goal",
                value: "\(formatWeight(currentWeightKg)) → \(formatWeight(goalWeightKg))"
            )
            planMetricRow(
                title: "Daily calories",
                value: "\(Int(plan.targetCalories)) kcal",
                subtitle: plan.dailyCalorieDelta == 0
                    ? "Maintenance"
                    : "\(plan.dailyCalorieDelta > 0 ? "+" : "")\(Int(plan.dailyCalorieDelta)) vs maintenance"
            )
            if let weeks = plan.weeksToGoal, weeks.isFinite {
                planMetricRow(
                    title: "Estimated timeline",
                    value: timelineLabel(weeks: weeks)
                )
            }

            Divider()
                .overlay(BrandTheme.purple.opacity(0.3))

            Text("Macros (\(plan.coachStyleName))")
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            HStack(spacing: 12) {
                macroChip("Protein", "\(Int(plan.macros.proteinG))g")
                macroChip("Carbs", "\(Int(plan.macros.carbsG))g")
                macroChip("Fat", "\(Int(plan.macros.fatG))g")
            }

            Text(plan.coachSummary)
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)

            Text(diet.title)
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text(diet.summary)
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(diet.points, id: \.self) { point in
                    Text(point)
                        .font(.caption)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }

            Text(plan.macroAdvice)
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandTheme.magenta.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(BrandTheme.magenta.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(16)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func onboardingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 10))
    }

    private var weightInferredGoal: GoalType {
        let diff = goalWeightKg - currentWeightKg
        if diff < -0.5 { return .lose }
        if diff > 0.5 { return .gain }
        return .maintain
    }

    /// Explicit "Make gains" wins even when the scale goal is still close to today's weight.
    private var activeGoalType: GoalType {
        focusChosen ? trainingFocus : weightInferredGoal
    }

    private var diet: DietGuidance {
        GoalCalculator.dietGuidance(for: activeGoalType, plan: plan)
    }

    private var focusCaption: String {
        switch activeGoalType {
        case .gain:
            return "Make gains sets a protein-forward surplus. You'll see the diet on the plan step. Coaching guidance, not medical advice."
        case .lose:
            return "Lose fat keeps protein high and calories under maintenance."
        case .maintain:
            return "Maintain eats to your calorie target. Protein still comes first."
        }
    }

    private var goalSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activeGoalType.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("≈ \(Int(plan.targetCalories)) kcal/day at this pace")
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(BrandTheme.neonBlue.opacity(0.35), lineWidth: 1)
        )
    }

    private var weightRange: ClosedRange<Double> {
        usesImperial ? 90...400 : 40...180
    }

    private var weeklySliderRange: ClosedRange<Double> {
        switch activeGoalType {
        case .lose: return -2.0...(-0.5)
        case .gain: return 0.25...0.75
        case .maintain: return 0...0
        }
    }

    private var weeklyPaceLabel: String {
        if activeGoalType == .maintain { return "Maintaining" }
        let absLb = abs(weeklyLbChange)
        let dir = weeklyLbChange < 0 ? "lose" : "gain"
        return String(format: "%.2f lb/week (%@)", absLb, dir)
    }

    private var larryProgramPitch: String {
        if let weeks = plan.weeksToGoal, weeks.isFinite {
            let rounded = max(1, Int(weeks.rounded()))
            return "You can look jacked like me if you follow my \(rounded)-week program."
        }
        return "You can look jacked like me if you follow my program."
    }

    private var focusBinding: Binding<GoalType> {
        Binding(
            get: { trainingFocus },
            set: { newValue in
                trainingFocus = newValue
                focusChosen = true
                weeklyManuallySet = false
                if newValue == .gain, goalWeightKg + 0.4 < currentWeightKg {
                    goalWeightKg = currentWeightKg
                }
                if newValue == .lose, goalWeightKg > currentWeightKg + 0.4 {
                    goalWeightKg = currentWeightKg
                }
                applyDefaultPace(for: newValue)
            }
        )
    }

    private func syncWeeklyIfNeeded() {
        guard !weeklyManuallySet else { return }
        if !focusChosen {
            trainingFocus = weightInferredGoal
        }
        applyDefaultPace(for: activeGoalType)
    }

    private func applyDefaultPace(for goal: GoalType) {
        let suggested = GoalCalculator.recommendedWeeklyLbChange(
            currentLb: currentWeightKg * GoalCalculator.kgToLb,
            goalLb: goalWeightKg * GoalCalculator.kgToLb,
            goalType: goal
        )
        switch goal {
        case .maintain:
            weeklyLbChange = 0
        case .lose:
            weeklyLbChange = min(suggested, -0.5)
        case .gain:
            weeklyLbChange = max(suggested, focusChosen ? 0.5 : 0.25)
        }
    }

    private func updateHeightCm() {
        heightCm = Double(heightFt * 12 + heightIn) * 2.54
    }

    private func formatWeight(_ kg: Double) -> String {
        if usesImperial {
            return String(format: "%.0f lb", kg * GoalCalculator.kgToLb)
        }
        return String(format: "%.0f kg", kg)
    }

    private func formatWeightDisplay(_ displayValue: Double) -> String {
        if usesImperial {
            return String(format: "%.0f lb", displayValue)
        }
        return String(format: "%.1f kg", displayValue)
    }

    private func timelineLabel(weeks: Double) -> String {
        if weeks < 8 { return String(format: "~%.0f weeks", weeks.rounded()) }
        let months = weeks / 4.33
        return String(format: "~%.0f months (%.0f weeks)", months.rounded(), weeks.rounded())
    }

    private func planMetricRow(title: String, value: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BrandTheme.homeSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(BrandTheme.homeActionBar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BrandTheme.purple.opacity(0.25), lineWidth: 1)
        )
    }

    private func advance() {
        if step < totalSteps - 1 {
            step += 1
            if step == 3 { syncWeeklyIfNeeded() }
        } else {
            finish()
        }
    }

    private func finish() {
        saveError = nil
        let settings = persistSettings()
        ensureTodayGoal(for: settings)
        seedDefaultPhrases()

        do {
            try context.save()
            appState.hasCompletedOnboarding = true
            appState.openLarryChatOnNextAppear = true
        } catch {
            saveError = "Couldn't save your plan. Please try again."
        }
    }

    private func persistSettings() -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try? context.fetch(descriptor).first {
            applyFormValues(to: existing)
            return existing
        }

        let settings = UserSettings(
            sex: sex,
            age: age,
            heightCm: heightCmValue,
            weightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            weeklyLbChangeTarget: weeklyLbChange,
            usesImperialUnits: usesImperial,
            activity: activity,
            goalType: activeGoalType,
            trainerVoice: LarryMcQuade.defaultVoice
        )
        context.insert(settings)
        return settings
    }

    private func applyFormValues(to settings: UserSettings) {
        settings.sex = sex
        settings.age = age
        settings.heightCm = heightCmValue
        settings.weightKg = currentWeightKg
        settings.goalWeightKg = goalWeightKg
        settings.weeklyLbChangeTarget = weeklyLbChange
        settings.usesImperialUnits = usesImperial
        settings.activity = activity
        settings.goalType = activeGoalType
        if settings.trainerVoice.isEmpty {
            settings.trainerVoice = LarryMcQuade.defaultVoice
        }
    }

    private func ensureTodayGoal(for settings: UserSettings) {
        let macros = GoalCalculator.recommendedMacros(for: settings)
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyGoal>()
        let goals = (try? context.fetch(descriptor)) ?? []

        if let existing = goals.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            existing.calories = macros.calories
            existing.proteinG = macros.proteinG
            existing.carbsG = macros.carbsG
            existing.fatG = macros.fatG
        } else {
            context.insert(DailyGoal(
                date: Date(),
                calories: macros.calories,
                proteinG: macros.proteinG,
                carbsG: macros.carbsG,
                fatG: macros.fatG
            ))
        }
    }

    private var heightCmValue: Double {
        if usesImperial {
            return Double(heightFt * 12 + heightIn) * 2.54
        }
        return heightCm
    }

    private func seedDefaultPhrases() {
        let descriptor = FetchDescriptor<TrainerPhrase>()
        if let count = try? context.fetchCount(descriptor), count > 0 { return }

        let defaults = LarryMcQuade.defaultPhrases
        for (text, tag) in defaults {
            context.insert(TrainerPhrase(text: text, tag: tag))
        }
    }
}

// MARK: - Onboarding sliders

private struct PieChartDialSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let color: Color

    private let dialSize: CGFloat = 148
    private let ringWidth: CGFloat = 14

    private var progress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = size / 2 - ringWidth

                ZStack {
                    OnboardingPieSlice(progress: progress)
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.35), color.opacity(0.08)],
                                center: .center,
                                startRadius: 0,
                                endRadius: radius
                            )
                        )
                        .frame(width: radius * 2, height: radius * 2)

                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: ringWidth)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .shadow(color: color.opacity(0.55), radius: 4)
                        .offset(knobOffset(radius: radius))

                    VStack(spacing: 2) {
                        Text(formattedValue)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(BrandTheme.homePrimaryText)
                        Text(unit)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            updateValue(from: gesture.location, center: center, radius: radius)
                        }
                )
            }
            .frame(width: dialSize, height: dialSize)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(formattedValue) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = snap(value + step)
            case .decrement:
                value = snap(value - step)
            @unknown default:
                break
            }
        }
    }

    private var formattedValue: String {
        if step >= 1 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func knobOffset(radius: CGFloat) -> CGSize {
        let angle = progress * 2 * Double.pi - Double.pi / 2
        return CGSize(
            width: CGFloat(cos(angle)) * radius,
            height: CGFloat(sin(angle)) * radius
        )
    }

    private func updateValue(from location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let normalized = angle / (2 * .pi)
        let raw = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        value = snap(raw)
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct OnboardingPieSlice: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct WeeklyPaceSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: String
    var onEditingChanged: ((Bool) -> Void)? = nil

    private var progress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(valueLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)

            GeometryReader { geo in
                let trackHeight: CGFloat = 8
                let thumbSize: CGFloat = 22
                let inset: CGFloat = 11
                let usable = max(geo.size.width - inset * 2, 1)
                let thumbX = inset + progress * usable

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrandTheme.homeCard)
                        .frame(height: trackHeight)
                        .overlay {
                            Capsule()
                                .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
                        }

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandTheme.magenta, BrandTheme.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(thumbX, inset), height: trackHeight)

                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: BrandTheme.magenta.opacity(0.45), radius: 4, y: 2)
                        .overlay {
                            Circle()
                                .stroke(BrandTheme.magenta, lineWidth: 2)
                        }
                        .offset(x: thumbX - thumbSize / 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            onEditingChanged?(true)
                            updateValue(at: gesture.location.x, width: geo.size.width, inset: inset)
                        }
                        .onEnded { _ in
                            onEditingChanged?(false)
                        }
                )
            }
            .frame(height: 36)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("More disciplined")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Text("Faster pace")
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Manageable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Text("Easier to sustain")
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly pace: \(valueLabel)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = snap(value + step)
            case .decrement:
                value = snap(value - step)
            @unknown default:
                break
            }
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat, inset: CGFloat) {
        let usable = max(width - inset * 2, 1)
        let normalized = min(max((x - inset) / usable, 0), 1)
        let raw = range.lowerBound + Double(normalized) * (range.upperBound - range.lowerBound)
        value = snap(raw)
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

