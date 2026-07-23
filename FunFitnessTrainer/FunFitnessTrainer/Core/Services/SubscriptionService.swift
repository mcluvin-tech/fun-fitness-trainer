import Foundation
import StoreKit

/// RevenueCat-ready subscription layer using StoreKit 2 for v1.
/// Set REVENUECAT_API_KEY in Secrets.plist when wiring RevenueCat SDK.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published var isPro = false
    @Published var products: [Product] = []

    private let productIds = ["fft_pro_monthly", "fft_pro_yearly"]

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
        } catch {
            products = []
        }
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified = verification {
                isPro = true
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIds.contains(transaction.productID) {
                isPro = true
                return
            }
        }
        isPro = false
    }
}
