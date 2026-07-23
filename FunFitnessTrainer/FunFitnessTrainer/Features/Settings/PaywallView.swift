import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var subs = SubscriptionService.shared
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandAccent)
                Text("Fun Fitness Pro")
                    .font(.title.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlimited food photo scans", systemImage: "checkmark.circle.fill")
                    Label("Morning ritual AI chat", systemImage: "checkmark.circle.fill")
                    Label("Cloud trainer voice sync", systemImage: "checkmark.circle.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                if subs.products.isEmpty {
                    Text("Products load from App Store Connect (fft_pro_monthly, fft_pro_yearly).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(subs.products, id: \.id) { product in
                        Button {
                            Task {
                                do {
                                    try await subs.purchase(product)
                                    appState.isPro = subs.isPro
                                    if subs.isPro { dismiss() }
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Text("\(product.displayName) — \(product.displayPrice)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandAccent)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                Text("Payment charged to Apple ID. Cancel anytime in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Go Pro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await subs.loadProducts() }
        }
    }
}
