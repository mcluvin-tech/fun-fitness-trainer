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

private enum LarryTalkPhase: Equatable {
    case idle
    case listening
    case thinking
    case reply
}

struct CoachChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Meal.loggedAt, order: .reverse) private var allMeals: [Meal]
    @Query(sort: \ExerciseLog.loggedAt, order: .reverse) private var allExercises: [ExerciseLog]
    @Query private var goals: [DailyGoal]
    @Query private var settingsList: [UserSettings]
    @Query private var phrases: [TrainerPhrase]

    /// When embedded in the floating tab bar, hide the close control and leave room for the dock.
    var showsCloseButton: Bool = true
    var onReturnHome: (() -> Void)? = nil

    @StateObject private var voice = VoiceCoachService()
    @ObservedObject private var healthKit = HealthKitService.shared
    @State private var messages: [ChatBubble] = []
    @State private var input = ""
    @State private var isLoading = false
    @State private var showKeyboard = false
    @State private var keyboardOverlap: CGFloat = 0
    @FocusState private var composerFocused: Bool
    @State private var voiceError: String?
    @State private var phase: LarryTalkPhase = .idle
    @State private var larryReply = ""
    @State private var replyEmotion: LarryEmotion = .neutral
    @State private var bounce = false
    @State private var poseTick = 0
    @State private var displayedConsumed: MacroTotals?
    @State private var doneProgress: CGFloat = 0
    /// Auto-dismiss only after a food log. Recommendations stay on screen.
    @State private var dismissAfterReply = false
    @State private var dinnerPlates: [TrainerService.DinnerPlate] = []
    @State private var dinnerHeader = ""
    @State private var platesAppeared = false

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
        DaySummaryService.activityCalorieBonus(
            manualExerciseCalories: DaySummaryService.exerciseCaloriesBurned(for: todayExercises),
            healthKitActiveEnergy: healthKit.calorieBonusFromHealth,
            useHealthKit: healthKit.isConnected
        )
    }

    private var baseGoalPayload: MacroGoalPayload? {
        DaySummaryService.foodTarget(from: settingsList.first)
    }

    private var goalPayload: MacroGoalPayload? {
        baseGoalPayload
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

    private var displayedBubble: String {
        switch phase {
        case .idle:
            return idlePrompt
        case .listening:
            let live = voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            return live.isEmpty ? "Go. I'm listening." : live
        case .thinking:
            return "Give me a second..."
        case .reply:
            return larryReply
        }
    }

    private var idlePrompt: String {
        if consumed.calories > 0 {
            return "\(Int(consumed.calories)) calories. Don't get comfortable. What else did you eat?"
        }
        return "I'm not here to babysit. What did you eat?"
    }

    private var idleEmotion: LarryEmotion {
        guard let goal = goalPayload, goal.calories > 0 else { return .neutral }
        if consumed.calories <= 0 { return .neutral }
        let overBy = consumed.calories - goal.calories
        if overBy >= goal.calories * 0.15 { return .shocked }
        if overBy >= 150 { return .disappointed }
        if overBy > 40 { return .skeptical }
        if consumed.proteinG >= goal.proteinG, overBy <= 0 { return .excited }
        if consumed.proteinG >= goal.proteinG * 0.85, overBy <= 0 { return .confident }
        return .neutral
    }

    private var activePose: LarryVoicePose {
        if voiceError != nil, phase == .idle { return .surprised }
        switch phase {
        case .idle:
            return LarryPoseSelector.pose(for: idleEmotion, seed: 1)
        case .listening:
            let live = voice.liveTranscript
            if let matched = LarryEmotion.detected(in: live) {
                return LarryPoseSelector.pose(for: matched, seed: poseTick, flavorText: live)
            }
            let cycle = live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? LarryVoicePose.listeningStartCycle
                : LarryVoicePose.listeningTalkCycle
            return cycle[poseTick % cycle.count]
        case .thinking:
            return .thinking
        case .reply:
            return LarryPoseSelector.pose(
                for: replyEmotion,
                seed: LarryPoseSelector.seed(for: larryReply),
                flavorText: larryReply
            )
        }
    }

    var body: some View {
        ZStack {
            coachBackground

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if phase == .reply, !dinnerPlates.isEmpty {
                                dinnerOptionsPanel
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                                    .id("conversationTop")
                            } else {
                                larryStage
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: keyboardOverlap > 0 ? 220 : 360)
                                    .id("conversationTop")
                            }
                            Color.clear.frame(height: 12).id("conversationBottom")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    .onChange(of: dinnerPlates.count) { _, _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            proxy.scrollTo("conversationTop", anchor: .top)
                        }
                    }
                }

                voiceInputBar
            }
            .padding(.bottom, keyboardOverlap)
            .safeAreaInset(edge: .bottom) {
                if !showsCloseButton, keyboardOverlap == 0, !(phase == .reply && dismissAfterReply) {
                    Color.clear.frame(height: 88)
                }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                        updateKeyboardOverlap(note, viewBottom: geo.frame(in: .global).maxY)
                    }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            restoreTodayChat()
            await healthKit.bootstrapIfConnected()
            await voice.prepare()
            bounce = true
            displayedConsumed = consumed
        }
        .onChange(of: consumed) { _, newValue in
            guard phase != .reply else { return }
            displayedConsumed = newValue
        }
        .onChange(of: showKeyboard) { _, show in
            composerFocused = show
        }
        .onChange(of: dinnerPlates) { _, plates in
            platesAppeared = false
            guard !plates.isEmpty else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78).delay(0.05)) {
                platesAppeared = true
            }
        }
        .alert("Voice unavailable", isPresented: .init(
            get: { voice.permissionDenied },
            set: { _ in }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Microphone and Speech Recognition for Larry in Settings → \(LarryMcQuade.appName).")
        }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.8), trigger: phase)
    }

    /// Quieter coach-only backdrop so conversation hierarchy reads first.
    private var coachBackground: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.06)
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.04, blue: 0.14),
                    Color(red: 0.03, green: 0.02, blue: 0.07),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [BrandTheme.purple.opacity(0.14), .clear],
                center: .top,
                startRadius: 24,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsCloseButton {
                Button {
                    returnHome()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                        .frame(width: 36, height: 36)
                        .background(BrandTheme.homeCard, in: Circle())
                }
                .accessibilityLabel("Close")
            }

            if let payload = goalPayload {
                let shown = displayedConsumed ?? consumed
                HStack(spacing: 10) {
                    Text("\(Int(shown.calories)) / \(Int(payload.calories)) cal")
                    Text("P \(Int(shown.proteinG))g")
                    if healthKit.isConnected {
                        Text("\(Int(healthKit.stepsToday).formatted()) steps")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(BrandTheme.homeTertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            if todayGoal == nil, let payload = baseGoalPayload {
                Button("Use plan") { applyGoal(payload) }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.purple)
                    .controlSize(.small)
            }
        }
    }

    private var dinnerOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                LarryHeroImage(pose: activePose, maxHeight: 124)
                    .frame(width: 112, height: 124)
                    .modifier(
                        LarryEntranceMotion(
                            motion: LarryReactionMotion.forEmotion(replyEmotion),
                            replayID: dinnerHeader.isEmpty ? larryReply : dinnerHeader
                        )
                    )
                    .accessibilityHidden(true)

                Text(dinnerHeader.isEmpty ? larryReply : dinnerHeader)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            .padding(.bottom, 2)

            VStack(spacing: 8) {
                ForEach(Array(dinnerPlates.enumerated()), id: \.element.id) { index, plate in
                    dinnerPlateCard(plate)
                        .opacity(platesAppeared ? 1 : 0)
                        .offset(y: platesAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.38, dampingFraction: 0.78)
                                .delay(Double(index) * 0.055),
                            value: platesAppeared
                        )
                }
            }
        }
    }

    private func dinnerPlateCard(_ plate: TrainerService.DinnerPlate) -> some View {
        Button {
            HomeHaptics.soft()
            pickDinnerPlate(plate)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(plate.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrandTheme.homePrimaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(plate.calories) cal")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrandTheme.teal)
                        Text("\(plate.protein)g protein")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrandTheme.teal)
                        Text("\(plate.carbs)g C · \(plate.fat)g F")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BrandTheme.homeTertiaryText)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 4)

                VStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrandTheme.teal.opacity(0.9))
                    Text("Log this")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrandTheme.homeCardSolid.opacity(0.92))
                    .shadow(color: BrandTheme.purple.opacity(0.18), radius: 14, y: 6)
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plate.name), \(plate.calories) calories, \(plate.protein) grams protein. Log this.")
    }

    private var larryStage: some View {
        VStack(spacing: 10) {
            LarryFloatingLine(text: displayedBubble)
                .id(displayedBubble)
                .padding(.horizontal, 24)
                .zIndex(1)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.86, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: displayedBubble)

            larryPortrait
        }
        .padding(.bottom, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: activePose)
        .task(id: phase) {
            poseTick = 0
            guard phase == .listening else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_150_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    poseTick += 1
                }
            }
        }
    }

    @ViewBuilder
    private var larryPortrait: some View {
        if phase == .reply {
            LarryHeroImage(pose: activePose, maxHeight: larryHeight)
                .id(activePose)
                .frame(maxWidth: larryHeight, maxHeight: larryHeight)
                .modifier(
                    LarryEntranceMotion(
                        motion: LarryReactionMotion.forEmotion(replyEmotion),
                        replayID: larryReply
                    )
                )
        } else {
            LarryHeroImage(pose: activePose, maxHeight: larryHeight)
                .id(activePose)
                .frame(maxWidth: larryHeight, maxHeight: larryHeight)
                .scaleEffect(phase == .listening ? 1.03 : 1)
                .offset(y: bounce ? -bounceHeight : bounceHeight)
                .rotationEffect(.degrees(phase == .thinking ? (bounce ? 2.4 : -2.4) : 0))
                .animation(
                    .easeInOut(duration: bounceDuration).repeatForever(autoreverses: true),
                    value: bounce
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: activePose)
        }
    }

    /// Shrink Larry while the keyboard is up so the typed line stays on screen.
    private var larryHeight: CGFloat {
        if keyboardOverlap > 0 { return 168 }
        return 280
    }

    private var bounceHeight: CGFloat {
        switch phase {
        case .idle: return 4
        case .listening: return 6
        case .thinking: return 8
        case .reply: return 3
        }
    }

    private var bounceDuration: Double {
        switch phase {
        case .thinking: return 0.32
        case .listening: return 0.55
        case .idle: return 1.05
        case .reply: return 1.2
        }
    }

    private var voiceInputBar: some View {
        VStack(spacing: 10) {
            if let voiceError {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            if phase == .reply, dismissAfterReply {
                Button(action: returnHome) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BrandTheme.teal.opacity(0.28))
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [BrandTheme.teal, BrandTheme.magenta.opacity(0.9)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .scaleEffect(x: doneProgress, y: 1, anchor: .leading)
                        Text("Done")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .accessibilityLabel("Done")
                .transition(.move(edge: .bottom).combined(with: .opacity))

                Button {
                    keepTalking()
                } label: {
                    Text("Tell Larry something")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BrandTheme.homeSecondaryText)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                modernComposer
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: voice.isRecording)
        .task(id: replyTimerID) {
            guard phase == .reply, dismissAfterReply else {
                doneProgress = 0
                return
            }
            doneProgress = 0
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 2)) {
                doneProgress = 1
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, phase == .reply, dismissAfterReply else { return }
            returnHome()
        }
    }

    private var modernComposer: some View {
        HStack(alignment: .center, spacing: 10) {
            if voice.isRecording {
                listeningComposerBody
            } else {
                TextField("Message Larry…", text: $input, axis: .vertical)
                    .focused($composerFocused)
                    .font(.body.weight(.medium))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .tint(BrandTheme.teal)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { sendUser(input, voiceMode: false) }
                    .disabled(isLoading)
            }

            Button(action: micTapped) {
                Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle()
                            .fill(voice.isRecording ? Color.red : BrandTheme.purple)
                            .shadow(
                                color: (voice.isRecording ? Color.red : BrandTheme.purple).opacity(0.45),
                                radius: voice.isRecording ? 10 : 8,
                                y: 2
                            )
                    }
            }
            .disabled(!voice.isReady || isLoading)
            .accessibilityLabel(voice.isRecording ? "Stop and send" : "Talk to Larry")

            if !voice.isRecording {
                Button {
                    sendUser(input, voiceMode: false)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSendText ? .white : BrandTheme.homeTertiaryText)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(canSendText ? BrandTheme.teal : BrandTheme.homeCardSolid)
                        }
                }
                .disabled(!canSendText || isLoading)
                .accessibilityLabel("Send")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(BrandTheme.homeActionBar)
                )
                .shadow(color: BrandTheme.purple.opacity(voice.isRecording ? 0.28 : 0.16), radius: 16, y: 6)
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    voice.isRecording ? BrandTheme.teal.opacity(0.45) : Color.white.opacity(0.08),
                    lineWidth: voice.isRecording ? 1.2 : 0.5
                )
        }
    }

    private var listeningComposerBody: some View {
        HStack(spacing: 12) {
            ListeningWaveform(active: bounce)
                .frame(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(listeningLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.homePrimaryText)
                    .lineLimit(1)
                Text("Tap stop when you're done")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BrandTheme.homeTertiaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(listeningLabel)
    }

    private var listeningLabel: String {
        let live = voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if live.isEmpty { return "Listening…" }
        return live
    }

    private var canSendText: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The tab shell ignores the keyboard, so lift the composer by the covered distance.
    private func updateKeyboardOverlap(_ note: Notification, viewBottom: CGFloat) {
        guard !showsCloseButton else { return }
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, viewBottom - frame.minY)
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardOverlap = overlap
        }
    }

    private func micTapped() {
        voiceError = nil
        if voice.isRecording {
            let transcript = voice.stopRecording()
            guard !transcript.isEmpty else {
                phase = .idle
                voiceError = "Didn't catch that. Try again."
                return
            }
            sendUser(transcript, voiceMode: true)
        } else {
            showKeyboard = false
            composerFocused = false
            do {
                try voice.startRecording()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    phase = .listening
                }
            } catch {
                voiceError = error.localizedDescription
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

    private func sendUser(_ text: String, voiceMode: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        messages.append(ChatBubble(text: trimmed, isUser: true))
        persistChat()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            phase = .thinking
        }
        Task { await reply(voiceMode: voiceMode) }
    }

    private func reply(voiceMode: Bool) async {
        isLoading = true
        defer { isLoading = false }

        let lastUser = messages.last(where: { $0.isUser })?.text ?? ""
        // Intercept dinner asks in the UI so cards show even if the backend path fails.
        if TrainerService.isOpenMealAsk(lastUser) {
            let goal = goalPayload ?? MacroGoalPayload(calories: 2000, proteinG: 150, carbsG: 180, fatG: 60)
            let left = remainingMacros ?? MacroTotals(calories: 800, proteinG: 50, carbsG: 70, fatG: 25)
            let pack = TrainerService.mealSuggestionPack(remaining: left, goal: goal, utterance: lastUser)
            presentDinnerSuggestions(pack)
            persistChat()
            markCoachSeenToday()
            return
        }

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
            weightKg: userWeightKg,
            stepsToday: healthKit.isConnected ? healthKit.stepsToday : nil,
            stepGoal: HealthActivityPreferences.stepGoal,
            settings: settings
        )
        presentLarry(response, isMealLog: response.suggested_meal != nil)
        persistChat()
        if response.clear_todays_log == true {
            clearTodaysLog()
        } else {
            applySuggestedMeal(response.suggested_meal)
            applySuggestedExercise(response.suggested_exercise)
        }
        // Ignore response.suggested_goal — daily targets come from GoalCalculator only.
        markCoachSeenToday()
    }

    private func presentDinnerSuggestions(_ pack: TrainerService.MealSuggestionPack) {
        messages.append(ChatBubble(text: pack.spoken, isUser: false))
        dismissAfterReply = false
        replyEmotion = .neutral
        platesAppeared = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            dinnerPlates = pack.plates
            dinnerHeader = pack.header
            larryReply = pack.header
            phase = .reply
        }
    }

    private func pickDinnerPlate(_ plate: TrainerService.DinnerPlate) {
        dinnerPlates = []
        dinnerHeader = ""
        sendUser("I'm having \(plate.name)", voiceMode: false)
    }

    private func presentLarry(_ response: TrainerChatResponse, isMealLog: Bool = false) {
        let spoken = response.spokenReply
        guard !spoken.isEmpty else {
            phase = .idle
            return
        }
        messages.append(ChatBubble(text: spoken, isUser: false))
        // #region agent log
        AgentDebugLog.emit(
            hypothesisId: "C",
            location: "CoachChatView.presentLarry",
            message: "spoken reply before any nutrition lookup",
            data: [
                "spoken": String(spoken.prefix(240)),
                "isMealLog": isMealLog,
            ]
        )
        // #endregion
        // Food logs get the short Done timer. Recommendations stay until you answer.
        dismissAfterReply = isMealLog
        dinnerPlates = []
        dinnerHeader = ""
        replyEmotion = LarryEmotion.fromReply(spoken)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            larryReply = spoken
            phase = .reply
        }
    }

    private var replyTimerID: String {
        "\(phase)-\(dismissAfterReply)"
    }

    private func keepTalking() {
        showKeyboard = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            phase = .idle
            larryReply = ""
            dinnerPlates = []
            dinnerHeader = ""
            dismissAfterReply = false
        }
    }

    private func returnHome() {
        if let onReturnHome {
            onReturnHome()
        } else {
            dismiss()
        }
    }

    private func clearTodaysLog() {
        for meal in todayMeals {
            context.delete(meal)
        }
        for exercise in todayExercises {
            context.delete(exercise)
        }
        try? context.save()
    }

    private func applySuggestedMeal(_ payload: MealPayload?) {
        if applyQuantityCorrectionFromLatestUserMessage() { return }
        guard let payload else { return }
        let inserted = MealLogging.insertReturningMeals(payload, into: context)
        if let snapshot = LarryReactionSnapshot.capturing(loggedMeals: inserted, in: context) {
            appState.presentLarryReaction(snapshot, afterSheetDismiss: false)
        }

        guard payload.lineItems.count <= 1, inserted.count <= 1 else { return }

        let source = latestFoodLogDescription() ?? payload.name
        Task {
            let resolved = await FoodAnalysisService.resolveMealForLogging(from: source)
            // #region agent log
            AgentDebugLog.emit(
                hypothesisId: "C",
                location: "CoachChatView.applySuggestedMeal",
                message: resolved.isLabelBacked ? "replacing meal with lookup" : "lookup not label-backed, kept first estimate",
                data: [
                    "source": source,
                    "initialCalories": payload.calories,
                    "initialProtein": payload.proteinG,
                    "initialSource": payload.source.rawValue,
                    "resolvedCalories": resolved.calories,
                    "resolvedProtein": resolved.proteinG,
                    "resolvedSource": resolved.source.rawValue,
                    "labelBacked": resolved.isLabelBacked,
                ]
            )
            // #endregion
            let lookupBeatsPlaceholder = resolved.source.priority < payload.source.priority
            guard resolved.isLabelBacked || lookupBeatsPlaceholder else { return }
            await MainActor.run {
                MealLogging.replace(meals: inserted, with: resolved, in: context)
            }
        }
    }

    @discardableResult
    private func applyQuantityCorrectionFromLatestUserMessage() -> Bool {
        guard let utterance = messages.last(where: { $0.isUser })?.text,
              let match = FoodLogCorrection.match(utterance: utterance, todayMeals: todayMeals) else {
            return false
        }
        let replacement = FoodAnalysisService.estimateOffline(from: match.replacementDescription)
        MealLogging.update(match.meal, with: replacement, in: context)
        return true
    }

    private func latestFoodLogDescription() -> String? {
        for bubble in messages.reversed() where bubble.isUser {
            let trimmed = bubble.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower.contains("log it") || lower.contains("log that") || lower.contains("make sure you log") {
                continue
            }
            if let mention = FoodItemNaming.foodMentionForLogging(from: trimmed) {
                return mention
            }
        }
        return nil
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
        let macros = DaySummaryService.foodTarget(from: settingsList.first) ?? payload
        let start = DaySummaryService.startOfDay()
        if let existing = goals.first(where: { Calendar.current.isDate($0.date, inSameDayAs: start) }) {
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
        markCoachSeenToday()
        try? context.save()
        presentLarry(TrainerChatResponse(
            reply: "Targets locked in, baby. About \(Int(macros.calories)) calories and \(Int(macros.proteinG)) grams of protein today. Discipline tastes better than regret!",
            replies: nil,
            suggested_goal: macros,
            suggested_meal: nil
        ))
        persistChat()
    }

    private func markCoachSeenToday() {
        if let settings = settingsList.first {
            settings.lastMorningRitualDate = Date()
            try? context.save()
        }
    }
}

/// Lightweight listening bars — no audio metering dependency.
private struct ListeningWaveform: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(BrandTheme.teal.opacity(0.85 - Double(abs(3 - index)) * 0.08))
                        .frame(width: 3.5, height: barHeight(index: index, t: t))
                }
            }
        }
        .opacity(active ? 1 : 0.7)
    }

    private func barHeight(index: Int, t: TimeInterval) -> CGFloat {
        let phase = t * 5.2 + Double(index) * 0.72
        let wave = (sin(phase) + 1) * 0.5
        return 8 + CGFloat(wave) * (index == 3 ? 18 : 12)
    }
}
