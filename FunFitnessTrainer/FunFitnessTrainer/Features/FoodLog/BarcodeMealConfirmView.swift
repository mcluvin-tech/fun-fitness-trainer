import SwiftUI
import SwiftData

/// Sheet payload so the scanned code is not lost when the camera cover dismisses.
struct PendingBarcodeScan: Identifiable, Hashable {
    let id = UUID()
    let code: String

    init(_ code: String = "") {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BarcodeMealConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    let barcode: String
    var onSaved: (() -> Void)?

    @State private var manualBarcode: String
    @State private var product: BarcodeProductResult?
    @State private var servings: Double = 1
    @State private var isLoading: Bool
    @State private var errorMessage: String?

    init(barcode: String, onSaved: (() -> Void)? = nil) {
        self.barcode = barcode
        self.onSaved = onSaved
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        _manualBarcode = State(initialValue: trimmed)
        _isLoading = State(initialValue: !trimmed.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                if product == nil && !isLoading {
                    Section("Barcode") {
                        if !barcode.isEmpty {
                            Text("Scanned: \(BarcodeNormalization.normalizedBarcode(barcode))")
                                .font(.headline)
                            Text(errorMessage ?? "Looking up this product failed. Try again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Look up again") {
                                Task { await lookup(barcode: barcode) }
                            }
                        } else {
                            TextField("Enter barcode", text: $manualBarcode)
                                .keyboardType(.numberPad)
                            Button("Look up product") {
                                Task { await lookup(barcode: manualBarcode) }
                            }
                            .disabled(manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        }
                    }
                }

                if isLoading {
                    Section {
                        ProgressView("Looking up nutrition…")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                if let product {
                    Section {
                        if let url = product.imageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 160)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                default:
                                    EmptyView()
                                }
                            }
                        }

                        Text(product.name)
                            .font(.headline)
                        Text("Barcode: \(product.barcode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Servings") {
                        Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                            Text(servingLabel(for: product))
                        }
                    }

                    Section("Nutrition") {
                        LabeledContent("Calories", value: "\(scaledMacros.displayedCalories)")
                        LabeledContent("Protein", value: "\(scaledMacros.displayedProteinG) g")
                        LabeledContent("Carbs", value: "\(scaledMacros.displayedCarbsG) g")
                        LabeledContent("Fat", value: "\(scaledMacros.displayedFatG) g")
                    }

                    Section {
                        Text("Data from Open Food Facts. Confirm before saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Scan result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(product == nil || isLoading)
                }
            }
            .task {
                manualBarcode = barcode
                if !barcode.isEmpty {
                    await lookup(barcode: barcode)
                }
            }
        }
    }

    private var scaledMacros: MacroTotals {
        guard let product else { return MacroTotals() }
        return MacroTotals(
            calories: product.perServing.calories * servings,
            proteinG: product.perServing.proteinG * servings,
            carbsG: product.perServing.carbsG * servings,
            fatG: product.perServing.fatG * servings
        )
    }

    private func servingLabel(for product: BarcodeProductResult) -> String {
        let count = servings.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", servings)
            : String(format: "%.2f", servings)

        if let description = product.servingDescription, !description.isEmpty {
            return "\(count) × \(description)"
        }
        return "\(count) serving\(servings == 1 ? "" : "s")"
    }

    private func lookup(barcode: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let recognized = BarcodeNormalization.normalizedBarcode(barcode)
        do {
            product = try await OpenFoodFactsService.lookup(barcode: barcode)
        } catch is URLError {
            product = nil
            errorMessage = "Barcode \(recognized) was read. The food database didn't respond."
        } catch {
            product = nil
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let product else { return }
        let macros = scaledMacros
        let payload = MealPayload(
            name: product.name,
            calories: macros.calories,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            barcode: product.barcode,
            isLabelBacked: true,
            assumptions: product.servingDescription.map { ["Serving: \($0)"] } ?? [],
            quantity: servings,
            unit: "serving",
            brand: product.brand,
            source: .manufacturer,
            confidence: .high
        )
        let inserted = MealLogging.insertReturningMeals(payload, into: context)
        if let snapshot = LarryReactionSnapshot.capturing(loggedMeals: inserted, in: context) {
            appState.presentLarryReaction(snapshot)
        }
        onSaved?()
        dismiss()
    }
}
