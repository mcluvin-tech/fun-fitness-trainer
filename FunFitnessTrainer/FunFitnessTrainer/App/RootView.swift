import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var settingsList: [UserSettings]

    private var needsOnboarding: Bool {
        !appState.hasCompletedOnboarding || settingsList.isEmpty
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
            } else {
                DashboardView()
            }
        }
        .task {
            await SubscriptionService.shared.loadProducts()
            appState.isPro = SubscriptionService.shared.isPro
        }
        .onChange(of: SubscriptionService.shared.isPro) { _, pro in
            appState.isPro = pro
        }
        .onChange(of: settingsList.count) { _, count in
            if count == 0, appState.hasCompletedOnboarding {
                appState.hasCompletedOnboarding = false
            }
        }
        .onAppear {
            if settingsList.isEmpty, appState.hasCompletedOnboarding {
                appState.hasCompletedOnboarding = false
            }
        }
    }
}
