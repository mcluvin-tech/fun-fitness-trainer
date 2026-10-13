import SwiftUI
import SwiftData
import PhotosUI

struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ExerciseLog.loggedAt, order: .reverse) private var allExercises: [ExerciseLog]

    @ObservedObject private var healthKit = HealthKitService.shared
    @ObservedObject private var progressPhotos = ProgressPhotoStore.shared
    @State private var cycle: TrackingCycleService.Snapshot?
    @State private var isConnectingHealth = false
    @State private var showLogExercise = false
    @State private var showThePack = false
    @State private var showChallengeFriend = false
    @State private var cardChallenge: FriendChallenge?

    var showsDismissButton: Bool = true
    var title: String = "Menu"

    private var todayExercises: [ExerciseLog] {
        DaySummaryService.exercisesToday(from: allExercises)
    }

    private var manualExerciseBurned: Double {
        DaySummaryService.exerciseCaloriesBurned(for: todayExercises)
    }

    private var exerciseBurned: Double {
        DaySummaryService.activityCalorieBonus(
            manualExerciseCalories: manualExerciseBurned,
            healthKitActiveEnergy: healthKit.calorieBonusFromHealth,
            useHealthKit: healthKit.isConnected
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()

                List {
                    Section {
                        cycleCard
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if title == "Progress" {
                        Section {
                            challengeCard
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section {
                        stepsAndExerciseCard
                    } header: {
                        Text("Steps & exercise")
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Section {
                        NavigationLink {
                            ProgressPhotosView()
                        } label: {
                            progressRow
                        }
                    } header: {
                        Text("Progress")
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(menuRowBackground)
                    .listRowSeparator(.hidden)

                    Section {
                        Button {
                            showThePack = true
                        } label: {
                            Label("The Pack", systemImage: "person.3.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BrandTheme.homePrimaryText)
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BrandTheme.homePrimaryText)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(menuRowBackground)
                    .listRowSeparator(.hidden)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .task {
                TrackingCycleService.ensureStarted()
                cycle = TrackingCycleService.snapshot()
                await healthKit.bootstrapIfConnected()
                await refreshChallengeCard()
            }
            .sheet(isPresented: $showLogExercise) {
                LogExerciseSheet()
            }
            .sheet(isPresented: $showThePack) {
                ThePackView()
            }
            .sheet(isPresented: $showChallengeFriend, onDismiss: {
                Task { await refreshChallengeCard() }
            }) {
                ChallengeFriendView()
            }
            .onChange(of: appState.showChallengeAccept) { _, showing in
                if !showing {
                    Task { await refreshChallengeCard() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !showsDismissButton {
                    Color.clear.frame(height: 88)
                }
            }
        }
    }

    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🥊  CHALLENGE A FRIEND")
                .font(.caption.weight(.bold))
                .foregroundStyle(BrandTheme.teal)
            Text("Think your buddy can outwork you?")
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("“\(challengeLarryLine)”")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if appState.pendingChallengeToken != nil {
                Text("You've been called out.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                Button("View challenge") {
                    appState.reopenIncomingChallenge()
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandTheme.teal)
            }

            if let cardChallenge {
                Text(challengeStatusLine(cardChallenge))
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }

            Button {
                showChallengeFriend = true
            } label: {
                Text(cardChallenge?.status == .pending && cardChallenge?.isInviter == true
                     ? "Share again"
                     : "Challenge Someone")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(BrandTheme.teal)
        }
        .padding(16)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
        )
    }

    private var challengeLarryLine: String {
        let rival = cardChallenge?.opponentDisplayName ?? cardChallenge?.inviterDisplayName
        if cardChallenge?.status == .accepted {
            return LarryChallengeQuotes.line(
                moment: .accepted,
                rivalName: rival,
                seed: cardChallenge?.id.hashValue ?? 0
            )
        }
        if appState.pendingChallengeToken != nil {
            return LarryChallengeQuotes.line(moment: .calledOut, rivalName: rival)
        }
        return LarryChallengeQuotes.line(moment: .invite, rivalName: rival)
    }

    private func challengeStatusLine(_ challenge: FriendChallenge) -> String {
        if challenge.status == .pending {
            return FriendChallengeRules.waitingLine(opponentName: challenge.opponentDisplayName)
        }
        return FriendChallengeRules.connectedLine(opponentName: challenge.opponentDisplayName)
    }

    private func refreshChallengeCard() async {
        guard title == "Progress" else { return }
        guard SupabaseService.shared.isSignedIn, AppConfig.hasBackend else {
            cardChallenge = nil
            return
        }
        let mine = (try? await ChallengeService.shared.fetchMyChallenges()) ?? []
        cardChallenge = FriendChallengeRules.preferredCardChallenge(mine)
    }

    private var menuRowBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(BrandTheme.homeCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
            )
    }

    private var cycleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.circle.fill")
                    .font(.title2)
                    .foregroundStyle(BrandTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking cycle")
                        .font(.headline)
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    if let cycle {
                        Text("Cycle \(cycle.cycleNumber)")
                            .font(.caption)
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                }
                Spacer()
            }

            if let cycle {
                Text("Week \(cycle.weekInCycle) of \(TrackingCycleService.weeksPerCycle)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BrandTheme.homePrimaryText)

                Text("Day \(cycle.dayInCycle) of \(cycle.cycleLengthDays)")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BrandTheme.homeSecondaryText.opacity(0.2))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [BrandTheme.teal, BrandTheme.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * cycle.progress))
                    }
                }
                .frame(height: 8)

                HStack(spacing: 6) {
                    ForEach(1...TrackingCycleService.weeksPerCycle, id: \.self) { week in
                        Text("W\(week)")
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                week == cycle.weekInCycle
                                    ? BrandTheme.teal.opacity(0.28)
                                    : BrandTheme.homeActionBar,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        week == cycle.weekInCycle
                                            ? BrandTheme.teal.opacity(0.8)
                                            : BrandTheme.purple.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(
                                week == cycle.weekInCycle
                                    ? BrandTheme.homePrimaryText
                                    : BrandTheme.homeSecondaryText
                            )
                    }
                }

                Text(cycleCaption(for: cycle))
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(BrandTheme.teal.opacity(0.35), lineWidth: 1)
        )
    }

    private var stepsAndExerciseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if healthKit.isConnected {
                StepProgressBar(
                    steps: healthKit.stepsToday,
                    goal: HealthActivityPreferences.stepGoal
                )

                HStack {
                    Label("Exercise", systemImage: "figure.run")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Spacer()
                    Text("+\(Int(exerciseBurned)) cal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrandTheme.neonBlue)
                }

                if healthKit.activeEnergyToday > 0 {
                    Text("Apple Health: \(Int(healthKit.activeEnergyToday)) active cal today")
                        .font(.caption)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
                if !todayExercises.isEmpty {
                    Text("\(todayExercises.count) workout\(todayExercises.count == 1 ? "" : "s") logged")
                        .font(.caption)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }

                Button {
                    showLogExercise = true
                } label: {
                    Label("Log exercise", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(BrandTheme.neonBlue)
            } else if healthKit.isAvailable {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect Apple Watch / Health to see steps and active calories here.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.homeSecondaryText)

                    Button {
                        Task {
                            isConnectingHealth = true
                            _ = await healthKit.connect()
                            isConnectingHealth = false
                        }
                    } label: {
                        HStack {
                            Label("Connect Apple Health", systemImage: "applewatch")
                            if isConnectingHealth {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.teal)
                    .disabled(isConnectingHealth)

                    if let err = healthKit.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        showLogExercise = true
                    } label: {
                        Label("Log exercise anyway", systemImage: "figure.run")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BrandTheme.neonBlue)

                    if exerciseBurned > 0 {
                        Text("Logged workouts: +\(Int(exerciseBurned)) cal today")
                            .font(.caption)
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                }
            } else {
                Text("Apple Health isn't available on this device. You can still log workouts.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                Button {
                    showLogExercise = true
                } label: {
                    Label("Log exercise", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(BrandTheme.neonBlue)
            }
        }
        .padding(16)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(BrandTheme.neonBlue.opacity(0.35), lineWidth: 1)
        )
    }

    private var progressRow: some View {
        HStack(spacing: 12) {
            progressThumbnails
            VStack(alignment: .leading, spacing: 4) {
                Text("Progress photos")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                Text(progressSubtitle)
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var progressThumbnails: some View {
        HStack(spacing: -10) {
            progressThumb(progressPhotos.baseline)
            if progressPhotos.latest?.id != progressPhotos.baseline?.id {
                progressThumb(progressPhotos.latest)
            }
        }
    }

    private func progressThumb(_ record: ProgressPhotoRecord?) -> some View {
        Group {
            if let record, let image = progressPhotos.image(for: record) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "figure.arms.open")
                    .font(.body)
                    .foregroundStyle(BrandTheme.teal)
            }
        }
        .frame(width: 40, height: 40)
        .background(BrandTheme.homeActionBar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BrandTheme.purple.opacity(0.4), lineWidth: 1)
        )
    }

    private var progressSubtitle: String {
        if !progressPhotos.hasBaseline {
            return "Optional day-one photo — skip anytime"
        }
        if !progressPhotos.hasPhotoThisWeek() {
            return "No photo this week yet"
        }
        return "\(progressPhotos.photos.count) photo\(progressPhotos.photos.count == 1 ? "" : "s") saved on this phone"
    }

    private func cycleCaption(for cycle: TrackingCycleService.Snapshot) -> String {
        switch cycle.weekInCycle {
        case 1:
            return "Week 1: stick to the plan. Larry's calibrating how your body actually responds."
        case 2:
            return "Week 2: stay consistent. This is where the numbers start telling the truth."
        default:
            return "Week 3: last stretch of this cycle. After this, Larry can lock in your true pace."
        }
    }
}

struct ProgressPhotosView: View {
    @ObservedObject private var store = ProgressPhotoStore.shared
    @State private var showCamera = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var selected: ProgressPhotoRecord?

    var body: some View {
        ZStack {
            HomeDarkBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Optional. Day one lives on this phone so you can see the work — skip it if you want.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.homeSecondaryText)

                    if let baseline = store.baseline, let latest = store.latest {
                        comparison(baseline: baseline, latest: latest)
                    } else {
                        emptyState
                    }

                    addButtons

                    if !store.photos.isEmpty {
                        Text("All photos")
                            .font(.headline)
                            .foregroundStyle(BrandTheme.homePrimaryText)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                            ForEach(store.photos) { photo in
                                Button {
                                    selected = photo
                                } label: {
                                    photoCell(photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Progress photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(purpose: .progress) { image in
                _ = store.add(image: image, isBaseline: !store.hasBaseline)
            }
        }
        .onChange(of: pickedItem) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        _ = store.add(image: image, isBaseline: !store.hasBaseline)
                        pickedItem = nil
                    }
                }
            }
        }
        .sheet(item: $selected) { photo in
            ProgressPhotoDetailView(photo: photo)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.arms.open")
                .font(.system(size: 40))
                .foregroundStyle(BrandTheme.teal)
            Text("No day-one photo yet")
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("A torso / abs shot in similar lighting each week is enough. You don't have to.")
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
        )
    }

    private func comparison(baseline: ProgressPhotoRecord, latest: ProgressPhotoRecord) -> some View {
        HStack(spacing: 10) {
            comparisonCard(title: "Day 1", photo: baseline)
            comparisonCard(
                title: baseline.id == latest.id ? "Latest" : "Now",
                photo: latest
            )
        }
    }

    private func comparisonCard(title: String, photo: ProgressPhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrandTheme.homeSecondaryText)
            if let image = store.image(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(photo.capturedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(BrandTheme.homeSecondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var addButtons: some View {
        VStack(spacing: 10) {
            Button {
                showCamera = true
            } label: {
                Label(
                    store.hasBaseline ? "Take this week's photo" : "Take day-one photo",
                    systemImage: "camera.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandTheme.magenta)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(BrandTheme.teal)
        }
    }

    private func photoCell(_ photo: ProgressPhotoRecord) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = store.image(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            if photo.isBaseline {
                Text("Day 1")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(BrandTheme.teal, in: Capsule())
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(BrandTheme.purple.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct ProgressPhotoDetailView: View {
    let photo: ProgressPhotoRecord
    @ObservedObject private var store = ProgressPhotoStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()
                if let image = store.image(for: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle(photo.isBaseline ? "Day 1" : photo.capturedAt.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        store.delete(photo)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
