import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @Query private var settingsList: [UserSettings]
    @Query private var meals: [Meal]

    private var needsOnboarding: Bool {
        !appState.hasCompletedOnboarding || settingsList.isEmpty
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .task {
            await SubscriptionService.shared.refreshEntitlements()
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
        .task(id: appState.hasCompletedOnboarding) {
            await refreshMealRemindersIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshMealRemindersIfReady() }
        }
        .onChange(of: meals.map(\.id)) { _, _ in
            Task { await refreshMealRemindersIfReady() }
        }
    }

    private func refreshMealRemindersIfReady() async {
        guard appState.hasCompletedOnboarding, !settingsList.isEmpty else { return }
        await NotificationService.shared.refreshMealReminders()
    }
}

// MARK: - Floating tab shell

enum HomeTab: Hashable {
    case today
    case log
    case larry
    case progress
    case settings
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: HomeTab = .today
    @State private var showLogFood = false
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var showManual = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingBarcode = ""
    @State private var showConfirm = false
    @State private var pendingBarcodeScan: PendingBarcodeScan?
    @State private var pendingLogFoodAction: MainTabLogAction?

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                DashboardView(
                    embeddedInTabs: true,
                    onRequestLog: { showLogFood = true },
                    onOpenLarry: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            tab = .larry
                        }
                    }
                )
                .opacity(tab == .today ? 1 : 0)
                .allowsHitTesting(tab == .today)
                .accessibilityHidden(tab != .today)

                CoachChatView(showsCloseButton: false, isActive: tab == .larry) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        tab = .today
                    }
                }
                .opacity(tab == .larry ? 1 : 0)
                .allowsHitTesting(tab == .larry)
                .accessibilityHidden(tab != .larry)

                if tab == .log {
                    FoodLogView()
                }
                if tab == .progress {
                    MenuView(showsDismissButton: false, title: "Progress")
                }
                if tab == .settings {
                    NavigationStack {
                        SettingsView()
                            .safeAreaInset(edge: .bottom) {
                                Color.clear.frame(height: 88)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tab)

            if appState.larryReaction == nil {
                FloatingHomeTabBar(selection: $tab)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: appState.larryReaction != nil)
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.dark)
        .onAppear {
            if appState.openLarryChatOnNextAppear {
                appState.openLarryChatOnNextAppear = false
                tab = .larry
            }
            appState.presentIncomingChallengeIfNeeded()
        }
        .onChange(of: appState.openLarryChatOnNextAppear) { _, open in
            if open {
                appState.openLarryChatOnNextAppear = false
                tab = .larry
            }
        }
        .onChange(of: appState.focusTodayTab) { _, focus in
            if focus {
                appState.focusTodayTab = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    tab = .today
                }
            }
        }
        .sheet(isPresented: $appState.showChallengeAccept, onDismiss: {
            appState.noteChallengeSheetDismissed()
        }) {
            ChallengeAcceptView()
        }
        .sheet(isPresented: $showLogFood, onDismiss: handleLogFoodSheetDismiss) {
            LogFoodSheet(
                pickedItem: $pickedItem,
                onCamera: { pendingLogFoodAction = .camera },
                onBarcode: { pendingLogFoodAction = .barcode },
                onManual: { pendingLogFoodAction = .manual }
            )
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if !pendingBarcode.isEmpty {
                pendingBarcodeScan = PendingBarcodeScan(pendingBarcode)
                pendingBarcode = ""
            } else if pendingImage != nil {
                showConfirm = true
            }
        }) {
            CameraCaptureView(onBarcode: { pendingBarcode = $0 }) { image in
                pendingImage = image
            }
        }
        .fullScreenCover(isPresented: $showBarcodeScanner, onDismiss: {
            if !pendingBarcode.isEmpty {
                pendingBarcodeScan = PendingBarcodeScan(pendingBarcode)
                pendingBarcode = ""
            }
        }) {
            BarcodeScannerView { code in
                pendingBarcode = code
            }
        }
        .onChange(of: pickedItem) { _, item in
            Task {
                guard item != nil else { return }
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        pendingImage = image
                        pickedItem = nil
                        if showLogFood {
                            pendingLogFoodAction = .confirmPhoto
                        } else {
                            showConfirm = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showConfirm) {
            if let img = pendingImage {
                MealConfirmView(image: img) {
                    pendingImage = nil
                    appState.recordScan()
                }
            }
        }
        .sheet(item: $pendingBarcodeScan) { scan in
            BarcodeMealConfirmView(barcode: scan.code) {
                pendingBarcodeScan = nil
                appState.recordScan()
            }
        }
        .sheet(isPresented: $showManual) {
            ManualMealEntryView()
        }
        .fullScreenCover(item: $appState.larryReaction) { snapshot in
            LarryReactsView(
                snapshot: snapshot,
                onDone: {
                    appState.larryReaction = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        tab = .today
                    }
                },
                onTalkToLarry: {
                    appState.larryReaction = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        tab = .larry
                    }
                }
            )
        }
    }

    private func handleLogFoodSheetDismiss() {
        guard let action = pendingLogFoodAction else { return }
        pendingLogFoodAction = nil
        switch action {
        case .camera:
            showCamera = true
        case .barcode:
            if RuntimeEnvironment.isCameraAvailable {
                showBarcodeScanner = true
            } else {
                pendingBarcodeScan = PendingBarcodeScan()
            }
        case .manual:
            showManual = true
        case .confirmPhoto:
            if pendingImage != nil {
                showConfirm = true
            }
        }
    }
}

