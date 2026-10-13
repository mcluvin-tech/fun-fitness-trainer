import SwiftUI
import SwiftData

struct MealConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

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
    @State private var detectedBarcode: String?
    @State private var analysisSource: FoodAnalysisSource?
    @State private var isLoading = false
    @State private var hasAnalyzed = false
    @State private var errorMessage: String?
    @State private var showBarcode = false
    @State private var barcodeForLookup = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var skippedAI = false
    @State private var resolvedPayload: MealPayload?
    @State private var displayedFromAnalysis: (calories: String, protein: String, carbs: String, fat: String)?

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
                        HStack(spacing: 14) {
                            PulsingBarcodeBars(isLocked: true)
                                .frame(width: 72, height: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reading the label, then estimating the rest")
                                    .font(.subheadline.weight(.semibold))
                                Text("You can save anytime.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        Button("Use current estimate") {
                            skippedAI = true
                            analysisTask?.cancel()
                            if calories.isEmpty || protein.isEmpty {
                                applyOfflineEstimate()
                            }
                            isLoading = false
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.secondary)
                        Text("You can still edit and Save — analysis is optional.")
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
                        if analysisSource == .barcode || detectedBarcode != nil {
                            Label("Matched via barcode · Open Food Facts", systemImage: "barcode.viewfinder")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if labelDetected {
                            Label("Read from nutrition label", systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if hasAnalyzed {
                            Text("AI estimate — confirm values or scan the barcode for exact nutrition.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            barcodeForLookup = detectedBarcode ?? ""
                            showBarcode = true
                        } label: {
                            Label("Scan barcode instead", systemImage: "barcode.viewfinder")
                                .font(.subheadline.weight(.medium))
                        }

                        if hasAnalyzed && !isLoading {
                            Button("Read photo again") {
                                skippedAI = false
                                analysisTask?.cancel()
                                analysisTask = Task { await analyze() }
                            }
                            .font(.caption)
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
            .task {
                analysisTask = Task { await analyze() }
            }
            .onDisappear {
                analysisTask?.cancel()
            }
            .sheet(isPresented: $showBarcode) {
                BarcodeMealConfirmView(barcode: barcodeForLookup) {
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

    private var photoLogSource: MacroTrackingEngine.NutritionSource {
        if detectedBarcode != nil { return .manufacturer }
        if labelDetected { return .userLabel }
        return .genericEstimate
    }

    private var photoLogConfidence: MacroTrackingEngine.NutritionConfidence {
        if detectedBarcode != nil || labelDetected { return .high }
        if analysisSource == .cloudAI { return .low }
        return .medium
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
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, !skippedAI else { return }
            let barcodeMiss = (error as? FoodAnalysisError).flatMap { analysisError -> String? in
                if case .barcodeNeedsLookup(let code) = analysisError { return code }
                return nil
            }
            if barcodeMiss == nil, calories.isEmpty || protein.isEmpty {
                applyOfflineEstimate()
            }
            if let analysisError = error as? FoodAnalysisError {
                switch analysisError {
                case .labelUnreadable:
                    errorMessage = analysisError.localizedDescription
                    assumptions = [
                        "Confirm macros or scan the barcode for exact nutrition.",
                    ]
                case .networkUnavailable:
                    errorMessage = nil
                    if analysisSource == .offlineEstimate || assumptions.isEmpty {
                        assumptions = ["Confirm macros — on-device estimate."]
                    }
                case .barcodeNeedsLookup(let code):
                    barcodeForLookup = code
                    detectedBarcode = code
                    showBarcode = true
                    return
                }
            } else {
                errorMessage = nil
                if analysisSource == .offlineEstimate || assumptions.isEmpty {
                    assumptions = ["Confirm macros — on-device estimate."]
                }
            }
        }
    }

    private func applyOfflineEstimate() {
        guard calories.isEmpty && protein.isEmpty else { return }
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimate = FoodAnalysisService.offlineEstimate(from: trimmedHint.isEmpty ? nil : trimmedHint)
        applyResolvedPayload(estimate, analysisSource: .offlineEstimate, visionConfidence: nil)
        assumptions = ["On-device estimate — confirm or wait for label/AI analysis."] + estimate.assumptions
    }

    private func applyAnalysisResult(_ result: FoodAnalysisResult) {
        let resolved = FoodAnalysisService.resolvedMeal(fromPhotoAnalysis: result)
        applyResolvedPayload(
            resolved,
            analysisSource: result.source,
            visionConfidence: result.confidence
        )
        items = result.items
        labelDetected = result.labelDetected ?? false
        detectedBarcode = result.barcode
    }

    private func applyResolvedPayload(
        _ payload: MealPayload,
        analysisSource: FoodAnalysisSource?,
        visionConfidence: Double?
    ) {
        resolvedPayload = payload
        let totals = FoodAnalysisService.userFacingTotals(from: payload)
        name = payload.entriesForLogging().count == 1
            ? (payload.entriesForLogging().first?.name ?? payload.name)
            : payload.name
        let calorieText = FoodAnalysisService.formatEstimateForDisplay(
            totals.calories,
            isCalories: true,
            confidence: payload.confidence
        )
        let proteinText = FoodAnalysisService.formatEstimateForDisplay(
            totals.proteinG,
            isCalories: false,
            confidence: payload.confidence
        )
        let carbText = FoodAnalysisService.formatEstimateForDisplay(
            totals.carbsG,
            isCalories: false,
            confidence: payload.confidence
        )
        let fatText = FoodAnalysisService.formatEstimateForDisplay(
            totals.fatG,
            isCalories: false,
            confidence: payload.confidence
        )
        calories = calorieText
        protein = proteinText
        carbs = carbText
        fat = fatText
        assumptions = payload.assumptions
        confidence = visionConfidence
        self.analysisSource = analysisSource
        displayedFromAnalysis = (calorieText, proteinText, carbText, fatText)
    }

    private var userEditedDisplayedMacros: Bool {
        guard let displayedFromAnalysis else { return false }
        return displayedFromAnalysis.calories != calories
            || displayedFromAnalysis.protein != protein
            || displayedFromAnalysis.carbs != carbs
            || displayedFromAnalysis.fat != fat
    }

    private func save() {
        guard let c = Double(calories), let p = Double(protein),
              let cb = Double(carbs), let f = Double(fat) else { return }

        let photo = image.jpegDataForFoodAnalysis() ?? image.jpegData(compressionQuality: 0.7)
        let payload: MealPayload
        if userEditedDisplayedMacros {
            payload = MealPayload(
                name: FoodItemNaming.canonicalName(for: name),
                calories: c,
                proteinG: p,
                carbsG: cb,
                fatG: f,
                items: items,
                barcode: detectedBarcode,
                isLabelBacked: labelDetected || detectedBarcode != nil,
                assumptions: assumptions,
                source: .userProvided,
                confidence: .high
            )
        } else if let resolvedPayload {
            payload = resolvedPayload
        } else {
            payload = MealPayload(
                name: FoodItemNaming.canonicalName(for: name),
                calories: c,
                proteinG: p,
                carbsG: cb,
                fatG: f,
                items: items,
                barcode: detectedBarcode,
                isLabelBacked: labelDetected || detectedBarcode != nil,
                assumptions: assumptions,
                source: photoLogSource,
                confidence: photoLogConfidence
            )
        }

        let inserted = MealLogging.insertReturningMeals(
            payload,
            into: context,
            photoData: photo,
            analysisConfidence: confidence
        )
        if let snapshot = LarryReactionSnapshot.capturing(loggedMeals: inserted, in: context) {
            appState.presentLarryReaction(snapshot)
        }
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
