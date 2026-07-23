import SwiftUI

struct MacroRingsView: View {
    let consumed: MacroTotals
    let goal: MacroGoalPayload
    var exerciseCalorieBonus: Double = 0

    private let ringDiameter: CGFloat = 108
    private let ringLineWidth: CGFloat = 13
    private let pairSpacing: CGFloat = 34

    private var effectiveCalorieTarget: Double {
        goal.calories
    }

    var body: some View {
        VStack(spacing: 8) {
            if exerciseCalorieBonus > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.caption.weight(.semibold))
                    Text("+\(Int(exerciseCalorieBonus)) cal earned from exercise")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(BrandTheme.neonBlue)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                HStack(spacing: pairSpacing) {
                    ring(title: "Cal", value: consumed.calories, max: effectiveCalorieTarget, color: BrandTheme.magenta)
                    ring(title: "Protein", value: consumed.proteinG, max: goal.proteinG, color: BrandTheme.neonBlue)
                }
                HStack(spacing: pairSpacing) {
                    ring(title: "Carbs", value: consumed.carbsG, max: goal.carbsG, color: BrandTheme.teal)
                    ring(title: "Fat", value: consumed.fatG, max: goal.fatG, color: BrandTheme.purple)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
    }

    private func ring(title: String, value: Double, max: Double, color: Color) -> some View {
        let progress = max > 0 ? min(value / max, 1.2) : 0
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: ringLineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(value))")
                        .font(.title3.weight(.semibold))
                    Text("/ \(Int(max))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: ringDiameter, height: ringDiameter)
            Text(title)
                .font(.caption2)
        }
        .frame(width: ringDiameter)
        .accessibilityLabel("\(title): \(Int(value)) of \(Int(max))")
    }
}