private enum MainTabLogAction {
    case camera, barcode, manual, confirmPhoto
}

struct FloatingHomeTabBar: View {
    @Binding var selection: HomeTab

    private let larryButtonSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.today, label: "Today", systemImage: "circle.grid.cross")
            tabButton(.log, label: "Log", systemImage: "list.bullet.rectangle")
            Color.clear
                .frame(width: larryButtonSize, height: larryButtonSize)
            tabButton(.progress, label: "Progress", systemImage: "chart.line.uptrend.xyaxis")
            tabButton(.settings, label: "Settings", systemImage: "gearshape")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(BrandTheme.homeActionBar)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .shadow(color: BrandTheme.purple.opacity(0.12), radius: 12, y: 3)
        }
        .overlay {
            larryTalkButton
        }
    }

    private var larryTalkButton: some View {
        let selected = selection == .larry
        return Button {
            HomeHaptics.soft()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selection = .larry
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: selected
                                ? [BrandTheme.purple, BrandTheme.magenta.opacity(0.88)]
                                : [BrandTheme.purple.opacity(0.92), BrandTheme.purple.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: larryButtonSize, height: larryButtonSize)
                    .shadow(
                        color: BrandTheme.purple.opacity(selected ? 0.42 : 0.22),
                        radius: selected ? 10 : 6,
                        y: 3
                    )

                LarryAvatarView(portrait: .home, size: larryButtonSize - 6)
                    .overlay(
                        Circle()
                            .stroke(
                                selected ? BrandTheme.teal.opacity(0.95) : Color.white.opacity(0.35),
                                lineWidth: selected ? 2 : 1.25
                            )
                    )
            }
            .frame(width: larryButtonSize, height: larryButtonSize)
            .scaleEffect(selected ? 1.03 : 0.98)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk to Larry")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tabButton(_ tab: HomeTab, label: String, systemImage: String) -> some View {
        let selected = selection == tab
        return Button {
            HomeHaptics.soft()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(selected ? .semibold : .regular))
                    .symbolVariant(selected ? .fill : .none)
                Text(label)
                    .font(.caption2.weight(selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? BrandTheme.homePrimaryText : BrandTheme.homeTertiaryText.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
