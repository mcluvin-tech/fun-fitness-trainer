import SwiftUI
import SwiftData
import PhotosUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var step = 0
    @State private var usesImperial = true
    @State private var currentWeightKg = 74.8
    @State private var goalWeightKg = 70.3
    @State private var weeklyLbChange = -1.0
    @State private var weeklyManuallySet = false

    @State private var sex: Sex = .male
    @State private var age = 30
    @State private var heightCm = 175.0
    @State private var heightFt = 5
    @State private var heightIn = 9
    @State private var activity: ActivityLevel = .moderate
    @State private var diet: DietStyle = .balanced
    @State private var saveError: String?
    @State private var showProgressCamera = false
    @State private var progressPickerItem: PhotosPickerItem?
    @State private var progressPreview: UIImage?
    @State private var didLoadExistingProfile = false

    private let totalSteps = 6

    private var draftSettings: UserSettings {
        UserSettings(
            sex: sex,
            age: age,
            heightCm: heightCmValue,
            weightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            weeklyLbChangeTarget: weeklyLbChange,
            usesImperialUnits: usesImperial,
            activity: activity,
            goalType: inferredGoalType,
            dietStyle: diet,
            trainerVoice: LarryMcQuade.defaultVoice
        )
    }

    private var plan: FitnessPlan {
        GoalCalculator.buildPlan(for: draftSettings)
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Welcome"
        case 1: return "Your diet"
        case 2: return "Your weights"
        case 3: return "About You"
        case 4: return "Your plan"
        case 5: return "Day one photo"
        default: return "Your plan"
        }
    }

    /// Centered title, quiet back button, no divider. Used by the tighter onboarding steps.
    private var usesCompactOnboardingChrome: Bool {
        step == 3 || step == 5
    }

    private var primaryButtonTitle: String {
        if step < totalSteps - 1 { return "Continue" }
        return progressPreview == nil ? "Skip for now" : "Start training"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: step == 0 ? 0 : 24) {
                    stepContent
                }
                .padding(.horizontal, step == 0 ? 24 : (usesCompactOnboardingChrome ? 20 : 16))
                .padding(.top, step == 0 ? 4 : (usesCompactOnboardingChrome ? 8 : 16))
                .padding(.bottom, step == 0 ? 12 : 16)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { HomeDarkBackground() }
            .preferredColorScheme(.dark)
            .navigationTitle(step == 0 ? "" : stepTitle)
            .navigationBarTitleDisplayMode(step == 0 || usesCompactOnboardingChrome ? .inline : .large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(step == 0 ? .hidden : .visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if step > 0 {
                    onboardingBottomBar
                }
            }
            .onChange(of: currentWeightKg) { _, _ in syncWeeklyIfNeeded() }
            .onChange(of: goalWeightKg) { _, _ in syncWeeklyIfNeeded() }
            .onChange(of: progressPickerItem) { _, item in
                Task {
                    guard let item else { return }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            progressPreview = image
                            progressPickerItem = nil
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showProgressCamera) {
                CameraCaptureView(purpose: .progress) { image in
                    progressPreview = image
                }
            }
            .onAppear {
                loadExistingProfileIfNeeded()
                syncWeeklyIfNeeded()
                if usesImperial { updateHeightCm() }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: dietStep
        case 2: weightsStep
        case 3: bodyStep
        case 4: planStep
        case 5: progressPhotoStep
        default: EmptyView()
        }
    }

    // MARK: - Steps

    private var welcomeQuote: String {
        "If you wanna look as sexy as me, you're gonna have to lock in!"
    }

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            welcomeHeader

            LarryHeroImage(
                portrait: .welcome,
                maxHeight: dynamicTypeSize.isAccessibilitySize ? 168 : 240,
                aspectRatio: 16.0 / 10.0,
                cornerRadius: 22,
                showsNeonBorder: false
            )
            .padding(.top, 8)

            VStack(spacing: 2) {
                Text(LarryMcQuade.name)
                    .font(OnboardingType.font(32, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text("Macro Tracker")
                    .font(OnboardingType.font(26, weight: .bold, relativeTo: .title1))
                    .foregroundStyle(BrandTheme.homePrimaryText.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text("Your 80s macro coach for realistic weight goals, daily calories, and macros.")
                .font(OnboardingType.font(17, weight: .regular, relativeTo: .body))
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.top, 12)

            Text("Not medical advice.")
                .font(OnboardingType.font(13, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 8)

            Text("\u{201C}\(welcomeQuote)\u{201D}")
                .font(OnboardingType.font(16, weight: .medium, relativeTo: .callout).italic())
                .foregroundStyle(BrandTheme.teal)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
                .padding(.top, 12)

            Button(action: advance) {
                Text("Get Started")
                    .font(OnboardingType.font(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.brandAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(OnboardingPressStyle())
            .padding(.top, 20)
            .accessibilityHint("Continues to diet and goal setup")

            AuthSignInSection()
                .padding(.top, 12)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var welcomeHeader: some View {
        ZStack {
            Text("Welcome")
                .font(OnboardingType.font(20, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(BrandTheme.homePrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 64)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer(minLength: 0)
                Button(action: finish) {
                    Text("Skip")
                        .font(OnboardingType.font(17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Skips the rest of setup")
            }
        }
        .frame(minHeight: 44)
    }

    private var onboardingBottomBar: some View {
        VStack(spacing: 12) {
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                advance()
            } label: {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandAccent)

            if step > 0 {
                Button("Back") { step -= 1 }
                    .font(usesCompactOnboardingChrome ? OnboardingType.font(15, weight: .semibold, relativeTo: .subheadline) : .subheadline)
                    .foregroundStyle(usesCompactOnboardingChrome ? BrandTheme.homeSecondaryText : BrandTheme.teal)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            BrandTheme.homeActionBar
                .overlay(alignment: .top) {
                    if !usesCompactOnboardingChrome {
                        Rectangle()
                            .fill(BrandTheme.purple.opacity(0.35))
                            .frame(height: 1)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var dietStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick how you like to eat. This sets the macro split. Calories still come from your weight, activity, and pace.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)

            ForEach(DietStyle.allCases) { style in
                DietStyleOptionCard(style: style, isSelected: diet == style) {
                    diet = style
                }
            }
        }
    }

    private var weightsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Units", selection: $usesImperial) {
                Text("lb").tag(true)
                Text("kg").tag(false)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                pieWeightDial(title: "Current weight", value: $currentWeightKg, color: BrandTheme.magenta)
                pieWeightDial(title: "Goal weight", value: $goalWeightKg, color: BrandTheme.teal)
            }

            goalSummaryCard

            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly pace")
                    .font(.headline)
                    .foregroundStyle(BrandTheme.homePrimaryText)

                Text("Based on ~3,500 kcal per pound. We cap pace at a safe, realistic rate.")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)

                if inferredGoalType == .maintain {
                    Text("Maintaining — calories stay at maintenance.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                } else {
                    WeeklyPaceSlider(
                        value: $weeklyLbChange,
                        range: weeklySliderRange,
                        step: 0.25,
                        valueLabel: weeklyPaceLabel,
                        onEditingChanged: { editing in
                            if editing { weeklyManuallySet = true }
                        }
                    )
                }
            }
            .padding(16)
            .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func pieWeightDial(title: String, value: Binding<Double>, color: Color) -> some View {
        let displayBinding = Binding<Double>(
            get: {
                usesImperial ? value.wrappedValue * GoalCalculator.kgToLb : value.wrappedValue
            },
            set: { newDisplay in
                value.wrappedValue = usesImperial ? newDisplay * GoalCalculator.lbToKg : newDisplay
            }
        )
        return PieChartDialSlider(
            title: title,
            value: displayBinding,
            range: weightRange,
            step: usesImperial ? 1 : 0.5,
            unit: usesImperial ? "lb" : "kg",
            color: color
        )
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private var bodyStep: some View {
        VStack(spacing: 8) {
            Text("Help Larry dial in your daily targets.")
                .font(OnboardingType.font(15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            aboutYouSexControl
                .padding(.bottom, 4)

            aboutYouRow("Age") {
                HStack(spacing: 12) {
                    Text("\(age)")
                        .font(OnboardingType.font(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                        .monospacedDigit()
                    Stepper("Age", value: $age, in: 16...90)
                        .labelsHidden()
                        .tint(BrandTheme.teal)
                }
            }

            aboutYouRow("Height") {
                if usesImperial {
                    HStack(spacing: 2) {
                        aboutYouMenuPicker(
                            label: "Feet",
                            value: "\(heightFt) ft",
                            accessibilityValue: "\(heightFt) feet"
                        ) {
                            ForEach(4...7, id: \.self) { value in
                                Text("\(value) ft").tag(value)
                            }
                        } selection: {
                            $heightFt
                        }
                        aboutYouMenuPicker(
                            label: "Inches",
                            value: "\(heightIn) in",
                            accessibilityValue: "\(heightIn) inches"
                        ) {
                            ForEach(0...11, id: \.self) { value in
                                Text("\(value) in").tag(value)
                            }
                        } selection: {
                            $heightIn
                        }
                    }
                    .onChange(of: heightFt) { _, _ in updateHeightCm() }
                    .onChange(of: heightIn) { _, _ in updateHeightCm() }
                } else {
                    HStack(spacing: 12) {
                        Text("\(Int(heightCm)) cm")
                            .font(OnboardingType.font(16, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .monospacedDigit()
                        Stepper("Height", value: $heightCm, in: 120...220, step: 1)
                            .labelsHidden()
                            .tint(BrandTheme.teal)
                    }
                }
            }

            aboutYouRow("Activity Level") {
                aboutYouMenuPicker(
                    label: "Activity Level",
                    value: activity.displayName,
                    accessibilityValue: activity.displayName
                ) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                } selection: {
                    $activity
                }
            }

            if inferredGoalType == .maintain {
                Text("Current and goal weight are close — we'll use maintenance calories.")
                    .font(OnboardingType.font(13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .onAppear { updateHeightCm() }
    }

    private var aboutYouSexControl: some View {
        HStack(spacing: 4) {
            ForEach(Sex.allCases) { option in
                let isSelected = sex == option
                Button {
                    sex = option
                } label: {
                    Text(option.rawValue.capitalized)
                        .font(OnboardingType.font(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(isSelected ? BrandTheme.homePrimaryText : BrandTheme.homeSecondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BrandTheme.homeCardSolid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sex")
    }

    private func aboutYouRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(OnboardingType.font(16, weight: .semibold, relativeTo: .body))
                .foregroundStyle(BrandTheme.homePrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTheme.homeCardSolid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func aboutYouMenuPicker<Selection: Hashable, Content: View>(
        label: String,
        value: String,
        accessibilityValue: String,
        @ViewBuilder content: () -> Content,
        selection: () -> Binding<Selection>
    ) -> some View {
        Picker(selection: selection()) {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .font(OnboardingType.font(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BrandTheme.teal)
            }
        }
        .pickerStyle(.menu)
        .tint(BrandTheme.homePrimaryText)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                LarryAvatarView(portrait: .programPitch, size: 80)
                    .frame(width: 80)

                LarrySpeechBubble(text: larryProgramPitch, maxLines: nil)
                    .padding(.top, 14)
            }

            planMetricRow(
                title: "Diet",
                value: diet.displayName,
                subtitle: diet.macroHint
            )
            planMetricRow(
                title: "Current → goal",
                value: "\(formatWeight(currentWeightKg)) → \(formatWeight(goalWeightKg))"
            )
            planMetricRow(
                title: "Daily calories",
                value: "\(Int(plan.targetCalories)) kcal",
                subtitle: plan.dailyCalorieDelta == 0
                    ? "Maintenance"
                    : "\(plan.dailyCalorieDelta > 0 ? "+" : "")\(Int(plan.dailyCalorieDelta)) vs maintenance"
            )
            if let weeks = plan.weeksToGoal, weeks.isFinite {
                planMetricRow(
                    title: "Estimated timeline",
                    value: timelineLabel(weeks: weeks)
                )
            }

            Divider()
                .overlay(BrandTheme.purple.opacity(0.3))

            Text("Macros (\(plan.coachStyleName))")
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            HStack(spacing: 12) {
                macroChip("Protein", "\(Int(plan.macros.proteinG))g")
                macroChip("Carbs", "\(Int(plan.macros.carbsG))g")
                macroChip("Fat", "\(Int(plan.macros.fatG))g")
            }

            Text(plan.coachSummary)
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)

            Text("On Today, tap calories to see this math. You can pull the goal up to 300 cal lower from there.")
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)

            Text(plan.macroAdvice)
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandTheme.magenta.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(BrandTheme.magenta.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(16)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
        )
    }

    private var progressPhotoStep: some View {
        VStack(spacing: 8) {
            Text("Optional. Snap a torso shot if you want a before pic. You can add photos later from the menu.")
                .font(OnboardingType.font(15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(BrandTheme.homeSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.bottom, 4)

            Image(LarryPortrait.programPitch.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .accessibilityLabel(LarryMcQuade.name)
                .padding(.top, 4)

            Text("Skip it. I won't ride you.")
                .font(OnboardingType.font(16, weight: .medium, relativeTo: .callout).italic())
                .foregroundStyle(BrandTheme.teal)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            if let progressPreview {
                Image(uiImage: progressPreview)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.arms.open")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                    Text("Same lighting, same pose, once a week is plenty. Stored only on this phone.")
                        .font(OnboardingType.font(13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .background(BrandTheme.homeCardSolid, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
            }

            Button {
                showProgressCamera = true
            } label: {
                Label(progressPreview == nil ? "Take photo" : "Retake photo", systemImage: "camera.fill")
                    .font(OnboardingType.font(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.brandAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(OnboardingPressStyle())
            .padding(.top, 12)

            PhotosPicker(selection: $progressPickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(OnboardingType.font(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background(BrandTheme.homeCardSolid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(OnboardingPressStyle())
        }
    }

    // MARK: - Helpers

    private func onboardingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 10))
    }

    private var inferredGoalType: GoalType {
        let diff = goalWeightKg - currentWeightKg
        if diff < -0.5 { return .lose }
        if diff > 0.5 { return .gain }
        return .maintain
    }

    private var goalSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(inferredGoalType.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("≈ \(Int(plan.targetCalories)) kcal/day at this pace")
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTheme.homeCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(BrandTheme.neonBlue.opacity(0.35), lineWidth: 1)
        )
    }

    private var weightRange: ClosedRange<Double> {
        usesImperial ? 90...400 : 40...180
    }

    private var weeklySliderRange: ClosedRange<Double> {
        switch inferredGoalType {
        case .lose: return -2.0...(-0.5)
        case .gain: return 0.25...0.75
        case .maintain: return 0...0
        }
    }

    private var weeklyPaceLabel: String {
        if inferredGoalType == .maintain { return "Maintaining" }
        let absLb = abs(weeklyLbChange)
        let dir = weeklyLbChange < 0 ? "lose" : "gain"
        return String(format: "%.2f lb/week (%@)", absLb, dir)
    }

    private var larryProgramPitch: String {
        if let weeks = plan.weeksToGoal, weeks.isFinite {
            let rounded = max(1, Int(weeks.rounded()))
            return "You can look jacked like me if you follow my \(rounded)-week program."
        }
        return "You can look jacked like me if you follow my program."
    }

    private func loadExistingProfileIfNeeded() {
        guard !didLoadExistingProfile else { return }
        didLoadExistingProfile = true
        let descriptor = FetchDescriptor<UserSettings>()
        guard let existing = (try? context.fetch(descriptor))?.first else { return }

        sex = existing.sex
        age = existing.age
        usesImperial = existing.usesImperialUnits
        currentWeightKg = existing.weightKg
        goalWeightKg = existing.effectiveGoalWeightKg
        activity = existing.activity
        if existing.hasChosenDiet {
            diet = existing.dietStyle
        }
        if let weekly = existing.weeklyLbChangeTarget {
            weeklyLbChange = weekly
            weeklyManuallySet = true
        }

        let totalInches = Int((existing.heightCm / 2.54).rounded())
        heightFt = min(7, max(4, totalInches / 12))
        heightIn = min(11, max(0, totalInches % 12))
        heightCm = existing.heightCm
    }

    private func syncWeeklyIfNeeded() {
        guard !weeklyManuallySet else { return }
        let suggested = GoalCalculator.recommendedWeeklyLbChange(
            currentLb: currentWeightKg * GoalCalculator.kgToLb,
            goalLb: goalWeightKg * GoalCalculator.kgToLb,
            goalType: inferredGoalType
        )
        weeklyLbChange = suggested
    }

    private func updateHeightCm() {
        heightCm = Double(heightFt * 12 + heightIn) * 2.54
    }

    private func formatWeight(_ kg: Double) -> String {
        if usesImperial {
            return String(format: "%.0f lb", kg * GoalCalculator.kgToLb)
        }
        return String(format: "%.0f kg", kg)
    }

    private func formatWeightDisplay(_ displayValue: Double) -> String {
        if usesImperial {
            return String(format: "%.0f lb", displayValue)
        }
        return String(format: "%.1f kg", displayValue)
    }

    private func timelineLabel(weeks: Double) -> String {
        if weeks < 8 { return String(format: "~%.0f weeks", weeks.rounded()) }
        let months = weeks / 4.33
        return String(format: "~%.0f months (%.0f weeks)", months.rounded(), weeks.rounded())
    }

    private func planMetricRow(title: String, value: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BrandTheme.homeSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(BrandTheme.homeActionBar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BrandTheme.purple.opacity(0.25), lineWidth: 1)
        )
    }

    private func advance() {
        if step < totalSteps - 1 {
            step += 1
            if step == 4 { syncWeeklyIfNeeded() }
        } else {
            finish()
        }
    }

    private func finish() {
        saveError = nil
        let settings = persistSettings()
        ensureTodayGoal(for: settings)
        seedDefaultPhrases()

        do {
            try context.save()
            TrackingCycleService.ensureStarted()
            if let progressPreview {
                _ = ProgressPhotoStore.shared.add(image: progressPreview, isBaseline: true)
            }
            appState.hasCompletedOnboarding = true
            if appState.pendingChallengeToken == nil {
                appState.openLarryChatOnNextAppear = true
            }
        } catch {
            saveError = "Couldn't save your plan. Please try again."
        }
    }

    private func persistSettings() -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try? context.fetch(descriptor).first {
            applyFormValues(to: existing)
            return existing
        }

        let settings = UserSettings(
            sex: sex,
            age: age,
            heightCm: heightCmValue,
            weightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            weeklyLbChangeTarget: weeklyLbChange,
            usesImperialUnits: usesImperial,
            activity: activity,
            goalType: inferredGoalType,
            dietStyle: diet,
            trainerVoice: LarryMcQuade.defaultVoice
        )
        context.insert(settings)
        return settings
    }

    private func applyFormValues(to settings: UserSettings) {
        settings.sex = sex
        settings.age = age
        settings.heightCm = heightCmValue
        settings.weightKg = currentWeightKg
        settings.goalWeightKg = goalWeightKg
        settings.weeklyLbChangeTarget = weeklyLbChange
        settings.usesImperialUnits = usesImperial
        settings.activity = activity
        settings.goalType = inferredGoalType
        settings.dietStyle = diet
        if settings.trainerVoice.isEmpty {
            settings.trainerVoice = LarryMcQuade.defaultVoice
        }
    }

    private func ensureTodayGoal(for settings: UserSettings) {
        let macros = GoalCalculator.recommendedMacros(for: settings)
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyGoal>()
        let goals = (try? context.fetch(descriptor)) ?? []

        if let existing = goals.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            existing.calories = macros.calories
            existing.proteinG = macros.proteinG
            existing.carbsG = macros.carbsG
            existing.fatG = macros.fatG
        } else {
            context.insert(DailyGoal(
                date: Date(),
                calories: macros.calories,
                proteinG: macros.proteinG,
                carbsG: macros.carbsG,
                fatG: macros.fatG
            ))
        }
    }

    private var heightCmValue: Double {
        if usesImperial {
            return Double(heightFt * 12 + heightIn) * 2.54
        }
        return heightCm
    }

    private func seedDefaultPhrases() {
        let descriptor = FetchDescriptor<TrainerPhrase>()
        if let count = try? context.fetchCount(descriptor), count > 0 { return }

        let defaults = LarryMcQuade.defaultPhrases
        for (text, tag) in defaults {
            context.insert(TrainerPhrase(text: text, tag: tag))
        }
    }
}

// MARK: - Onboarding sliders

private struct PieChartDialSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let color: Color

    private let dialSize: CGFloat = 148
    private let ringWidth: CGFloat = 14

    private var progress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.homePrimaryText)

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = size / 2 - ringWidth

                ZStack {
                    OnboardingPieSlice(progress: progress)
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.35), color.opacity(0.08)],
                                center: .center,
                                startRadius: 0,
                                endRadius: radius
                            )
                        )
                        .frame(width: radius * 2, height: radius * 2)

                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: ringWidth)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .shadow(color: color.opacity(0.55), radius: 4)
                        .offset(knobOffset(radius: radius))

                    VStack(spacing: 2) {
                        Text(formattedValue)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(BrandTheme.homePrimaryText)
                        Text(unit)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BrandTheme.homeSecondaryText)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            updateValue(from: gesture.location, center: center, radius: radius)
                        }
                )
            }
            .frame(width: dialSize, height: dialSize)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(formattedValue) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = snap(value + step)
            case .decrement:
                value = snap(value - step)
            @unknown default:
                break
            }
        }
    }

    private var formattedValue: String {
        if step >= 1 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func knobOffset(radius: CGFloat) -> CGSize {
        let angle = progress * 2 * Double.pi - Double.pi / 2
        return CGSize(
            width: CGFloat(cos(angle)) * radius,
            height: CGFloat(sin(angle)) * radius
        )
    }

    private func updateValue(from location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let normalized = angle / (2 * .pi)
        let raw = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        value = snap(raw)
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct OnboardingPieSlice: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct WeeklyPaceSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: String
    var onEditingChanged: ((Bool) -> Void)? = nil

    private var progress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(valueLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)

            GeometryReader { geo in
                let trackHeight: CGFloat = 8
                let thumbSize: CGFloat = 22
                let inset: CGFloat = 11
                let usable = max(geo.size.width - inset * 2, 1)
                let thumbX = inset + progress * usable

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrandTheme.homeCard)
                        .frame(height: trackHeight)
                        .overlay {
                            Capsule()
                                .stroke(BrandTheme.purple.opacity(0.35), lineWidth: 1)
                        }

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BrandTheme.magenta, BrandTheme.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(thumbX, inset), height: trackHeight)

                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: BrandTheme.magenta.opacity(0.45), radius: 4, y: 2)
                        .overlay {
                            Circle()
                                .stroke(BrandTheme.magenta, lineWidth: 2)
                        }
                        .offset(x: thumbX - thumbSize / 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            onEditingChanged?(true)
                            updateValue(at: gesture.location.x, width: geo.size.width, inset: inset)
                        }
                        .onEnded { _ in
                            onEditingChanged?(false)
                        }
                )
            }
            .frame(height: 36)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("More disciplined")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Text("Faster pace")
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Manageable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                    Text("Easier to sustain")
                        .font(.caption2)
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly pace: \(valueLabel)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = snap(value + step)
            case .decrement:
                value = snap(value - step)
            @unknown default:
                break
            }
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat, inset: CGFloat) {
        let usable = max(width - inset * 2, 1)
        let normalized = min(max((x - inset) / usable, 0), 1)
        let raw = range.lowerBound + Double(normalized) * (range.upperBound - range.lowerBound)
        value = snap(raw)
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

