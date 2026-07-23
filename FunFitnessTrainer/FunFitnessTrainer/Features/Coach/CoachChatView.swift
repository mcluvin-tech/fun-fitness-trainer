import SwiftUI
import SwiftData

struct ChatBubble: Identifiable {
    let id: UUID
    let text: String
    let isUser: Bool

    init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
}

struct CoachChatView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.loggedAt, order: .reverse) private var allMeals: [Meal]
    @Query(sort: \ExerciseLog.loggedAt, order: .reverse) private var allExercises: [ExerciseLog]
    @Query private var goals: [DailyGoal]
    @Query private var settingsList: [UserSettings]
    @Query private var phrases: [TrainerPhrase]

    @StateObject private var voice = VoiceCoachService()
    @State private var messages: [ChatBubble] = []
    @State private var input = ""
    @State private var isLoading = false
    @State private var showKeyboard = false
    @State private var voiceError: String?

    private var todayMeals: [Meal] {
        DaySummaryService.mealsToday(from: allMeals)
    }

    private var consumed: MacroTotals {
        DaySummaryService.totals(for: todayMeals)
    }

    private var todayGoal: DailyGoal? {
        DaySummaryService.goal(for: Date(), goals: goals)
    }

    private var todayExercises: [ExerciseLog] {
        DaySummaryService.exercisesToday(from: allExercises)
    }

    private var exerciseBurned: Double {
        DaySummaryService.exerciseCaloriesBurned(for: todayExercises)
    }

    private var baseGoalPayload: MacroGoalPayload? {
        if let goal = todayGoal {
            return MacroGoalPayload(
                calories: goal.calories,
                proteinG: goal.proteinG,
                carbsG: goal.carbsG,
                fatG: goal.fatG
            )
        }
        return settingsList.first.map { GoalCalculator.recommendedMacros(for: $0) }
    }

    private var goalPayload: MacroGoalPayload? {
        guard let base = baseGoalPayload else { return nil }
        return DaySummaryService.effectiveGoal(base: base, exerciseCalorieBonus: exerciseBurned)
    }

    private var remainingMacros: MacroTotals? {
        guard let goalPayload else { return nil }
        return DaySummaryService.remaining(consumed: consumed, goal: goalPayload)
    }

    private var userWeightKg: Double {
        settingsList.first?.weightKg ?? 75
    }

    private var goalTypeLabel: String {
        settingsList.first?.resolvedGoalType.rawValue ?? "lose"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LarryHeaderView(portrait: .happy)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(BrandTheme.headerGradient)

                if todayGoal == nil, let payload = baseGoalPayload {
                    noGoalBanner(payload)
                }

                if let payload = goalPayload {
                    macroFactsStrip(payload)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty && !isLoading {
                                emptyPrompt
                            }
                            ForEach(messages) { msg in
                                chatBubble(msg)
                                    .id(msg.id)
                            }
                            if isLoading {
                                HStack(spacing: 8) {
                                    LarryAvatarView(portrait: .carrots, size: 32)
                                    ProgressView("Larry is thinking…")
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                voiceInputBar
            }
            .navigationTitle(LarryMcQuade.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !AppConfig.hasBackend {
                        Text("Offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                restoreTodayChat()
                await voice.prepare()
                await greetIfNeeded()
            }
            .alert("Voice unavailable", isPresented: .init(
                get: { voice.permissionDenied },
                set: { _ in }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable Microphone and Speech Recognition for Larry in Settings → \(LarryMcQuade.appName).")
            }
        }
    }

    private var voiceInputBar: some View {
        VStack(spacing: 10) {
            if voice.isRecording, !voice.liveTranscript.isEmpty {
                Text(voice.liveTranscript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else if let voiceError {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 16) {
                Button {
                    showKeyboard.toggle()
                } label: {
                    Image(systemName: showKeyboard ? "mic.fill" : "keyboard")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(showKeyboard ? "Use voice" : "Type instead")

                Button(action: micTapped) {
                    ZStack {
                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 72, height: 72)
                        Image(systemName: micIconName)
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .disabled(!voice.isReady || isLoading)
                .accessibilityLabel(voice.isRecording ? "Stop and send" : "Talk to Larry")
            }

            if showKeyboard {
                HStack(spacing: 10) {
                    TextField("Type to Larry…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    Button("Send") { sendUser(input, voiceMode: false) }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            } else {
                Text(voice.isRecording ? "Tap when you're done talking" : "Tap the mic — Larry replies in the chat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var micButtonColor: Color {
        if voice.isRecording { return .red }
        if isLoading { return .gray }
        return BrandTheme.purple
    }

    private var micIconName: String {
        voice.isRecording ? "stop.fill" : "mic.fill"
    }

    private func micTapped() {
        voiceError = nil
        if voice.isRecording {
            let transcript = voice.stopRecording()
            guard !transcript.isEmpty else {
                voiceError = "Didn't catch that — try again."
                return
            }
            sendUser(transcript, voiceMode: true)
        } else {
            do {
                try voice.startRecording()
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }

    private func macroFactsStrip(_ payload: MacroGoalPayload) -> some View {
        HStack(spacing: 12) {
            factPill("Today", "\(Int(consumed.calories)) / \(Int(payload.calories)) cal")
            factPill("Protein", "\(Int(consumed.proteinG)) / \(Int(payload.proteinG))g")
            if exerciseBurned > 0 {
                factPill("Earned", "+\(Int(exerciseBurned))")
            } else if todayMeals.count > 0 {
                factPill("Meals", "\(todayMeals.count)")
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(BrandTheme.teal.opacity(0.08))
    }

    private func factPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private var emptyPrompt: some View {
        HStack(alignment: .top, spacing: 10) {
            LarryAvatarView(portrait: .discipline, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(LarryMcQuade.tagline)
                    .font(.subheadline.weight(.semibold))
                Text("Say what you ate or drank to log it, tell Larry about a workout to earn calories, or ask about food or drinks you're thinking of having.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func noGoalBanner(_ payload: MacroGoalPayload) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("No target set for today")
                    .font(.subheadline.weight(.semibold))
                Text("\(Int(payload.calories)) cal · P \(Int(payload.proteinG))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Use plan") { applyGoal(payload) }
                .buttonStyle(.borderedProminent)
                .tint(BrandTheme.purple)
        }
        .padding()
        .background(BrandTheme.purple.opacity(0.12))
    }

    @ViewBuilder
    private func chatBubble(_ msg: ChatBubble) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if msg.isUser {
                Spacer(minLength: 48)
            } else {
                LarryAvatarView(portrait: .carrots, size: 32)
            }

            Text(msg.text)
                .padding(12)
                .background(
                    msg.isUser
                        ? BrandTheme.magenta.opacity(0.2)
                        : BrandTheme.purple.opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !msg.isUser {
                Spacer(minLength: 48)
            }
        }
    }

    private func restoreTodayChat() {
        let stored = CoachChatPersistence.loadBubbles()
        guard !stored.isEmpty else { return }
        messages = stored.map {
            ChatBubble(id: $0.id, text: $0.text, isUser: $0.isUser)
        }
    }

    private func persistChat() {
        let stored = messages.map {
            CoachChatPersistence.StoredBubble(
                id: $0.id,
                text: $0.text,
                isUser: $0.isUser,
                createdAt: Date()
            )
        }
        CoachChatPersistence.save(stored)
    }

    private func greetIfNeeded() async {
        guard messages.isEmpty, !CoachChatPersistence.hasGreetedToday() else { return }
        CoachChatPersistence.markGreetedToday()
        isLoading = true
        defer { isLoading = false }

        let settings = settingsList.first
        let voicePrompt = resolvedVoice(settings)
        let samplePhrases = phrases.map(\.text)

        let response = await TrainerService.chatSafely(
            mode: "voice",
            messages: [ChatMessageDTO(role: "user", content: "Say a short hello and give me one fact about my macros today.")],
            trainerVoice: voicePrompt,
            phrases: samplePhrases,
            goal: goalPayload,
            consumed: consumed,
            remaining: remainingMacros,
            goalType: goalTypeLabel,
            exerciseCaloriesBurned: exerciseBurned,
            weightKg: userWeightKg
        )
        appendLarryMessages(response)
        persistChat()
        applySuggestedMeal(response.suggested_meal)
        applySuggestedExercise(response.suggested_exercise)
        markCoachSeenToday()
    }

    private func sendUser(_ text: String, voiceMode: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        messages.append(ChatBubble(text: trimmed, isUser: true))
        persistChat()
        Task { await reply(voiceMode: voiceMode) }
    }

    private func reply(voiceMode: Bool) async {
        isLoading = true
        defer { isLoading = false }

        let dtos = messages.map { ChatMessageDTO(role: $0.isUser ? "user" : "assistant", content: $0.text) }
        let settings = settingsList.first

        let response = await TrainerService.chatSafely(
            mode: voiceMode ? "voice" : "chat",
            messages: dtos,
            trainerVoice: resolvedVoice(settings),
            phrases: phrases.map(\.text),
            goal: goalPayload,
            consumed: consumed,
            remaining: remainingMacros,
            goalType: goalTypeLabel,
            exerciseCaloriesBurned: exerciseBurned,
            weightKg: userWeightKg
        )
        appendLarryMessages(response)
        persistChat()
        applySuggestedMeal(response.suggested_meal)
        applySuggestedExercise(response.suggested_exercise)
        markCoachSeenToday()
    }

    private func appendLarryMessages(_ response: TrainerChatResponse) {
        for text in response.chatReplies {
            messages.append(ChatBubble(text: text, isUser: false))
        }
    }

    private func applySuggestedMeal(_ payload: MealPayload?) {
        guard let payload else { return }
        // Insert immediately so Today's log and macro rings update cumulatively.
        let inserted = MealLogging.insertReturningMeals(payload, into: context)

        let source = latestFoodLogDescription() ?? payload.name
        Task {
            let resolved = await FoodAnalysisService.resolveMealForLogging(from: source)
            guard resolved.isLabelBacked else { return }
            await MainActor.run {
                MealLogging.replace(meals: inserted, with: resolved, in: context)
            }
        }
    }

    private func latestFoodLogDescription() -> String? {
        guard let text = messages.last(where: { $0.isUser })?.text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return FoodItemNaming.loggedFoodDescription(from: trimmed) ?? trimmed
    }

    private func applySuggestedExercise(_ payload: ExercisePayload?) {
        guard let payload else { return }
        ExerciseLogging.insert(payload, into: context)
    }

    private func resolvedVoice(_ settings: UserSettings?) -> String {
        let voice = settings?.trainerVoice ?? ""
        return voice.isEmpty ? LarryMcQuade.defaultVoice : voice
    }

    private func applyGoal(_ payload: MacroGoalPayload) {
        let start = DaySummaryService.startOfDay()
        if let existing = goals.first(where: { Calendar.current.isDate($0.date, inSameDayAs: start) }) {
            existing.calories = payload.calories
            existing.proteinG = payload.proteinG
            existing.carbsG = payload.carbsG
            existing.fatG = payload.fatG
        } else {
            context.insert(DailyGoal(
                date: Date(),
                calories: payload.calories,
                proteinG: payload.proteinG,
                carbsG: payload.carbsG,
                fatG: payload.fatG
            ))
        }
        markCoachSeenToday()
        try? context.save()
        let reply = "Targets locked in, baby. ~\(Int(payload.calories)) calories and \(Int(payload.proteinG)) grams protein today. Discipline tastes better than regret!"
        messages.append(ChatBubble(text: reply, isUser: false))
        persistChat()
    }

    private func markCoachSeenToday() {
        if let settings = settingsList.first {
            settings.lastMorningRitualDate = Date()
            try? context.save()
        }
    }
}
