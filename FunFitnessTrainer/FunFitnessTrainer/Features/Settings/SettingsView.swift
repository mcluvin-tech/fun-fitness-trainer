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

    var body: some View {
        NavigationStack {
            List {
                Section("Larry McQuade") {
                    NavigationLink("Larry's voice") {
                        TrainerVoiceView()
                    }
                    NavigationLink("Phrase library") {
                        PhraseLibraryView()
                    }
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
                    if appState.isPro {
                        Label("Pro active", systemImage: "star.fill")
                    } else {
                        Button("Upgrade to Pro") { showPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { await SubscriptionService.shared.restore() }
                    }
                }
                Section("Legal") {
                    Text("Not medical advice. Macro estimates are approximate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Privacy policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Terms of service", destination: URL(string: "https://example.com/terms")!)
                }
                Section("Backend") {
                    Label(
                        AppConfig.hasBackend ? "Supabase connected" : "Demo mode (add Secrets.plist)",
                        systemImage: AppConfig.hasBackend ? "cloud.fill" : "cloud.slash"
                    )
                }
            }
            .navigationTitle("Settings")
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

struct PhraseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainerPhrase.createdAt, order: .reverse) private var phrases: [TrainerPhrase]
    @State private var newText = ""
    @State private var newTag: PhraseTag = .general

    var body: some View {
        List {
            Section("Add phrase") {
                TextField("Catchphrase", text: $newText)
                Picker("Tag", selection: $newTag) {
                    ForEach(PhraseTag.allCases) { Text($0.displayName).tag($0) }
                }
                Button("Add") { add() }
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Library") {
                ForEach(phrases) { phrase in
                    VStack(alignment: .leading) {
                        Text(phrase.text)
                        Text(phrase.tag.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Phrase library")
    }

    private func add() {
        context.insert(TrainerPhrase(text: newText.trimmingCharacters(in: .whitespaces), tag: newTag))
        try? context.save()
        newText = ""
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(phrases[i]) }
        try? context.save()
    }
}
