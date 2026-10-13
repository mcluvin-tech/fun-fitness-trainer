import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.loggedAt, order: .reverse) private var allMeals: [Meal]
    @Query(sort: \ExerciseLog.loggedAt, order: .reverse) private var allExercises: [ExerciseLog]
    @Query private var settingsList: [UserSettings]
    @Query private var phrases: [TrainerPhrase]

    @ObservedObject private var healthKit = HealthKitService.shared

    /// When embedded in MainTabView, logging / Larry are owned by the tab shell.
    var embeddedInTabs: Bool = false
    var onRequestLog: (() -> Void)? = nil
    var onOpenLarry: (() -> Void)? = nil

    @State private var trainerQuip = LarryMcQuade.randomDashboardGreeting()
    @State private var loadingQuip = false
    @State private var quoteVisible = false
    @State private var showLarryChat = false
    @State private var showMenu = false
    @State private var showLogFood = false
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var showManual = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingBarcode = ""
    @State private var showConfirm = false
    @State private var pendingBarcodeScan: PendingBarcodeScan?
    @State private var showThePack = false
    @State private var showLogExercise = false
    @State private var pendingLogFoodAction: PendingLogFoodAction?
    @State private var macroExplanation: MacroGoalExplanation?
    @State private var showDietPicker = false
    @State private var focusedMacroKind: MacroGoalKind?
    @State private var pulseKind: MacroGoalKind?
    @State private var celebrationChip: LogCelebrationChip?
    @State private var knownMealIDs: Set<UUID> = []
    @State private var previousConsumed = MacroTotals()
    @State private var estimateMeal: Meal?
    @State private var path = NavigationPath()

    private var todayMeals: [Meal] {
        DaySummaryService.mealsToday(from: allMeals)
    }

    private var todayExercises: [ExerciseLog] {
        DaySummaryService.exercisesToday(from: allExercises)
    }

    private var todayLogItems: [DailyLogItem] {
        DaySummaryService.combinedLog(meals: todayMeals, exercises: todayExercises)
            .sorted { $0.loggedAt > $1.loggedAt }
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

    private var consumed: MacroTotals {
        DaySummaryService.totals(for: todayMeals)
    }

    private var displayGoal: MacroGoalPayload? {
        DaySummaryService.foodTarget(from: settingsList.first)
    }

    private var streakDays: Int {
        DaySummaryService.streakDays(meals: allMeals)
    }

    private var remaining: MacroTotals? {
        guard let goal = displayGoal else { return nil }
        return DaySummaryService.remaining(consumed: consumed, goal: goal)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                HomeDarkBackground()

                VStack(spacing: 0) {
                    homeTopBar

                    ScrollView {
                        VStack(spacing: 18) {
                            dailyStatusStory
                            macroSection
                            logSection
                            larryCoachStrip
                                .padding(.bottom, embeddedInTabs ? 100 : 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        normalizeTodayMeals()
                        await healthKit.refreshToday()
                        await refreshContextualQuip(force: true)
                        HomeHaptics.soft()
                    }
                }

                if let chip = celebrationChip {
                    celebrationOverlay(chip)
                }
            }
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let meal = todayMeals.first(where: { $0.id == id }) {
                    MealEditView(meal: meal)
                }
            }
            .task {
                normalizeTodayMeals()
                await healthKit.bootstrapIfConnected()
                knownMealIDs = Set(todayMeals.map(\.id))
                previousConsumed = consumed
                await refreshContextualQuip(force: true)
            }
            .onAppear {
                normalizeTodayMeals()
                TrackingCycleService.ensureStarted()
                if appState.openLarryChatOnNextAppear {
                    appState.openLarryChatOnNextAppear = false
                    openLarry()
                }
            }
            .onChange(of: todayMeals.map(\.id)) { _, newIDs in
                normalizeTodayMeals()
                handleMealLogChange(newIDs: Set(newIDs))
            }
            .onChange(of: focusedMacroKind) { _, kind in
                if kind == .protein, let goal = displayGoal, consumed.proteinG >= goal.proteinG {
                    applyContextualLarry()
                    springLarry()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await refreshContextualQuip(force: true)
                    await healthKit.refreshToday()
                }
            }
            .fullScreenCover(isPresented: $showLarryChat) {
                CoachChatView()
            }
            .fullScreenCover(item: Binding(
                get: { embeddedInTabs ? nil : appState.larryReaction },
                set: { if !embeddedInTabs { appState.larryReaction = $0 } }
            )) { snapshot in
                LarryReactsView(
                    snapshot: snapshot,
                    onDone: { appState.larryReaction = nil },
                    onTalkToLarry: {
                        appState.larryReaction = nil
                        openLarry()
                    }
                )
            }
            .sheet(isPresented: $showMenu) {
                MenuView()
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if !pendingBarcode.isEmpty {
                    pendingBarcodeScan = PendingBarcodeScan(pendingBarcode)
                    pendingBarcode = ""
                } else if pendingImage != nil {
                    showConfirm = true
                }
            }) {
                CameraCaptureView(
                    onBarcode: { pendingBarcode = $0 }
                ) { image in
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
            .sheet(isPresented: $showLogFood, onDismiss: handleLogFoodSheetDismiss) {
                LogFoodSheet(
                    pickedItem: $pickedItem,
                    onCamera: { pendingLogFoodAction = .camera },
                    onBarcode: { pendingLogFoodAction = .barcode },
                    onManual: { pendingLogFoodAction = .manual }
                )
            }
            .sheet(isPresented: $showThePack) {
                ThePackView()
            }
            .sheet(isPresented: $showLogExercise) {
                LogExerciseSheet()
            }
            .sheet(item: $macroExplanation) { explanation in
                if explanation.kind == .calories, let settings = settingsList.first {
                    CalorieGoalSheet(
                        settings: settings,
                        exerciseCalorieBonus: exerciseBurned
                    )
                } else {
                    MacroGoalExplanationSheet(explanation: explanation)
                }
            }
            .sheet(isPresented: $showDietPicker) {
                DietStyleEditor(wrapsInNavigationStack: true)
            }
            .sheet(isPresented: Binding(
                get: { estimateMeal != nil },
                set: { if !$0 { estimateMeal = nil } }
            )) {
                if let meal = estimateMeal {
                    MealEstimateReviewSheet(meal: meal)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeRequestLogFood)) { _ in
                showLogFood = true
            }
        }
    }

    // MARK: - Top bar

    private var homeTopBar: some View {
        ZStack {
            HomeDateHeader()

            HStack {
                if streakDays > 0 {
                    StreakFlameIndicator(days: streakDays)
                }
                Spacer()
                if !embeddedInTabs {
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(BrandTheme.homeCardBorder, lineWidth: 1))
                    }
                    .accessibilityLabel("Menu")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Daily status story

    @ViewBuilder
    private var dailyStatusStory: some View {
        if let goal = displayGoal, let rem = remaining {
            let eaten = MacroTrackingEngine.displayCalories(consumed.calories)
            let remainingCal = MacroTrackingEngine.displayCalories(max(rem.calories, 0))
            let over = rem.calories < 0
            let pace = DaySummaryService.dailyPaceLine(
                consumed: consumed,
                goal: goal,
                logIsEmpty: todayLogItems.isEmpty
            )

            VStack(alignment: .leading, spacing: 8) {
                Button(action: openCalorieExplanation) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(eaten)")
                            .font(BrandTheme.typeHero)
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: eaten)
                        Text("cal eaten")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                        Spacer(minLength: 8)
                        Text(over
                              ? "\(MacroTrackingEngine.displayCalories(-rem.calories)) over"
                              : "\(remainingCal.formatted()) remaining")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(over ? BrandTheme.magenta : BrandTheme.homeSecondaryText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(eaten) calories eaten, \(over ? "\(MacroTrackingEngine.displayCalories(-rem.calories)) over" : "\(remainingCal) remaining"). \(pace)")
                .accessibilityHint("Shows why this calorie goal is set, and lets you lower it slightly")

                HStack(spacing: 8) {
                    if let settings = settingsList.first {
                        Button {
                            showDietPicker = true
                        } label: {
                            Label(
                                settings.hasChosenDiet ? settings.dietStyle.displayName : "Choose a diet",
                                systemImage: settings.dietStyle.symbolName
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrandTheme.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BrandTheme.teal.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(settings.hasChosenDiet ? "Diet: \(settings.dietStyle.displayName)" : "Choose a diet")
                    }

                    Button(action: openCalorieExplanation) {
                        Text("Why \(Int(goal.calories.rounded())) cal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTheme.magenta)
                    }
                    .buttonStyle(.plain)
                }

                Text(pace)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BrandTheme.teal.opacity(0.95))
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Macros

    private func openCalorieExplanation() {
        guard let settings = settingsList.first else { return }
        macroExplanation = GoalCalculator.explanation(
            for: .calories,
            settings: settings,
            exerciseCalorieBonus: exerciseBurned,
            displayedGoal: displayGoal
        )
    }

    @ViewBuilder
    private var macroSection: some View {
        if let goal = displayGoal {
            MacroRingsView(
                consumed: consumed,
                goal: goal,
                onExplainGoal: { kind in
                    guard let settings = settingsList.first else { return }
                    macroExplanation = GoalCalculator.explanation(
                        for: kind,
                        settings: settings,
                        exerciseCalorieBonus: exerciseBurned,
                        displayedGoal: goal
                    )
                },
                interactiveFocus: true,
                onFocusChange: { focusedMacroKind = $0 },
                pulseKind: pulseKind
            )
        } else {
            Text("Finish onboarding to set your macro targets.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Today's log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today’s log")
                    .font(BrandTheme.typeSection)
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showLogExercise = true
                } label: {
                    Label("Exercise", systemImage: "figure.run")
                        .font(BrandTheme.typeMeta.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(BrandTheme.neonBlue)
            }

            if todayLogItems.isEmpty {
                Text("Nothing logged yet. Snap food, talk to Larry, or log a workout.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 12)
                    .elevatedSurface(cornerRadius: 16)
            } else {
                VStack(spacing: 14) {
                    ForEach(todayLogItems) { item in
                        switch item {
                        case .meal(let meal):
                            mealCard(meal)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        case .exercise(let exercise):
                            exerciseCard(exercise)
                        }
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: todayLogItems.map(\.id))
            }
        }
    }

    private func mealCard(_ meal: Meal) -> some View {
        MealRowView(meal: meal, showsDisclosure: false) {
            estimateMeal = meal
        }
        .padding(14)
        .elevatedSurface(cornerRadius: 16, glow: BrandTheme.magenta.opacity(0.35))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            path.append(meal.id)
        }
        .contextMenu {
            Button {
                path.append(meal.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                duplicateMeal(meal)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                deleteMeal(meal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActionsCompat(
            onLeading: { duplicateMeal(meal) },
            onTrailing: { deleteMeal(meal) }
        )
        .onLongPressGesture(minimumDuration: 0.45) {
            HomeHaptics.light()
            path.append(meal.id)
        }
    }

    private func exerciseCard(_ exercise: ExerciseLog) -> some View {
        ExerciseRowView(exercise: exercise)
            .padding(14)
            .elevatedSurface(cornerRadius: 16, glow: BrandTheme.neonBlue.opacity(0.4))
            .contextMenu {
                Button(role: .destructive) {
                    deleteExercise(exercise)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActionsCompat(
                onLeading: nil,
                onTrailing: { deleteExercise(exercise) }
            )
    }

    // MARK: - Larry coach strip

    private var larryCoachStrip: some View {
        Button {
            openLarry()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Larry")
                        .font(BrandTheme.typeMeta.weight(.bold))
                        .foregroundStyle(BrandTheme.teal)
                    if loadingQuip {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(BrandTheme.teal)
                    } else {
                        Text(trainerQuip)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .minimumScaleFactor(0.9)
                            .opacity(quoteVisible ? 1 : 0)
                            .offset(y: quoteVisible ? 0 : 4)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(BrandTheme.homeCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BrandTheme.homeCardBorder, lineWidth: 1)
                        )
                        .shadow(color: BrandTheme.purple.opacity(0.25), radius: 14, y: 6)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandTheme.homeTertiaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loadingQuip ? "Larry is thinking" : "Larry says: \(trainerQuip). Open chat.")
    }

    // MARK: - Celebration

    private func celebrationOverlay(_ chip: LogCelebrationChip) -> some View {
        GeometryReader { geo in
            Text(chip.text)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(chip.color.opacity(0.92), in: Capsule())
                .shadow(color: chip.color.opacity(0.5), radius: 10, y: 4)
                .position(
                    x: geo.size.width * chip.xFraction,
                    y: geo.size.height * chip.yProgress
                )
                .opacity(chip.yProgress < 0.22 ? 0 : 1)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Logging reactions

    private func handleMealLogChange(newIDs: Set<UUID>) {
        let added = newIDs.subtracting(knownMealIDs)
        knownMealIDs = newIDs
        guard !added.isEmpty else {
            previousConsumed = consumed
            return
        }

        let delta = MacroTotals(
            calories: consumed.calories - previousConsumed.calories,
            proteinG: consumed.proteinG - previousConsumed.proteinG,
            carbsG: consumed.carbsG - previousConsumed.carbsG,
            fatG: consumed.fatG - previousConsumed.fatG
        )
        previousConsumed = consumed

        if appState.suppressNextLogCelebration {
            appState.suppressNextLogCelebration = false
            applyContextualLarry()
            springLarry()
            return
        }

        HomeHaptics.success()
        playLogCelebration(delta: delta)
        applyContextualLarry()
        springLarry()
    }

    private func playLogCelebration(delta: MacroTotals) {
        let candidates: [(MacroGoalKind, Double, String, Color, CGFloat)] = [
            (.protein, delta.proteinG, "+\(MacroTrackingEngine.displayGrams(delta.proteinG))g protein", BrandTheme.neonBlue, 0.62),
            (.calories, delta.calories, "+\(MacroTrackingEngine.displayCalories(delta.calories)) cal", BrandTheme.magenta, 0.38),
            (.carbs, delta.carbsG, "+\(MacroTrackingEngine.displayGrams(delta.carbsG))g carbs", BrandTheme.teal, 0.38),
            (.fat, delta.fatG, "+\(MacroTrackingEngine.displayGrams(delta.fatG))g fat", BrandTheme.purple, 0.62),
        ]
        guard let best = candidates.max(by: { abs($0.1) < abs($1.1) }), best.1 > 0.4 else { return }

        pulseKind = best.0
        celebrationChip = LogCelebrationChip(
            text: best.2,
            color: best.3,
            xFraction: best.4,
            yProgress: 0.72
        )

        withAnimation(.easeOut(duration: 0.7)) {
            celebrationChip = LogCelebrationChip(
                text: best.2,
                color: best.3,
                xFraction: best.4,
                yProgress: 0.18
            )
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                celebrationChip = nil
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            pulseKind = nil
        }
    }

    // MARK: - Larry helpers

    private func openLarry() {
        if let onOpenLarry {
            onOpenLarry()
        } else {
            showLarryChat = true
        }
    }

    private func springLarry() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
            quoteVisible = true
        }
    }

    private func applyContextualLarry() {
        guard let goal = displayGoal else {
            trainerQuip = DaySummaryService.pickRandomDashboardQuip(phrases: phrases)
            quoteVisible = true
            return
        }
        let result = DaySummaryService.contextualLarryLine(
            consumed: consumed,
            goal: goal,
            latestMealName: todayMeals.last.map { FoodItemNaming.displayTitle(for: $0.name) },
            streakDays: streakDays,
            focusedKind: focusedMacroKind,
            phrases: phrases
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            trainerQuip = LarrySpeechStyle.clean(result.text)
            quoteVisible = true
        }
    }

    private func refreshContextualQuip(force: Bool) async {
        if force || !quoteVisible {
            applyContextualLarry()
        }
        guard appState.isPro, let goal = displayGoal else { return }

        let proteinRatio = consumed.proteinG / max(goal.proteinG, 1)
        let tag: PhraseTag = proteinRatio < 0.7
            ? .underProtein
            : (consumed.calories >= goal.calories * 0.9 ? .crushedIt : .general)

        loadingQuip = true
        defer { loadingQuip = false }

        do {
            let rawVoice = settingsList.first?.trainerVoice ?? ""
            let voice = rawVoice.isEmpty ? LarryMcQuade.defaultVoice : rawVoice
            let line = try await TrainerService.reaction(
                tag: tag,
                phrases: phrases,
                trainerVoice: voice,
                goal: goal,
                consumed: consumed
            )
            withAnimation(.easeOut(duration: 0.35)) {
                trainerQuip = LarrySpeechStyle.clean(line)
                quoteVisible = true
            }
        } catch {
            applyContextualLarry()
        }
    }

    // MARK: - Data

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

    private func deleteMeal(_ meal: Meal) {
        HomeHaptics.light()
        context.delete(meal)
        try? context.save()
    }

    private func duplicateMeal(_ meal: Meal) {
        HomeHaptics.soft()
        let copy = Meal(
            name: meal.name,
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            loggedAt: Date(),
            photoData: meal.photoData,
            items: meal.items,
            assumptions: meal.assumptions,
            confidence: meal.confidence,
            isEstimate: meal.isEstimate,
            barcode: meal.barcode,
            quantity: meal.quantity ?? 1,
            unit: meal.unit ?? "serving",
            preparationState: meal.preparationState,
            brand: meal.brand,
            nutritionSource: meal.nutritionSource ?? "generic_estimate",
            nutritionConfidence: meal.nutritionConfidence ?? "medium"
        )
        context.insert(copy)
        try? context.save()
    }

    private func deleteExercise(_ exercise: ExerciseLog) {
        HomeHaptics.light()
        context.delete(exercise)
        try? context.save()
    }

    private func normalizeTodayMeals() {
        var changed = false
        for meal in todayMeals {
            let cleaned = FoodItemNaming.canonicalName(for: meal.name)
            if cleaned != meal.name {
                meal.name = cleaned
                changed = true
            }

            let repaired = FoodAnalysisService.displayMacros(
                name: cleaned,
                calories: meal.calories,
                proteinG: meal.proteinG,
                carbsG: meal.carbsG,
                fatG: meal.fatG
            )
            let looksLikeQuantityBug =
                (cleaned.lowercased().contains("milk") && meal.calories >= 400)
                || (StapleNutritionDatabase.looksLikePlainIce(cleaned) && meal.calories >= 20)
            if looksLikeQuantityBug, abs(repaired.calories - meal.calories) > 1 {
                meal.calories = repaired.calories
                meal.proteinG = repaired.proteinG
                meal.carbsG = repaired.carbsG
                meal.fatG = repaired.fatG
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }
}

private enum PendingLogFoodAction {
    case camera
    case barcode
    case manual
    case confirmPhoto
}

private struct LogCelebrationChip {
    let text: String
    let color: Color
    let xFraction: CGFloat
    var yProgress: CGFloat
}

extension Notification.Name {
    static let homeRequestLogFood = Notification.Name("homeRequestLogFood")
}

// MARK: - Swipe helper (cards outside List)

private struct SwipeActionsCompat: ViewModifier {
    var onLeading: (() -> Void)?
    var onTrailing: (() -> Void)?
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        let dx = value.translation.width
                        if dx > 0, onLeading != nil {
                            offset = min(dx, 72)
                        } else if dx < 0, onTrailing != nil {
                            offset = max(dx, -72)
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        if dx > 56, let onLeading {
                            onLeading()
                        } else if dx < -56, let onTrailing {
                            onTrailing()
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            offset = 0
                        }
                    }
            )
    }
}

private extension View {
    func swipeActionsCompat(onLeading: (() -> Void)?, onTrailing: (() -> Void)?) -> some View {
        modifier(SwipeActionsCompat(onLeading: onLeading, onTrailing: onTrailing))
    }
}

// MARK: - Components

struct LarrySpeechBubble: View {
    let text: String
    var isLoading: Bool = false
    /// `nil` = show full quote without truncation (home + onboarding).
    var maxLines: Int? = nil

    private let tailWidth: CGFloat = 12
    private let bubbleGradient = LinearGradient(
        colors: [BrandTheme.purple.opacity(0.55), BrandTheme.magenta.opacity(0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if let maxLines {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(maxLines)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
            } else {
                Text(text)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .padding(.trailing, 14)
        .padding(.leading, 14 + tailWidth / 2)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(BrandTheme.homePrimaryText)
        .background {
            LarrySpeechBubbleShape(tailWidth: tailWidth, tailCenterY: 22)
                .fill(BrandTheme.homeCardSolid)
        }
        .overlay {
            LarrySpeechBubbleShape(tailWidth: tailWidth, tailCenterY: 22)
                .stroke(bubbleGradient, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Larry says: \(text)")
    }
}

private struct LarrySpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 14
    var tailWidth: CGFloat = 12
    var tailHeight: CGFloat = 14
    var tailCenterY: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let bubbleRect = CGRect(
            x: rect.minX + tailWidth,
            y: rect.minY,
            width: rect.width - tailWidth,
            height: rect.height
        )

        var path = Path(roundedRect: bubbleRect, cornerRadius: cornerRadius)

        let attachX = bubbleRect.minX
        let centerY = min(max(rect.minY + tailCenterY, bubbleRect.minY + cornerRadius), bubbleRect.maxY - cornerRadius)
        let halfTail = tailHeight / 2

        path.move(to: CGPoint(x: attachX, y: centerY - halfTail))
        path.addLine(to: CGPoint(x: rect.minX, y: centerY))
        path.addLine(to: CGPoint(x: attachX, y: centerY + halfTail))
        path.closeSubpath()

        return path
    }
}

struct ExerciseRowView: View {
    let exercise: ExerciseLog

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandTheme.neonBlue.opacity(0.18))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BrandTheme.neonBlue)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(FoodItemNaming.stripDashes(exercise.name))
                    .font(BrandTheme.typeItem)
                    .foregroundStyle(BrandTheme.homePrimaryText)
                if let minutes = exercise.durationMinutes {
                    Text("+\(Int(exercise.caloriesBurned)) cal burned · \(Int(minutes)) min")
                        .font(BrandTheme.typeMeta)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                } else {
                    Text("+\(Int(exercise.caloriesBurned)) cal burned")
                        .font(BrandTheme.typeMeta)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }
            Spacer()
            if exercise.isEstimate {
                Text("Est.")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BrandTheme.neonBlue.opacity(0.2), in: Capsule())
                    .foregroundStyle(BrandTheme.neonBlue)
            }
        }
    }
}

struct MealRowView: View {
    let meal: Meal
    var showsDisclosure: Bool = true
    var onReviewEstimate: (() -> Void)? = nil

    private var displayName: String {
        FoodItemNaming.displayTitle(for: meal.name)
    }

    private var displayMacros: MacroTotals {
        meal.storedMacros
    }

    private var mealSlot: String {
        let hour = Calendar.current.component(.hour, from: meal.loggedAt)
        switch hour {
        case 5..<11: return "Breakfast"
        case 11..<15: return "Lunch"
        case 15..<17: return "Snack"
        case 17..<22: return "Dinner"
        default: return "Late night"
        }
    }

    private var needsReview: Bool {
        meal.confidenceKind == .low || meal.confidenceKind == .medium || meal.isEstimate
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            mealThumb

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(BrandTheme.typeItem)
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .multilineTextAlignment(.leading)

                Text("\(displayMacros.displayedCalories) cal · \(displayMacros.displayedProteinG)g protein")
                    .font(BrandTheme.typeMeta.weight(.medium))
                    .foregroundStyle(BrandTheme.homeSecondaryText)

                HStack(spacing: 8) {
                    Text(mealSlot)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandTheme.homeTertiaryText)

                    if needsReview {
                        Button {
                            onReviewEstimate?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                Text("Estimate, review")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(BrandTheme.magenta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BrandTheme.magenta.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Review AI estimate")
                    }
                }
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandTheme.homeTertiaryText)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var mealThumb: some View {
        if let data = meal.photoData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandTheme.magenta.opacity(0.14))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: meal.barcode != nil ? "barcode" : "fork.knife")
                        .foregroundStyle(BrandTheme.magenta.opacity(0.85))
                }
        }
    }
}

// MARK: - AI estimate review

struct MealEstimateReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var meal: Meal
    @State private var portionMultiplier: Double = 1

    private var assumptionText: String {
        let raw: String
        if !meal.assumptions.isEmpty {
            raw = meal.assumptions.joined(separator: " ")
        } else if !meal.items.isEmpty {
            raw = "We estimated \(meal.items.joined(separator: ", ")). Correct?"
        } else {
            raw = "We estimated \(FoodItemNaming.displayTitle(for: meal.name)). Correct?"
        }
        return FoodItemNaming.stripDashes(raw)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(BrandTheme.magenta)
                            Text("Estimate, review")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BrandTheme.homePrimaryText)
                        }

                        Text(assumptionText)
                            .font(.body)
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Portion")
                                .font(BrandTheme.typeMeta.weight(.semibold))
                                .foregroundStyle(BrandTheme.homeSecondaryText)
                            HStack {
                                Button {
                                    portionMultiplier = max(0.25, portionMultiplier - 0.25)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(BrandTheme.teal)
                                }
                                Text(String(format: "%.2g×", portionMultiplier))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(BrandTheme.homePrimaryText)
                                    .frame(maxWidth: .infinity)
                                Button {
                                    portionMultiplier = min(4, portionMultiplier + 0.25)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(BrandTheme.teal)
                                }
                            }

                            let scaled = MacroTrackingEngine.scale(meal.storedMacros, by: portionMultiplier)
                            Text("\(scaled.displayedCalories) cal · P \(scaled.displayedProteinG)g · C \(scaled.displayedCarbsG)g · F \(scaled.displayedFatG)g")
                                .font(BrandTheme.typeMeta.weight(.medium))
                                .foregroundStyle(BrandTheme.homeSecondaryText)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(16)
                        .elevatedSurface(cornerRadius: 16)

                        Button {
                            applyPortion()
                            dismiss()
                        } label: {
                            Text("Looks right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandTheme.teal)

                        Button {
                            dismiss()
                        } label: {
                            Text("Edit details")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrandTheme.magenta)
                    }
                    .padding(20)
                }
            }
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func applyPortion() {
        let scaled = MacroTrackingEngine.scale(meal.storedMacros, by: portionMultiplier)
        meal.calories = scaled.calories
        meal.proteinG = scaled.proteinG
        meal.carbsG = scaled.carbsG
        meal.fatG = scaled.fatG
        if let q = meal.quantity {
            meal.quantity = q * portionMultiplier
        }
        meal.nutritionConfidence = MacroTrackingEngine.NutritionConfidence.high.rawValue
        meal.isEstimate = false
        try? context.save()
        HomeHaptics.success()
    }
}
