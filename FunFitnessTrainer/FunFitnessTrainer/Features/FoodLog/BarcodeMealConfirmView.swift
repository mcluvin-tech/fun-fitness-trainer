import SwiftUI
import SwiftData

struct BarcodeMealConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let barcode: String
    var onSaved: (() -> Void)?

    @State private var manualBarcode = ""
    @State private var product: BarcodeProductResult?
    @State private var servings: Double = 1
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if product == nil {
                    Section("Barcode") {
                        TextField("Enter barcode", text: $manualBarcode)
                            .keyboardType(.numberPad)
                        Button("Look up product") {
                            Task { await lookup(barcode: manualBarcode) }
                        }
                        .disabled(manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
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
                        LabeledContent("Calories", value: "\(Int(scaledMacros.calories))")
                        LabeledContent("Protein", value: "\(Int(scaledMacros.proteinG)) g")
                        LabeledContent("Carbs", value: "\(Int(scaledMacros.carbsG)) g")
                        LabeledContent("Fat", value: "\(Int(scaledMacros.fatG)) g")
                    }

                    Section {
                        Text(product.nutritionIsComplete
                             ? "Data from Open Food Facts. Confirm the serving, then save."
                             : "Open Food Facts has this product but no label calories. Saving logs zeros — edit them after if you know the label.")
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

        do {
            product = try await OpenFoodFactsService.lookup(barcode: barcode)
        } catch {
            product = nil
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let product else { return }
        let macros = scaledMacros

        let meal = Meal(
            name: product.name,
            calories: macros.calories,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            isEstimate: false,
            barcode: product.barcode
        )
        context.insert(meal)
        do {
            try context.save()
        } catch {
            context.delete(meal)
            errorMessage = "Couldn't save this meal. Try again."
            return
        }
        MealLogging.shareToPack(meal: meal)
        onSaved?()
        dismiss()
    }
}
