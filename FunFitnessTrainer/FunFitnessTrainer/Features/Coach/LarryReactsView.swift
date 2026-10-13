import SwiftUI
import SwiftData
import UIKit

/// Captured meal-log moment that drives the food-logged confirmation.
struct LarryReactionSnapshot: Identifiable, Equatable {
    let id: UUID
    var mealName: String
    var photoData: Data?
    var delta: MacroTotals
    var previousConsumed: MacroTotals
    var newConsumed: MacroTotals
    var goal: MacroGoalPayload?
    var mealsLoggedToday: Int
    var loggedMealCount: Int
    var streakDays: Int

    init(
        id: UUID = UUID(),
        mealName: String,
        photoData: Data? = nil,
        delta: MacroTotals,
        previousConsumed: MacroTotals,
        newConsumed: MacroTotals,
        goal: MacroGoalPayload?,
        mealsLoggedToday: Int,
        loggedMealCount: Int,
        streakDays: Int
    ) {
        self.id = id
        self.mealName = mealName
        self.photoData = photoData
        self.delta = delta
        self.previousConsumed = previousConsumed
        self.newConsumed = newConsumed
        self.goal = goal
        self.mealsLoggedToday = mealsLoggedToday
        self.loggedMealCount = loggedMealCount
        self.streakDays = streakDays
    }

    static func capturing(loggedMeals: [Meal], in context: ModelContext) -> LarryReactionSnapshot? {
        guard !loggedMeals.isEmpty else { return nil }

        let allMeals = (try? context.fetch(FetchDescriptor<Meal>())) ?? loggedMeals
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>())) ?? []
        let today = DaySummaryService.mealsToday(from: allMeals)
        let consumed = DaySummaryService.totals(for: today)
        let delta = MacroTotals(
            calories: loggedMeals.reduce(0) { $0 + $1.calories },
            proteinG: loggedMeals.reduce(0) { $0 + $1.proteinG },
            carbsG: loggedMeals.reduce(0) { $0 + $1.carbsG },
            fatG: loggedMeals.reduce(0) { $0 + $1.fatG }
        )
        let previous = MacroTotals(
            calories: max(0, consumed.calories - delta.calories),
            proteinG: max(0, consumed.proteinG - delta.proteinG),
            carbsG: max(0, consumed.carbsG - delta.carbsG),
            fatG: max(0, consumed.fatG - delta.fatG)
        )

        var goal: MacroGoalPayload?
        if let settings = settings.first {
            goal = GoalCalculator.recommendedMacros(for: settings)
        }

        let name: String
        if loggedMeals.count == 1 {
            name = FoodItemNaming.displayTitle(for: loggedMeals[0].name)
        } else {
            let first = FoodItemNaming.displayTitle(for: loggedMeals[0].name)
            name = "\(first) +\(loggedMeals.count - 1)"
        }

        return LarryReactionSnapshot(
            mealName: name,
            photoData: loggedMeals.first(where: { $0.photoData != nil })?.photoData,
            delta: delta,
            previousConsumed: previous,
            newConsumed: consumed,
            goal: goal,
            mealsLoggedToday: today.count,
            loggedMealCount: loggedMeals.count,
            streakDays: DaySummaryService.streakDays(meals: allMeals)
        )
    }
}

/// Confirmation after a food log. Progress, the meal, then Larry — Done stays tappable.
struct LarryReactsView: View {
    let snapshot: LarryReactionSnapshot
    var onDone: () -> Void
    var onTalkToLarry: () -> Void

    private let presentation: LarryReactionPresentation

    @State private var displayedConsumed: MacroTotals

    init(
        snapshot: LarryReactionSnapshot,
        onDone: @escaping () -> Void,
        onTalkToLarry: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.onDone = onDone
        self.onTalkToLarry = onTalkToLarry
        self.presentation = LarryReactionComposer.present(snapshot: snapshot)
        _displayedConsumed = State(initialValue: snapshot.previousConsumed)
    }

