import SwiftUI
import SwiftData

@main
struct FunFitnessTrainerApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .modelContainer(PersistenceController.shared.container)
                .onOpenURL { url in
                    if let token = ChallengeLink.token(from: url) {
                        appState.registerChallengeLink(token)
                        return
                    }
                    Task {
                        try? await SupabaseService.shared.handleOAuthCallback(url: url)
                    }
                }
                .task {
                    if appState.hasCompletedOnboarding {
                        TrackingCycleService.ensureStarted()
                    }
                    await HealthKitService.shared.bootstrapIfConnected()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await HealthKitService.shared.refreshToday() }
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
    /// Fullscreen "Larry Reacts" sequence after a food log.
    @Published var larryReaction: LarryReactionSnapshot?
    /// Skip the Today-screen chip when Larry Reacts is about to play.
    @Published var suppressNextLogCelebration = false
    /// Invite token kept through signup. Cleared after accept, or when the link is dead.
    @Published var pendingChallengeToken: String? = nil {
        didSet { persistPendingChallengeToken() }
    }
    @Published var showChallengeAccept = false
    /// Main tabs switch to Today after a challenge is accepted.
    @Published var focusTodayTab = false
    /// Bumped when the center Larry button should open the mic, even mid-reply.
    @Published var larryListenNonce = 0
    /// Shown on the center button so listening, logging, and speaking look different.
    @Published var voicePhase: VoiceTurnPhase = .idle

    func presentLarryReaction(_ snapshot: LarryReactionSnapshot, afterSheetDismiss: Bool = true) {
        suppressNextLogCelebration = true
        guard afterSheetDismiss else {
            larryReaction = snapshot
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            larryReaction = snapshot
        }
    }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        pendingChallengeToken = UserDefaults.standard.string(forKey: Self.pendingChallengeTokenKey)
        resetScansIfNewDay()
    }

    @MainActor
    func registerChallengeLink(_ token: String) {
        let clean = ChallengeLink.normalizeToken(token)
        guard ChallengeLink.isValidToken(clean) else { return }
        pendingChallengeToken = clean
        UserDefaults.standard.removeObject(forKey: Self.dismissedChallengeTokenKey)
        ProductAnalytics.track(.challengeLinkOpened, metadata: [
            "authenticated": SupabaseService.shared.isSignedIn ? "true" : "false",
        ])
        if hasCompletedOnboarding {
            showChallengeAccept = true
        }
    }

    func presentIncomingChallengeIfNeeded() {
        guard hasCompletedOnboarding, hasActionableIncomingChallenge else { return }
        showChallengeAccept = true
    }

    var hasActionableIncomingChallenge: Bool {
        guard let pendingChallengeToken, ChallengeLink.isValidToken(pendingChallengeToken) else { return false }
        return UserDefaults.standard.string(forKey: Self.dismissedChallengeTokenKey) != pendingChallengeToken
    }

    func reopenIncomingChallenge() {
        UserDefaults.standard.removeObject(forKey: Self.dismissedChallengeTokenKey)
        showChallengeAccept = true
    }

    func postponeIncomingChallenge() {
        if let pendingChallengeToken {
            UserDefaults.standard.set(pendingChallengeToken, forKey: Self.dismissedChallengeTokenKey)
        }
        showChallengeAccept = false
    }

    /// Swipe-down on the accept sheet. Keeps the token so Progress can reopen it.
    func noteChallengeSheetDismissed() {
        guard let pendingChallengeToken else { return }
        if UserDefaults.standard.string(forKey: Self.dismissedChallengeTokenKey) == pendingChallengeToken {
            return
        }
        UserDefaults.standard.set(pendingChallengeToken, forKey: Self.dismissedChallengeTokenKey)
    }

    /// Drops the saved link without closing the accept sheet.
    func dropIncomingToken() {
        pendingChallengeToken = nil
        UserDefaults.standard.removeObject(forKey: Self.dismissedChallengeTokenKey)
    }

    func clearIncomingChallenge() {
        dropIncomingToken()
        showChallengeAccept = false
    }

    func completeChallengeHandoff() {
        clearIncomingChallenge()
        focusTodayTab = true
    }

    private static let pendingChallengeTokenKey = "pendingChallengeToken"
    private static let dismissedChallengeTokenKey = "dismissedChallengeToken"

    private func persistPendingChallengeToken() {
        if let pendingChallengeToken {
            UserDefaults.standard.set(pendingChallengeToken, forKey: Self.pendingChallengeTokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingChallengeTokenKey)
        }
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

    var isFounders: Bool { AppConfig.isFoundersEdition }

    var canScanFood: Bool {
        isFounders || isPro || scansToday < AppConfig.freeScansPerDay
    }

    var scanAllowanceLabel: String {
        if isFounders { return "Founders · unlimited photos" }
        if isPro { return "Scans today: \(scansToday)/∞" }
        return "Scans today: \(scansToday)/\(AppConfig.freeScansPerDay)"
    }
}
