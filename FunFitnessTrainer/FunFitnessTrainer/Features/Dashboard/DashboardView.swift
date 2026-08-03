import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.loggedAt, order: .reverse) private var allMeals: [Meal]
    @Query(sort: \ExerciseLog.loggedAt, order: .reverse) private var allExercises: [ExerciseLog]
    @Query private var goals: [DailyGoal]
    @Query private var settingsList: [UserSettings]
    @Query private var phrases: [TrainerPhrase]

    @State private var trainerQuip = LarryMcQuade.randomDashboardGreeting()
    @State private var loadingQuip = false
    @State private var showLarryChat = false
    @State private var showSettings = false
    @State private var showLogFood = false
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var showManual = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingBarcode = ""
    @State private var showConfirm = false
    @State private var showBarcodeConfirm = false
    @State private var showThePack = false
    @State private var showLogExercise = false
    @State private var pendingLogFoodAction: PendingLogFoodAction?
    @State private var isHomeMenuExpanded = false
    private var todayMeals: [Meal] {
        DaySummaryService.mealsToday(from: allMeals)
    }

    private var todayExercises: [ExerciseLog] {
        DaySummaryService.exercisesToday(from: allExercises)
    }

    private var todayLogItems: [DailyLogItem] {
        DaySummaryService.combinedLog(meals: todayMeals, exercises: todayExercises)
    }

    private var exerciseBurned: Double {
        DaySummaryService.exerciseCaloriesBurned(for: todayExercises)
    }

    private var consumed: MacroTotals {
        DaySummaryService.totals(for: todayMeals)
    }

    private var todayGoal: DailyGoal? {
        DaySummaryService.goal(for: Date(), goals: goals)
    }

    private var displayGoal: MacroGoalPayload? {
        guard let base = baseGoal else { return nil }
        return DaySummaryService.effectiveGoal(base: base, exerciseCalorieBonus: exerciseBurned)
    }

    private var baseGoal: MacroGoalPayload? {
        if let goal = todayGoal {
            return MacroGoalPayload(
                calories: goal.calories,
                proteinG: goal.proteinG,
                carbsG: goal.carbsG,
                fatG: goal.fatG
            )
        }
        if let settings = settingsList.first {
            return GoalCalculator.recommendedMacros(for: settings)
        }
        return nil
    }

    private var streakDays: Int {
        DaySummaryService.streakDays(meals: allMeals)
    }

    private var mealNumbers: [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        var index = 1
        for item in todayLogItems {
            if case .meal(let meal) = item {
                numbers[meal.id] = index
                index += 1
            }
        }
        return numbers
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                HomeDarkBackground()

                VStack(spacing: 0) {
                    homeTopBar

                    VStack(spacing: 12) {
                        larrySection
                        macroSection
                        logSectionHeader
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

                    logListContent
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .frame(maxHeight: todayLogItems.isEmpty ? nil : .infinity)

                    Spacer(minLength: todayLogItems.isEmpty ? 12 : 0)

                    // Reserve space so content doesn't sit under the dock.
                    Color.clear.frame(height: 108)
                }

                if isHomeMenuExpanded {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { collapseHomeMenu() }
                        .transition(.opacity)
                        .accessibilityLabel("Dismiss menu")
                        .accessibilityAddTraits(.isButton)
                }

                homeActionBar
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHomeMenuExpanded)
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .task { normalizeTodayMeals() }
            .refreshable { await refreshQuip() }
            .onAppear {
                applyRandomGreeting()
                if appState.openLarryChatOnNextAppear {
                    appState.openLarryChatOnNextAppear = false
                    showLarryChat = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                applyRandomGreeting()
            }
            .onChange(of: showLarryChat) { _, open in
                if open { collapseHomeMenu() }
            }
            .onChange(of: showCamera) { _, open in
                if open { collapseHomeMenu() }
            }
            .onChange(of: showLogFood) { _, open in
                if open { collapseHomeMenu() }
            }
            .onChange(of: showThePack) { _, open in
                if open { collapseHomeMenu() }
            }
            .sheet(isPresented: $showLarryChat) {
                CoachChatView()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if pendingImage != nil {
                    showConfirm = true
                }
            }) {
                CameraCaptureView { image in
                    pendingImage = image
                }
            }
            .fullScreenCover(isPresented: $showBarcodeScanner, onDismiss: {
                if !pendingBarcode.isEmpty {
                    showBarcodeConfirm = true
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
            .sheet(isPresented: $showBarcodeConfirm) {
                BarcodeMealConfirmView(barcode: pendingBarcode) {
                    pendingBarcode = ""
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
        }
    }

    // MARK: - Top bar

    private var homeTopBar: some View {
        ZStack {
            HomeDateHeader()

            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                        .frame(width: 36, height: 36)
                        .background(BrandTheme.homeCard.opacity(0.65), in: Circle())
                        .overlay(Circle().stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1))
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Larry + quip

    private var larrySection: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if streakDays > 0 {
                    StreakFlameIndicator(days: streakDays)
                }
                LarryAvatarView(portrait: .home, size: 58)
            }

            LarrySpeechBubble(text: trainerQuip, isLoading: loadingQuip, maxLines: nil)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Macros

    @ViewBuilder
    private var macroSection: some View {
        if let goal = displayGoal {
            MacroRingsView(consumed: consumed, goal: goal, exerciseCalorieBonus: exerciseBurned)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(macroAccessibilityLabel(goal: goal))
        } else {
            Text("Finish onboarding to set your macro targets.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Log list

    private var logSectionHeader: some View {
        HStack {
            Text("Today's log")
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showLogExercise = true
            } label: {
                Label("Exercise", systemImage: "figure.run")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(BrandTheme.neonBlue)
            if !todayLogItems.isEmpty {
                Text("\(todayLogItems.count) item\(todayLogItems.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
        }
    }

    private var logListContent: some View {
        Group {
            if todayLogItems.isEmpty {
                Text("Nothing logged yet today — snap food, tell Larry, or log a workout to earn extra calories.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(todayLogItems) { item in
                            switch item {
                            case .meal(let meal):
                                NavigationLink {
                                    MealEditView(meal: meal)
                                } label: {
                                    MealRowView(
                                        meal: meal,
                                        mealNumber: mealNumbers[meal.id],
                                        showsDisclosure: false
                                    )
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteMeal(meal)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            case .exercise(let exercise):
                                ExerciseRowView(exercise: exercise)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteExercise(exercise)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }

                            if item.id != todayLogItems.last?.id {
                                Divider()
                                    .overlay(BrandTheme.purple.opacity(0.25))
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [BrandTheme.purple.opacity(0.45), BrandTheme.teal.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxHeight: todayLogItems.isEmpty ? 96 : nil)
    }

    // MARK: - Bottom actions: Capture · Voice · Community (pop-out)

    private var homeActionBar: some View {
        homePopOutMenu
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .safeAreaPadding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background {
                HomeDockBackground()
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandTheme.purple.opacity(0.55), BrandTheme.teal.opacity(0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                    }
            }
    }

    /// Closed: solid origin dot. Open: Capture · Voice · Community fan out horizontally.
    private var homePopOutMenu: some View {
        ZStack {
            homeMenuAction(
                systemImage: "camera.fill",
                label: "Capture",
                tint: Color.brandAccent,
                accessibilityLabel: "Capture food",
                xOffset: isHomeMenuExpanded ? -110 : 0,
                appearDelay: 0.02
            ) {
                if appState.canScanFood && RuntimeEnvironment.isCameraAvailable {
                    showCamera = true
                } else {
                    showLogFood = true
                }
            }
            .contextMenu {
                Button {
                    showLogFood = true
                } label: {
                    Label("More options", systemImage: "ellipsis.circle")
                }
            }

            homeMenuAction(
                systemImage: "mic.fill",
                label: "Voice",
                tint: BrandTheme.purple,
                accessibilityLabel: "Voice — talk to Larry",
                xOffset: 0,
                appearDelay: 0
            ) {
                showLarryChat = true
            }

            homeMenuAction(
                systemImage: "person.3.fill",
                label: "Community",
                tint: BrandTheme.teal,
                accessibilityLabel: "Community — The Pack feed",
                xOffset: isHomeMenuExpanded ? 110 : 0,
                appearDelay: 0.04
            ) {
                showThePack = true
            }

            // Origin hub — solid black dot when closed (sketch label 1).
            Button {
                toggleHomeMenu()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.05, green: 0.03, blue: 0.09))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [BrandTheme.magenta.opacity(0.75), BrandTheme.purple.opacity(0.55)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                        .shadow(color: BrandTheme.magenta.opacity(0.4), radius: 12, y: 2)

                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 18, height: 18)
                }
                .frame(width: 64, height: 86, alignment: .top)
            }
            .buttonStyle(.plain)
            .opacity(isHomeMenuExpanded ? 0 : 1)
            .scaleEffect(isHomeMenuExpanded ? 0.35 : 1)
            .allowsHitTesting(!isHomeMenuExpanded)
            .accessibilityLabel("Open Capture, Voice, and Community")
            .accessibilityHint("Expands actions for Capture, Voice, and Community")
            .accessibilityHidden(isHomeMenuExpanded)
            .zIndex(2)
        }
        .frame(height: 86)
    }

    private func homeMenuAction(
        systemImage: String,
        label: String,
        tint: Color,
        accessibilityLabel: String,
        xOffset: CGFloat,
        appearDelay: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HomeActionButton(systemImage: systemImage, label: label, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .offset(x: xOffset)
        .opacity(isHomeMenuExpanded ? 1 : 0)
        .scaleEffect(isHomeMenuExpanded ? 1 : 0.2)
        .animation(
            .spring(response: 0.42, dampingFraction: 0.78).delay(isHomeMenuExpanded ? appearDelay : 0),
            value: isHomeMenuExpanded
        )
        .allowsHitTesting(isHomeMenuExpanded)
        .accessibilityHidden(!isHomeMenuExpanded)
        .zIndex(1)
    }

    private func toggleHomeMenu() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            isHomeMenuExpanded.toggle()
        }
    }

    private func collapseHomeMenu() {
        guard isHomeMenuExpanded else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isHomeMenuExpanded = false
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
                pendingBarcode = ""
                showBarcodeConfirm = true
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
        context.delete(meal)
        try? context.save()
    }

    private func deleteExercise(_ exercise: ExerciseLog) {
        context.delete(exercise)
        try? context.save()
    }

    private func normalizeTodayMeals() {
        var changed = false
        for meal in todayMeals {
            let cleaned = FoodItemNaming.canonicalName(for: meal.name)
            let nameChanged = cleaned != meal.name
            if nameChanged {
                meal.name = cleaned
                changed = true
            }

            guard meal.isEstimate else { continue }
            guard FoodAnalysisService.hasKnownNutrition(for: cleaned),
                  let entry = FoodAnalysisService.estimateForStoredName(cleaned) else { continue }

            let macrosChanged =
                Int(entry.calories) != Int(meal.calories)
                || Int(entry.proteinG) != Int(meal.proteinG)
                || Int(entry.carbsG) != Int(meal.carbsG)
                || Int(entry.fatG) != Int(meal.fatG)

            if nameChanged || macrosChanged {
                meal.calories = entry.calories
                meal.proteinG = entry.proteinG
                meal.carbsG = entry.carbsG
                meal.fatG = entry.fatG
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }

    private func macroAccessibilityLabel(goal: MacroGoalPayload) -> String {
        var label = "Calories \(Int(consumed.calories)) of \(Int(goal.calories)). Protein \(Int(consumed.proteinG)) of \(Int(goal.proteinG)) grams."
        if exerciseBurned > 0 {
            label += " Including \(Int(exerciseBurned)) bonus calories from exercise."
        }
        return label
    }

    private func applyRandomGreeting() {
        var next = DaySummaryService.pickRandomDashboardQuip(phrases: phrases)
        if next == trainerQuip {
            for _ in 0..<4 {
                let candidate = DaySummaryService.pickRandomDashboardQuip(phrases: phrases)
                if candidate != trainerQuip {
                    next = candidate
                    break
                }
            }
        }
        trainerQuip = next
    }

    private func refreshQuip() async {
        guard appState.isPro, displayGoal != nil else {
            applyRandomGreeting()
            return
        }

        let goal = displayGoal!
        let proteinRatio = consumed.proteinG / max(goal.proteinG, 1)
        let tag: PhraseTag = proteinRatio < 0.7 ? .underProtein : (consumed.calories >= goal.calories * 0.9 ? .crushedIt : .general)

        loadingQuip = true
        defer { loadingQuip = false }

        do {
            let rawVoice = settingsList.first?.trainerVoice ?? ""
            let voice = rawVoice.isEmpty ? LarryMcQuade.defaultVoice : rawVoice
            trainerQuip = try await TrainerService.reaction(
                tag: tag,
                phrases: phrases,
                trainerVoice: voice,
                goal: goal,
                consumed: consumed
            )
        } catch {
            applyRandomGreeting()
        }
    }
}

private enum PendingLogFoodAction {
    case camera
    case barcode
    case manual
    case confirmPhoto
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
                .fill(BrandTheme.homeCard)
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
    /// Points at Larry's mouth when the bubble sits beside his avatar.
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

struct HomeActionButton: View {
    let systemImage: String
    var label: String? = nil
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 64, height: 64)
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            if let label {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
        }
    }
}

struct ExerciseRowView: View {
    let exercise: ExerciseLog

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(BrandTheme.neonBlue.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "figure.run")
                        .foregroundStyle(BrandTheme.neonBlue)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(BrandTheme.homePrimaryText)
                if let minutes = exercise.durationMinutes {
                    Text("+\(Int(exercise.caloriesBurned)) cal burned · \(Int(minutes)) min")
                        .font(.caption)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                } else {
                    Text("+\(Int(exercise.caloriesBurned)) cal burned")
                        .font(.caption)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }
            Spacer()
            if exercise.isEstimate {
                Text("Est.")
                    .font(.caption2)
                    .padding(4)
                    .background(BrandTheme.neonBlue.opacity(0.2), in: Capsule())
            }
        }
    }
}

struct MealRowView: View {
    let meal: Meal
    var mealNumber: Int? = nil
    var showsDisclosure: Bool = true

    private var displayName: String {
        FoodItemNaming.displayTitle(for: meal.name)
    }

    var body: some View {
        HStack(spacing: 12) {
            mealLeadingBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(BrandTheme.homePrimaryText)
                Text("\(Int(meal.calories)) cal · P \(Int(meal.proteinG))g")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
            Spacer()
            if meal.isEstimate {
                Text("Est.")
                    .font(.caption2)
                    .padding(4)
                    .background(BrandTheme.magenta.opacity(0.2), in: Capsule())
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var mealLeadingBadge: some View {
        ZStack(alignment: .topLeading) {
            if let data = meal.photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BrandTheme.magenta.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: meal.barcode != nil ? "barcode" : "fork.knife")
                            .foregroundStyle(BrandTheme.magenta.opacity(0.8))
                    }
            }

            if let mealNumber {
                Text("\(mealNumber)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 4)
                    .background(BrandTheme.magenta, in: Capsule())
                    .offset(x: -6, y: -6)
                    .accessibilityLabel("Meal \(mealNumber)")
            }
        }
    }
}
