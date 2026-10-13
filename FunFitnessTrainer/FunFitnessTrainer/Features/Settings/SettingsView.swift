import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var appleSignIn = SignInWithAppleHelper()
    @StateObject private var googleSignIn = OAuthSignInHelper()
    @StateObject private var phoneSignIn = PhoneSignInHelper()
    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @ObservedObject private var healthKit = HealthKitService.shared
    @State private var stepNotifications = HealthActivityPreferences.stepNotificationsEnabled
    @State private var mealReminders = HealthActivityPreferences.mealLogRemindersEnabled
    @State private var isConnectingHealth = false

    var body: some View {
            List {
                Section {
                    NavigationLink {
                        DietStyleEditor()
                    } label: {
                        HStack {
                            Text("Eating style")
                            Spacer()
                            Text(dietStatusLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Diet")
                } footer: {
                    Text(dietFooter)
                }
                Section {
                    NavigationLink("Larry's voice") {
                        TrainerVoiceView()
                    }
                    Toggle("Remind me to log meals", isOn: $mealReminders)
                        .onChange(of: mealReminders) { _, value in
                            HealthActivityPreferences.mealLogRemindersEnabled = value
                            Task { await NotificationService.shared.refreshMealReminders() }
                        }
                } header: {
                    Text("Larry McQuade")
                } footer: {
                    Text("Breakfast, lunch, and dinner. He stays quiet if that meal is already logged.")
                }
                Section {
                    if healthKit.isAvailable {
                        if healthKit.isConnected {
                            Label("Connected to Apple Health", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Toggle("Notify at \(HealthActivityPreferences.stepGoal.formatted()) steps", isOn: $stepNotifications)
                                .onChange(of: stepNotifications) { _, value in
                                    HealthActivityPreferences.stepNotificationsEnabled = value
                                    if value {
                                        Task { await NotificationService.shared.requestAuthorization() }
                                    }
                                }
                            Button("Refresh from Health") {
                                Task { await healthKit.refreshToday() }
                            }
                            .disabled(healthKit.isRefreshing)
                            Button("Disconnect Apple Health", role: .destructive) {
                                healthKit.disconnect()
                            }
                        } else {
                            Button {
                                Task {
                                    isConnectingHealth = true
                                    _ = await healthKit.connect()
                                    isConnectingHealth = false
                                    stepNotifications = HealthActivityPreferences.stepNotificationsEnabled
                                }
                            } label: {
                                HStack {
                                    Label("Connect Apple Watch / Health", systemImage: "applewatch")
                                    if isConnectingHealth {
                                        Spacer()
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isConnectingHealth)
                        }
                        if let err = healthKit.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    } else {
                        Text("Apple Health isn't available on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health & Watch")
                } footer: {
                    Text("Larry reads steps and active calories from Apple Health (Watch, iPhone, and other synced fitness devices). Activity is shown in the menu. It does not increase your daily food target — that already includes your activity level. You'll get a Larry notification when you hit \(HealthActivityPreferences.stepGoal.formatted()) steps.")
                }
                Section("Account") {
                    if supabase.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Sign out", role: .destructive) {
                            supabase.clearSession()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if AppConfig.supportsSignInWithApple {
                                AppleSignInButton(helper: appleSignIn, height: 50)
                            }

                            Button {
                                googleSignIn.signInWithGoogle()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "envelope.fill")
                                    Text("Continue with Gmail")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!AppConfig.hasBackend || googleSignIn.isLoading || appleSignIn.isLoading)

                            Button {
                                phoneSignIn.present()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "phone.fill")
                                    Text("Continue with Phone Number")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!AppConfig.hasBackend || phoneSignIn.isLoading || appleSignIn.isLoading)

                            if googleSignIn.isLoading || phoneSignIn.isLoading || appleSignIn.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }

                            if !AppConfig.hasBackend {
                                Text("Add Supabase keys to enable Apple, Gmail, and phone sign-in.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let err = appleSignIn.errorMessage ?? googleSignIn.errorMessage ?? phoneSignIn.errorMessage {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    Button("Delete account", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
                Section("Pro") {
                    if appState.isFounders {
                        Label("Founders · unlimited photos", systemImage: "infinity")
                    } else if appState.isPro {
                        Label("Pro active", systemImage: "star.fill")
                    } else {
                        Button("Upgrade to Pro") { showPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { await SubscriptionService.shared.restore() }
                    }
                }
                Section("Legal") {
                    Text("Not medical advice. Macro estimates are approximate. Coach language may include strong language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Host docs/privacy-policy.md and docs/terms.md, then replace these URLs before App Store submit.
                    Link("Privacy policy", destination: URL(string: "https://github.com/mcluvin-tech/fun-fitness-trainer/blob/main/docs/privacy-policy.md")!)
                    Link("Terms of service", destination: URL(string: "https://github.com/mcluvin-tech/fun-fitness-trainer/blob/main/docs/terms.md")!)
                }
                Section("Backend") {
                    Label(
                        AppConfig.hasBackend ? "Supabase connected" : "Demo mode (add Secrets.plist)",
                        systemImage: AppConfig.hasBackend ? "cloud.fill" : "cloud.slash"
                    )
                }
            }
            .navigationTitle("Settings")
            .preferredColorScheme(.dark)
            .task {
                await healthKit.bootstrapIfConnected()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $phoneSignIn.showSheet) {
                PhoneSignInSheet(helper: phoneSignIn)
            }
            .confirmationDialog("Delete account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await supabase.deleteAccount()
                    }
                }
            } message: {
                Text("This removes your sign-in session. Cloud data deletion may require support contact.")
            }
            .onChange(of: supabase.isSignedIn) { _, signedIn in
                if signedIn { Task { await syncVoiceFromCloud() } }
            }
    }

    private var dietStatusLabel: String {
        guard let settings = settingsList.first else { return "Balanced" }
        return settings.hasChosenDiet ? settings.dietStyle.displayName : "Not chosen"
    }

    private var dietFooter: String {
        guard let settings = settingsList.first else {
            return "Choose paleo, keto, carnivore, or balanced. Tap calories on Today to see the math and pull the goal a little lower."
        }
        if settings.hasChosenDiet {
            return "\(settings.dietStyle.summary) Tap calories on Today to see why the target is set, and to pull it a little lower."
        }
        return "Choose paleo, keto, carnivore, or balanced. Tap calories on Today to see the math and pull the goal a little lower."
    }

    private func syncVoiceFromCloud() async {
        guard let settings = settingsList.first else { return }
        if let voice = try? await supabase.fetchTrainerVoice(), !voice.isEmpty {
            settings.trainerVoice = voice
            try? context.save()
        }
    }
}

struct TrainerVoiceView: View {
    @Query private var settingsList: [UserSettings]
    @Environment(\.modelContext) private var context
    @State private var voice = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $voice)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            if saved {
                Text("Saved").font(.caption).foregroundStyle(.green)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Larry's voice")
        .onAppear {
            let stored = settingsList.first?.trainerVoice ?? ""
            voice = stored.isEmpty ? LarryMcQuade.defaultVoice : stored
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let s = settingsList.first {
                        s.trainerVoice = voice
                    }
                    try? context.save()
                    saved = true
                    Task {
                        try? await SupabaseService.shared.syncTrainerVoice(voice)
                    }
                }
            }
        }
    }
}

struct DietStyleOptionCard: View {
    let style: DietStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: style.symbolName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? BrandTheme.magenta : BrandTheme.teal)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(style.displayName)
                        .font(.headline)
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Text(style.summary)
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                        .multilineTextAlignment(.leading)
                    Text(style.macroHint)
                        .font(.caption)
                        .foregroundStyle(BrandTheme.teal)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? BrandTheme.magenta : BrandTheme.homeSecondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? BrandTheme.magenta.opacity(0.7) : BrandTheme.purple.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DietStyleEditor: View {
    var wrapsInNavigationStack: Bool = false

    @Query private var settingsList: [UserSettings]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { editor }
            } else {
                editor
            }
        }
    }

    private var editor: some View {
        ZStack {
            HomeDarkBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("This sets how your calories split across protein, carbs, and fat. The calorie number itself still comes from your weight, activity, and pace.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.homeSecondaryText)

                    ForEach(DietStyle.allCases) { style in
                        DietStyleOptionCard(
                            style: style,
                            isSelected: settingsList.first?.dietStyle == style && settingsList.first?.hasChosenDiet == true
                        ) {
                            select(style)
                        }
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Your diet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if wrapsInNavigationStack {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func select(_ style: DietStyle) {
        guard let settings = settingsList.first else { return }
        settings.dietStyle = style
        try? context.save()
        if wrapsInNavigationStack {
            dismiss()
        }
    }
}
