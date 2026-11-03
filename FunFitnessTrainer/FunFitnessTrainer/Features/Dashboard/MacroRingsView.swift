import SwiftUI

struct EditableMacroBindings {
    var calories: Binding<Double>
    var proteinG: Binding<Double>
    var carbsG: Binding<Double>
    var fatG: Binding<Double>
}

struct MacroRingsView: View {
    let consumed: MacroTotals
    let goal: MacroGoalPayload
    var exerciseCalorieBonus: Double = 0
    var stepsToday: Double? = nil
    var stepGoal: Int = 10_000
    /// When set, tapping a ring focuses that value for inline editing.
    var editableValues: EditableMacroBindings? = nil
    /// When set (and not editing), tapping a ring explains why that goal exists.
    var onExplainGoal: ((MacroGoalKind) -> Void)? = nil
    /// Dashboard mode: expand ring + show remaining story (instead of goal sheet).
    var interactiveFocus: Bool = false
    var onFocusChange: ((MacroGoalKind?) -> Void)? = nil
    var pulseKind: MacroGoalKind? = nil

    @FocusState private var focusedMacro: MacroGoalKind?
    @State private var animated = MacroTotals()
    @State private var selectedKind: MacroGoalKind?
    @State private var hasAppeared = false
    @State private var completedKinds: Set<MacroGoalKind> = []

    private let ringDiameter: CGFloat = 96
    private let ringLineWidth: CGFloat = 11
    private let pairSpacing: CGFloat = 28

    private var displayConsumed: MacroTotals {
        if let editableValues {
            return MacroTotals(
                calories: editableValues.calories.wrappedValue,
                proteinG: editableValues.proteinG.wrappedValue,
                carbsG: editableValues.carbsG.wrappedValue,
                fatG: editableValues.fatG.wrappedValue
            )
        }
        return animated
    }

    private var canExplain: Bool {
        editableValues == nil && onExplainGoal != nil && !interactiveFocus
    }

    private var remaining: MacroTotals {
        MacroTrackingEngine.remaining(consumed: displayConsumed, goal: goal)
    }