    var body: some View {
        ZStack {
            reactionBackdrop

            VStack(spacing: 12) {
                ScrollView {
                    VStack(spacing: 12) {
                        dailyHeader
                        mealCard
                        LarryReactionCard(
                            pose: presentation.pose,
                            quote: presentation.quote,
                            motion: presentation.motion
                        )
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)

                bottomActions
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                displayedConsumed = snapshot.newConsumed
            }
            playHaptic()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var reactionBackdrop: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.06)
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.03, blue: 0.10),
                    Color(red: 0.03, green: 0.02, blue: 0.07),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [BrandTheme.purple.opacity(0.16), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }

    private var dailyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let goal = snapshot.goal {
                rollingRow(
                    label: "Calories",
                    value: displayedConsumed.calories,
                    goal: goal.calories,
                    unit: "cal",
                    color: BrandTheme.magenta
                )
                rollingRow(
                    label: "Protein",
                    value: displayedConsumed.proteinG,
                    goal: goal.proteinG,
                    unit: "g",
                    color: BrandTheme.neonBlue,
                    asGrams: true
                )
            } else {
                HStack {
                    RollingMetric(value: displayedConsumed.calories, suffix: " cal")
                    Spacer()
                    RollingMetric(value: displayedConsumed.proteinG, suffix: "g P")
                }
                .font(.headline.weight(.heavy))
                .foregroundStyle(BrandTheme.homePrimaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func rollingRow(
        label: String,
        value: Double,
        goal: Double,
        unit: String,
        color: Color,
        asGrams: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingMetric(value: value, suffix: "", asGrams: asGrams)
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Text("/ \(asGrams ? MacroTrackingEngine.displayGrams(goal) : MacroTrackingEngine.displayCalories(goal)) \(unit)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.homeTertiaryText)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * CGFloat(min(value / max(goal, 1), 1))))
                }
            }
            .frame(height: 6)
        }
    }

    private var mealCard: some View {
        HStack(spacing: 14) {
            mealThumb

            VStack(alignment: .leading, spacing: 4) {
                Text("Logged.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandTheme.homeTertiaryText)
                Text(snapshot.mealName)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if snapshot.delta.calories > 0.4 {
                        deltaChip(
                            "+\(MacroTrackingEngine.displayCalories(snapshot.delta.calories)) cal",
                            color: BrandTheme.magenta
                        )
                    }
                    if snapshot.delta.proteinG > 0.2 {
                        deltaChip(
                            "+\(MacroTrackingEngine.displayGrams(snapshot.delta.proteinG))g protein",
                            color: BrandTheme.neonBlue
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private var mealThumb: some View {
        if let data = snapshot.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandTheme.purple.opacity(0.28))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BrandTheme.teal)
                }
        }
    }

    private func deltaChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.92), in: Capsule())
    }

    private var bottomActions: some View {
        VStack(spacing: 8) {
            Button(action: onDone) {
                Text("Done")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(BrandTheme.teal, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")

            Button(action: onTalkToLarry) {
                Text("Tell Larry something")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var accessibilitySummary: String {
        "\(snapshot.mealName) logged. \(MacroTrackingEngine.displayCalories(snapshot.delta.calories)) calories, \(MacroTrackingEngine.displayGrams(snapshot.delta.proteinG)) grams of protein. Larry says \(presentation.quote)"
    }

    private func playHaptic() {
        switch presentation.category {
        case .great, .good:
            HomeHaptics.success()
        case .bad, .disaster:
            HomeHaptics.warning()
        case .neutral, .questionable:
            HomeHaptics.soft()
        }
    }
}

struct LarryFloatingLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundStyle(BrandTheme.homePrimaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            .accessibilityLabel(text)
    }
}

private struct RollingMetric: View, Animatable {
    var value: Double
    var suffix: String
    var asGrams: Bool = false

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let number = asGrams
            ? MacroTrackingEngine.displayGrams(value)
            : MacroTrackingEngine.displayCalories(value)
        Text("\(number)\(suffix)")
            .monospacedDigit()
    }
}
