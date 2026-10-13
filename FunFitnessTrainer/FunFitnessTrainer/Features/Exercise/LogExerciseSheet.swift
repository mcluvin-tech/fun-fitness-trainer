import SwiftUI
import SwiftData

struct LogExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    @State private var showManual = false

    private var weightKg: Double {
        settingsList.first?.weightKg ?? 75
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(BrandTheme.neonBlue)
                    .padding(.top, 8)

                Text("Log exercise")
                    .font(.title2.bold())

                Text("Burned calories are tracked. They don't add extra food to today's target.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    ForEach(ExercisePreset.allCases) { preset in
                        let estimate = ExerciseEstimateService.preset(preset, weightKg: weightKg)
                        Button {
                            save(estimate)
                        } label: {
                            HStack {
                                Image(systemName: preset.icon)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.rawValue)
                                        .font(.body.weight(.semibold))
                                    Text("~\(Int(estimate.caloriesBurned)) cal burned")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(Int(estimate.caloriesBurned))")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrandTheme.neonBlue)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showManual = true
                    } label: {
                        Label("Enter manually", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Text("Estimates based on your weight — not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showManual) {
                ManualExerciseEntryView()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save(_ payload: ExercisePayload) {
        ExerciseLogging.insert(payload, into: context)
        dismiss()
    }
}

struct ManualExerciseEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var calories = ""
    @State private var minutes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Activity", text: $name)
                TextField("Calories burned", text: $calories)
                    .keyboardType(.decimalPad)
                TextField("Duration (min, optional)", text: $minutes)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Manual exercise")
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
        guard let burn = Double(calories) else { return }
        let payload = ExercisePayload(
            name: name,
            caloriesBurned: burn,
            durationMinutes: Double(minutes)
        )
        ExerciseLogging.insert(payload, into: context)
        dismiss()
    }
}