    var body: some View {
        VStack(spacing: 14) {
            if interactiveFocus {
                HStack {
                    Text("Daily Progress")
                        .font(BrandTheme.typeSection)
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Spacer()
                    if exerciseCalorieBonus > 0 {
                        Label("+\(Int(exerciseCalorieBonus)) cal", systemImage: "figure.run")
                            .font(BrandTheme.typeMeta.weight(.semibold))
                            .foregroundStyle(BrandTheme.neonBlue)
                    }
                }
            } else if exerciseCalorieBonus > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.caption.weight(.semibold))
                    Text("+\(Int(exerciseCalorieBonus)) cal earned from activity")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(BrandTheme.neonBlue)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                HStack(spacing: pairSpacing) {
                    ring(
                        title: "Cal",
                        value: displayConsumed.calories,
                        max: goal.calories,
                        color: BrandTheme.magenta,
                        kind: .calories,
                        binding: editableValues?.calories,
                        unit: "cal"
                    )
                    ring(
                        title: "Protein",
                        value: displayConsumed.proteinG,
                        max: goal.proteinG,
                        color: BrandTheme.neonBlue,
                        kind: .protein,
                        binding: editableValues?.proteinG,
                        unit: "g"
                    )
                }
                HStack(spacing: pairSpacing) {
                    ring(
                        title: "Carbs",
                        value: displayConsumed.carbsG,
                        max: goal.carbsG,
                        color: BrandTheme.teal,
                        kind: .carbs,
                        binding: editableValues?.carbsG,
                        unit: "g"
                    )
                    ring(
                        title: "Fat",
                        value: displayConsumed.fatG,
                        max: goal.fatG,
                        color: BrandTheme.purple,
                        kind: .fat,
                        binding: editableValues?.fatG,
                        unit: "g"
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)

            if interactiveFocus, let kind = selectedKind {
                focusDetail(for: kind)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            } else if canExplain {
                Text("Tap a ring to see why that goal is set")
                    .font(.caption2)
                    .foregroundStyle(BrandTheme.homeSecondaryText.opacity(0.9))
                    .frame(maxWidth: .infinity)
            }

            if let stepsToday {
                StepProgressBar(steps: stepsToday, goal: stepGoal)
                    .padding(.top, 4)
            }
        }
        .padding(interactiveFocus ? 16 : 0)
        .modifier(OptionalElevatedSurface(enabled: interactiveFocus))
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            animated = MacroTotals()
            withAnimation(.spring(response: 0.92, dampingFraction: 0.78)) {
                animated = consumed
            }
            checkCompletions(for: consumed, haptic: false)
        }
        .onChange(of: consumed) { old, new in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                animated = new
            }
            checkCompletions(for: new, haptic: true)
            if interactiveFocus, old != new {
                // Keep selection in sync after logging.
            }
        }
        .toolbar {
            if focusedMacro != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedMacro = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func focusDetail(for kind: MacroGoalKind) -> some View {
        let (value, max, rem, color, unit) = metrics(for: kind)
        let pct = Int(MacroTrackingEngine.percentOfTarget(consumed: value, target: max).rounded())
        let remText: String = {
            if rem >= 0 {
                return unit == "cal"
                    ? "\(MacroTrackingEngine.displayCalories(rem)) remaining"
                    : "\(MacroTrackingEngine.displayGrams(rem))g remaining"
            } else {
                return unit == "cal"
                    ? "\(MacroTrackingEngine.displayCalories(-rem)) over"
                    : "\(MacroTrackingEngine.displayGrams(-rem))g over"
            }
        }()

        VStack(spacing: 4) {
            Text("\(remText) · You’re \(pct)% there")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)
                .multilineTextAlignment(.center)
            if let onExplainGoal {
                Button("Why this goal?") {
                    onExplainGoal(kind)
                }
                .font(BrandTheme.typeMeta.weight(.medium))
                .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func metrics(for kind: MacroGoalKind) -> (Double, Double, Double, Color, String) {
        switch kind {
        case .calories:
            return (displayConsumed.calories, goal.calories, remaining.calories, BrandTheme.magenta, "cal")
        case .protein:
            return (displayConsumed.proteinG, goal.proteinG, remaining.proteinG, BrandTheme.neonBlue, "g")
        case .carbs:
            return (displayConsumed.carbsG, goal.carbsG, remaining.carbsG, BrandTheme.teal, "g")
        case .fat:
            return (displayConsumed.fatG, goal.fatG, remaining.fatG, BrandTheme.purple, "g")
        }
    }

    private func ring(
        title: String,
        value: Double,
        max: Double,
        color: Color,
        kind: MacroGoalKind,
        binding: Binding<Double>?,
        unit: String
    ) -> some View {
        let progress = max > 0 ? min(Swift.max(value / max, 0), 1) : 0
        let isEditFocused = focusedMacro == kind
        let isSelected = selectedKind == kind
        let isEditable = binding != nil
        let dimmed = interactiveFocus && selectedKind != nil && !isSelected
        let expanded = interactiveFocus && isSelected
        let pulsing = pulseKind == kind

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(isSelected || isEditFocused ? 0.32 : 0.16), lineWidth: ringLineWidth)
                    .shadow(color: (expanded || pulsing) ? color.opacity(0.45) : .clear, radius: expanded ? 16 : 10)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.75), color, color.opacity(0.9)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(expanded || pulsing ? 0.55 : 0.22), radius: pulsing ? 12 : 6)

                if let binding {
                    TextField(
                        "0",
                        value: binding,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .focused($focusedMacro, equals: kind)
                    .frame(width: ringDiameter - 32)
                    .opacity(isEditFocused ? 1 : 0)
                    .allowsHitTesting(isEditFocused)

                    if !isEditFocused {
                        ringCenterLabel(value: value, max: max)
                            .allowsHitTesting(false)
                    }
                } else {
                    ringCenterLabel(value: value, max: max)
                }
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .scaleEffect(expanded ? 1.14 : (dimmed ? 0.88 : (pulsing ? 1.08 : 1)))
            .opacity(dimmed ? 0.42 : 1)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: selectedKind)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: pulseKind)
            .contentShape(Circle())
            .onTapGesture {
                if isEditable {
                    focusedMacro = kind
                } else if kind == .calories, let onExplainGoal {
                    onExplainGoal(.calories)
                    HomeHaptics.soft()
                } else if interactiveFocus {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedKind = selectedKind == kind ? nil : kind
                    }
                    onFocusChange?(selectedKind)
                    HomeHaptics.soft()
                } else if let onExplainGoal {
                    onExplainGoal(kind)
                }
            }

            Text(title)
                .font(.caption2.weight(isSelected || isEditFocused ? .bold : .medium))
                .foregroundStyle(isSelected || isEditFocused ? color : BrandTheme.homeSecondaryText)
        }
        .frame(width: ringDiameter + (expanded ? 8 : 0))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(MacroTrackingEngine.displayCalories(value)) of \(MacroTrackingEngine.displayCalories(max))")
        .accessibilityAddTraits((isEditable || canExplain || interactiveFocus) ? .isButton : [])
        .accessibilityHint(
            isEditable
                ? "Double tap to edit"
                : (kind == .calories && onExplainGoal != nil
                    ? "Double tap to see why this calorie goal is set"
                    : (interactiveFocus ? "Double tap to focus this macro" : (canExplain ? "Double tap to hear why this goal is set" : "")))
        )
        .accessibilityAction(named: isEditable ? "Edit" : (kind == .calories && onExplainGoal != nil ? "Why this goal" : (interactiveFocus ? "Focus" : "Why this goal"))) {
            if isEditable {
                focusedMacro = kind
            } else if kind == .calories, let onExplainGoal {
                onExplainGoal(.calories)
            } else if interactiveFocus {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedKind = selectedKind == kind ? nil : kind
                }
                onFocusChange?(selectedKind)
            } else if let onExplainGoal {
                onExplainGoal(kind)
            }
        }
    }

    private func ringCenterLabel(value: Double, max: Double) -> some View {
        VStack(spacing: 1) {
            Text("\(MacroTrackingEngine.displayCalories(value))")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(BrandTheme.homePrimaryText)
                .contentTransition(.numericText())
            Text("/ \(MacroTrackingEngine.displayCalories(max))")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(BrandTheme.homeTertiaryText)
        }
    }

    private func checkCompletions(for totals: MacroTotals, haptic: Bool) {
        let pairs: [(MacroGoalKind, Double, Double)] = [
            (.calories, totals.calories, goal.calories),
            (.protein, totals.proteinG, goal.proteinG),
            (.carbs, totals.carbsG, goal.carbsG),
            (.fat, totals.fatG, goal.fatG),
        ]
        for (kind, value, max) in pairs where max > 0 && value >= max {
            if !completedKinds.contains(kind) {
                completedKinds.insert(kind)
                if haptic { HomeHaptics.ringComplete() }
            }
        }
    }
}

