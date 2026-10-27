import SwiftUI
import SwiftData

struct ManualMealEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal name", text: $name)
                TextField("Calories", text: $calories).keyboardType(.decimalPad)
                TextField("Protein (g)", text: $protein).keyboardType(.decimalPad)
                TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad)
                TextField("Fat (g)", text: $fat).keyboardType(.decimalPad)
            }
            .navigationTitle("Manual log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || Double(calories) == nil)
                }
            }
        }
    }

    private func save() {
        guard let c = Double(calories) else { return }
        let p = Double(protein) ?? 0
        let cb = Double(carbs) ?? 0
        let f = Double(fat) ?? 0
        let payload = MealPayload(
            name: FoodItemNaming.canonicalName(for: name),
            calories: c,
            proteinG: p,
            carbsG: cb,
            fatG: f,
            isLabelBacked: true,
            source: .userProvided,
            confidence: .high
        )
        let inserted = MealLogging.insertReturningMeals(payload, into: context)
        if let snapshot = LarryReactionSnapshot.capturing(loggedMeals: inserted, in: context) {
            appState.presentLarryReaction(snapshot)
        }
        dismiss()
    }
}

struct MealEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var meal: Meal
    @Query private var settingsList: [UserSettings]
    @State private var servingCount: Double = 1
    @State private var appliedServingCount: Double?

    private var displayGoal: MacroGoalPayload? {
        DaySummaryService.foodTarget(from: settingsList.first)
    }

    private var mealTotals: MacroTotals {
        MacroTotals(
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG
        )
    }

    /// Live food target from UserSettings; placeholders if onboarding isn't done.
    private var ringsGoal: MacroGoalPayload {
        if let displayGoal { return displayGoal }
        return MacroGoalPayload(
            calories: max(meal.calories, 500),
            proteinG: max(meal.proteinG, 50),
            carbsG: max(meal.carbsG, 50),
            fatG: max(meal.fatG, 20)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                nameCard
                ringsCard(goal: ringsGoal)
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            HomeDarkBackground()
        }
        .navigationTitle("Edit meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            normalizeStoredName()
            let start = max(meal.quantity ?? 1, 0.25)
            appliedServingCount = start
            servingCount = start
        }
        .onDisappear {
            normalizeStoredName()
            try? context.save()
        }
    }

    private var servingCountText: String {
        servingCount == floor(servingCount) ? String(Int(servingCount)) : String(format: "%g", servingCount)
    }

    private func normalizeStoredName() {
        let cleaned = FoodItemNaming.canonicalName(for: meal.name)
        if cleaned != meal.name {
            meal.name = cleaned
        }
    }

    private func applyServingChange(to newValue: Double) {
        guard let previous = appliedServingCount, abs(previous - newValue) > 0.001 else { return }
        let scaled = MacroTrackingEngine.scaledForQuantityChange(mealTotals, from: previous, to: newValue)
        meal.calories = scaled.calories
        meal.proteinG = scaled.proteinG
        meal.carbsG = scaled.carbsG
        meal.fatG = scaled.fatG
        meal.quantity = newValue
        appliedServingCount = newValue
    }

    private var nameCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Meal name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .textCase(.uppercase)
                    .tracking(0.6)

                TextField("What did you eat?", text: $meal.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .tint(BrandTheme.magenta)

                Stepper(value: $servingCount, in: 0.25...20, step: 0.25) {
                    Text("Servings \(servingCountText)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                }
                .onChange(of: servingCount) { _, newValue in
                    applyServingChange(to: newValue)
                }

                HStack(spacing: 8) {
                    if meal.confidenceKind == .high {
                        MealTagChip(text: meal.barcode != nil ? "Barcode" : "Label", icon: meal.barcode != nil ? "barcode" : "doc.text.magnifyingglass", tint: BrandTheme.teal)
                    } else if meal.confidenceKind == .low {
                        MealTagChip(text: "Low confidence", icon: "questionmark.circle", tint: BrandTheme.magenta)
                    }
                    if meal.isEstimate || meal.confidenceKind == .medium {
                        MealTagChip(text: "Estimate", icon: "sparkles", tint: BrandTheme.magenta)
                    }
                }
            }
        }
    }

    private func ringsCard(goal: MacroGoalPayload) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This meal vs daily targets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)

                    Text("Edit macros")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BrandTheme.homeSecondaryText)

                    Text("Tap a circle if the estimate wasn’t accurate.")
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.homeSecondaryText.opacity(0.85))
                }

                MacroRingsView(
                    consumed: mealTotals,
                    goal: goal,
                    editableValues: EditableMacroBindings(
                        calories: $meal.calories,
                        proteinG: $meal.proteinG,
                        carbsG: $meal.carbsG,
                        fatG: $meal.fatG
                    )
                )
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            context.delete(meal)
            try? context.save()
            dismiss()
        } label: {
            Label("Delete meal", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Color.red.opacity(0.95))
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.red.opacity(0.28), lineWidth: 1)
                }
        }
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(BrandTheme.homeCard.opacity(0.28))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        BrandTheme.purple.opacity(0.45),
                                        BrandTheme.teal.opacity(0.22),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: BrandTheme.purple.opacity(0.22), radius: 18, y: 8)
            }
    }
}

private struct MealTagChip: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
            .foregroundStyle(tint)
    }
}








