import SwiftUI
import SwiftData

struct MealConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let image: UIImage
    var onSaved: (() -> Void)?

    @State private var hint = ""
    @State private var name = "Meal"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var items: [String] = []
    @State private var assumptions: [String] = []
    @State private var confidence: Double?
    @State private var labelDetected = false
    @State private var isLoading = false
    @State private var hasAnalyzed = false
    @State private var errorMessage: String?
    @State private var showBarcode = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var skippedAI = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Food photo")
                }

                if isLoading {
                    Section {
                        ProgressView("Analyzing…")
                        Text("Slow connection? You can save the estimate below or tap Skip AI.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Skip AI") {
                            skippedAI = true
                            analysisTask?.cancel()
                            isLoading = false
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                        Text("Edit the values below and save — no need to wait for AI.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Hint (optional)", text: $hint, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    macrosCard
                } header: {
                    Text("Nutrition")
                } footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        if labelDetected {
                            Label("Read from nutrition label", systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if hasAnalyzed {
                            Text("AI estimate — confirm values or scan the barcode for exact nutrition.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            showBarcode = true
                        } label: {
                            Label("Scan barcode instead", systemImage: "barcode.viewfinder")
                                .font(.subheadline.weight(.medium))
                        }

                        if hasAnalyzed && !isLoading {
                            Button("Re-analyze with hint") {
                                skippedAI = false
                                analysisTask?.cancel()
                                analysisTask = Task { await analyze() }
                            }
                            .font(.caption)
                            .disabled(hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if !assumptions.isEmpty {
                    Section("Assumptions") {
                        ForEach(assumptions, id: \.self) { Text($0).font(.caption) }
                    }
                }

                Section {
                    Text("Estimates only — not medical advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Confirm meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                applyOfflineEstimate()
            }
            .task {
                analysisTask = Task { await analyze() }
            }
            .onDisappear {
                analysisTask?.cancel()
            }
            .sheet(isPresented: $showBarcode) {
                BarcodeMealConfirmView(barcode: "") {
                    onSaved?()
                    dismiss()
                }
            }
        }
    }

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacroTextFieldRow(
                label: "Calories",
                unit: "cal",
                color: BrandTheme.magenta,
                text: $calories
            )
            macroDivider
            MacroTextFieldRow(
                label: "Protein",
                unit: "g",
                color: BrandTheme.neonBlue,
                text: $protein
            )
            macroDivider
            MacroTextFieldRow(
                label: "Carbs",
                unit: "g",
                color: BrandTheme.teal,
                text: $carbs
            )
            macroDivider
            MacroTextFieldRow(
                label: "Fat",
                unit: "g",
                color: BrandTheme.purple,
                text: $fat
            )
        }
        .listRowInsets(EdgeInsets())
    }

    private var macroDivider: some View {
        Divider().padding(.leading, 38)
    }

    private var canSave: Bool {
        Double(calories) != nil && Double(protein) != nil
    }

    private func analyze() async {
        guard !skippedAI else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasAnalyzed = true
        }
        do {
            let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await FoodAnalysisService.analyze(
                image: image,
                hint: trimmedHint.isEmpty ? nil : trimmedHint
            )
            guard !Task.isCancelled, !skippedAI else { return }
            applyAnalysisResult(result)
        } catch {
            guard !Task.isCancelled, !skippedAI else { return }
            if calories.isEmpty || protein.isEmpty {
                applyOfflineEstimate()
            }
            if let urlError = error as? URLError, urlError.code == .timedOut {
                errorMessage = "Connection timed out. Saved values are a rough estimate — edit and save."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyOfflineEstimate() {
        guard calories.isEmpty && protein.isEmpty else { return }
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimate = FoodAnalysisService.offlineEstimate(from: trimmedHint.isEmpty ? nil : trimmedHint)
        let entry = estimate.entriesForLogging().first
        name = entry?.name ?? estimate.name
        calories = formatMacro(entry?.calories ?? estimate.calories)
        protein = formatMacro(entry?.proteinG ?? estimate.proteinG)
        carbs = formatMacro(entry?.carbsG ?? estimate.carbsG)
        fat = formatMacro(entry?.fatG ?? estimate.fatG)
        assumptions = ["Offline estimate — confirm or wait for AI on a faster connection."]
    }

    private func applyAnalysisResult(_ result: FoodAnalysisResult) {
        name = result.items.first ?? "Meal"
        calories = formatMacro(result.calories)
        protein = formatMacro(result.proteinG)
        carbs = formatMacro(result.carbsG)
        fat = formatMacro(result.fatG)
        items = result.items
        assumptions = result.assumptions
        confidence = result.confidence
        labelDetected = result.labelDetected ?? false
    }

    private func formatMacro(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", value)
    }

    private func save() {
        guard let c = Double(calories), let p = Double(protein),
              let cb = Double(carbs), let f = Double(fat) else { return }

        let payload = MealPayload(
            name: FoodItemNaming.canonicalName(for: name),
            calories: c,
            proteinG: p,
            carbsG: cb,
            fatG: f,
            items: items
        )
        let photo = image.jpegData(compressionQuality: 0.7)
        let entries = payload.entriesForLogging()

        if entries.count > 1 {
            for entry in entries {
                let meal = Meal(
                    name: entry.name,
                    calories: entry.calories,
                    proteinG: entry.proteinG,
                    carbsG: entry.carbsG,
                    fatG: entry.fatG,
                    photoData: photo,
                    assumptions: assumptions,
                    confidence: confidence,
                    isEstimate: !labelDetected
                )
                context.insert(meal)
                MealLogging.shareToPack(meal: meal)
            }
        } else {
            let entry = entries.first
            let meal = Meal(
                name: entry?.name ?? FoodItemNaming.canonicalName(for: name),
                calories: c,
                proteinG: p,
                carbsG: cb,
                fatG: f,
                photoData: photo,
                items: items,
                assumptions: assumptions,
                confidence: confidence,
                isEstimate: !labelDetected
            )
            context.insert(meal)
            MealLogging.shareToPack(meal: meal)
        }
        try? context.save()
        onSaved?()
        dismiss()
    }
}

private struct MacroTextFieldRow: View {
    let label: String
    let unit: String
    let color: Color
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 64, alignment: .leading)

            Spacer(minLength: 8)

            TextField("0", text: $text)
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
        .accessibilityLabel("\(label): \(text.isEmpty ? "empty" : text) \(unit)")
    }
}