struct CalorieGoalSheet: View {
    @Bindable var settings: UserSettings
    var exerciseCalorieBonus: Double
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var plan: FitnessPlan {
        GoalCalculator.buildPlan(for: settings)
    }

    private var explanation: MacroGoalExplanation {
        GoalCalculator.explanation(
            for: .calories,
            settings: settings,
            exerciseCalorieBonus: exerciseCalorieBonus,
            displayedGoal: plan.macros
        )
    }

    private var nudge: Double {
        min(settings.resolvedCalorieNudge, plan.maxCalorieNudge)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            LarryAvatarView(portrait: .home, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(explanation.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(BrandTheme.homePrimaryText)
                                Text(explanation.subtitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(BrandTheme.magenta)
                            }
                        }

                        Text(explanation.body)
                            .font(.body)
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        nudgeControl

                        HStack(spacing: 8) {
                            macroChip("Protein", "\(Int(plan.macros.proteinG.rounded()))g")
                            macroChip("Carbs", "\(Int(plan.macros.carbsG.rounded()))g")
                            macroChip("Fat", "\(Int(plan.macros.fatG.rounded()))g")
                        }

                        Text(plan.dietStyle.summary)
                            .font(.caption)
                            .foregroundStyle(BrandTheme.homeSecondaryText)

                        Text("Macros don't lie. People do.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elevatedSurface(cornerRadius: 16, glow: BrandTheme.magenta)
                    .padding()
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: settings.calorieNudgeKcal) { _, _ in
            try? context.save()
        }
    }

    @ViewBuilder
    private var nudgeControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pull the goal a little lower")
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)

