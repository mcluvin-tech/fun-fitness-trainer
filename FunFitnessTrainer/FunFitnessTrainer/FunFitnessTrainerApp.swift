import SwiftUI
import SwiftData

@main
struct FunFitnessTrainerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .modelContainer(PersistenceController.shared.container)
                .onOpenURL { url in
                    Task {
                        try? await SupabaseService.shared.handleOAuthCallback(url: url)
                    }
                }
        }
    }
}

final class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    /// Set after onboarding so the home screen opens Larry voice chat once.
    @Published var openLarryChatOnNextAppear = false
    @Published var isPro: Bool = false
    @Published var scansToday: Int = 0

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        resetScansIfNewDay()
    }

    func resetScansIfNewDay() {
        let key = "scansDate"
        let today = Calendar.current.startOfDay(for: Date())
        if let saved = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(saved, inSameDayAs: today) {
            scansToday = UserDefaults.standard.integer(forKey: "scansToday")
        } else {
            scansToday = 0
            UserDefaults.standard.set(today, forKey: key)
            UserDefaults.standard.set(0, forKey: "scansToday")
        }
    }

    func recordScan() {
        scansToday += 1
        UserDefaults.standard.set(scansToday, forKey: "scansToday")
    }

    var canScanFood: Bool {
        isPro || scansToday < AppConfig.freeScansPerDay
    }
}
