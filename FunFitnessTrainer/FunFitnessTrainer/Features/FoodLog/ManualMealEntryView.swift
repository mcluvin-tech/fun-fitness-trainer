import SwiftUI
import SwiftData

struct ManualMealEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

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
        guard let c = Double(calories), let p = Double(protein) else { return }
        let cb = Double(carbs) ?? 0
        let f = Double(fat) ?? 0
        let meal = Meal(
            name: FoodItemNaming.canonicalName(for: name),
            calories: c,
            proteinG: p,
            carbsG: cb,
            fatG: f,
            isEstimate: false
        )
        context.insert(meal)
        try? context.save()
        MealLogging.shareToPack(meal: meal)
        dismiss()
    }
}

struct MealEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var meal: Meal
    @Query private var goals: [DailyGoal]
    @Query private var settingsList: [UserSettings]

    private var displayGoal: MacroGoalPayload? {
        if let goal = DaySummaryService.goal(for: Date(), goals: goals) {
            return MacroGoalPayload(
                calories: goal.calories,
                proteinG: goal.proteinG,
                carbsG: goal.carbsG,
                fatG: goal.fatG
            )
        }
        if let settings = settingsList.first {
            return GoalCalculator.recommendedMacros(for: settings)
        }
        return nil
    }

    private var mealTotals: MacroTotals {
        MacroTotals(
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                nameCard

                if let goal = displayGoal {
                    ringsCard(goal: goal)
                }

                macrosCard

                deleteButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edit meal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeStoredName()
        }
        .onDisappear {
            normalizeStoredName()
            try? context.save()
        }
    }

    private func normalizeStoredName() {
        let cleaned = FoodItemNaming.canonicalName(for: meal.name)
        if cleaned != meal.name {
            meal.name = cleaned
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meal name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextField("What did you eat?", text: $meal.name)
                .font(.headline)

            HStack(spacing: 8) {
                if meal.barcode != nil {
                    MealTagChip(text: "Barcode", icon: "barcode", tint: BrandTheme.teal)
                }
                if meal.isEstimate {
                    MealTagChip(text: "Estimate", icon: "sparkles", tint: BrandTheme.magenta)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func ringsCard(goal: MacroGoalPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This meal vs daily targets")
                .font(.subheadline.weight(.semibold))

            MacroRingsView(consumed: mealTotals, goal: goal)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit macros")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            MacroEditRow(label: "Calories", unit: "cal", color: BrandTheme.magenta, value: $meal.calories)
            macroDivider
            MacroEditRow(label: "Protein", unit: "g", color: BrandTheme.neonBlue, value: $meal.proteinG)
            macroDivider
            MacroEditRow(label: "Carbs", unit: "g", color: BrandTheme.teal, value: $meal.carbsG)
            macroDivider
            MacroEditRow(label: "Fat", unit: "g", color: BrandTheme.purple, value: $meal.fatG)
                .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var macroDivider: some View {
        Divider().padding(.leading, 38)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            context.delete(meal)
            try? context.save()
            dismiss()
        } label: {
            Label("Delete meal", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MacroEditRow: View {
    let label: String
    let unit: String
    let color: Color
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 64, alignment: .leading)

            Spacer(minLength: 8)

            TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value)) \(unit)")
    }
}

private struct MealTagChip: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