            if plan.maxCalorieNudge < GoalCalculator.calorieNudgeStep {
                Text("This target is already on the calorie floor, so it can't go lower.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            } else {
                HStack {
                    Text("Calculated \(Int(plan.calculatedCalories))")
                    Spacer()
                    Text(nudge == 0 ? "On plan" : "−\(Int(nudge)) cal")
                        .foregroundStyle(BrandTheme.magenta)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)

                Slider(
                    value: Binding(
                        get: { nudge },
                        set: { newValue in
                            let stepped = (newValue / GoalCalculator.calorieNudgeStep).rounded() * GoalCalculator.calorieNudgeStep
                            settings.calorieNudgeKcal = min(max(stepped, 0), plan.maxCalorieNudge)
                        }
                    ),
                    in: 0...plan.maxCalorieNudge,
                    step: GoalCalculator.calorieNudgeStep
                )
                .tint(BrandTheme.magenta)

                HStack {
                    Text("Plan")
                    Spacer()
                    Text("Goal \(Int(plan.targetCalories))")
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Spacer()
                    Text("−\(Int(plan.maxCalorieNudge))")
                }
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            }
        }
        .padding(14)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 12))
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
        .padding(.vertical, 8)
        .background(BrandTheme.homeActionBar, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MacroGoalExplanationSheet: View {
    let explanation: MacroGoalExplanation
    @Environment(\.dismiss) private var dismiss

    private var accent: Color {
        switch explanation.kind {
        case .calories: return BrandTheme.magenta
        case .protein: return BrandTheme.neonBlue
        case .carbs: return BrandTheme.teal
        case .fat: return BrandTheme.purple
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            LarryAvatarView(portrait: .home, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(explanation.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(BrandTheme.homePrimaryText)
                                Text(explanation.subtitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(accent)
                            }
                        }

                        Text(explanation.body)
                            .font(.body)
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Macros don't lie. People do.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elevatedSurface(cornerRadius: 16, glow: accent)
                    .padding()
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle(explanation.kind.shortTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct StepProgressBar: View {
    let steps: Double
    var goal: Int = 10_000

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(steps / Double(goal), 1.2)
    }

    private var hitGoal: Bool {
        steps >= Double(goal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text("\(Int(steps).formatted()) / \(goal.formatted()) steps")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: hitGoal ? "figure.walk.motion" : "figure.walk")
                }
                .foregroundStyle(hitGoal ? BrandTheme.teal : BrandTheme.homeSecondaryText)
                Spacer()
                if hitGoal {
                    Text("Goal hit")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrandTheme.teal)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrandTheme.homeSecondaryText.opacity(0.2))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandTheme.teal, BrandTheme.neonBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * min(progress, 1)))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Steps \(Int(steps)) of \(goal)")
    }
}

private struct OptionalElevatedSurface: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.elevatedSurface(cornerRadius: 22, glow: BrandTheme.purple)
        } else {
            content
        }
    }
}
