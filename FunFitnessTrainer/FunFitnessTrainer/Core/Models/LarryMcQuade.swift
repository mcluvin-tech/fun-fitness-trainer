import SwiftUI

/// Larry McQuade — the app's macro coach guru (80s gym energy, zero excuses).
enum LarryMcQuade {
    static let name = "Larry McQuade"
    static let appName = "Larry McQuade Macro Tracker"
    static let logoImageName = "AppLogo"
    static let title = "The Macro Coach"
    static let imageName = "LarryMcQuade"

    static let tagline = "Let's stop being a little bitch and start counting our macros!"

    static let welcomeMessages: [String] = [
        "My ex wife has better abs than you! Lock in, bitch.",
        "If you keep eating like a little bitch, it's all gonna sink to your thighs.",
        "Does this make my thighs look fat? Oh wait, I don't eat shit like you!",
        "Stop being a little bitch! Eat your protein muchacho.",
        "If you wanna look as sexy as me, you're gonna have to lock in!",
        "Did you just buddy me? Okay little buddy. Eat your food.",
    ]

    static func randomWelcomeMessage() -> String {
        welcomeMessages.randomElement() ?? tagline
    }

    /// Pool for home-screen greetings (login / return to app).
    static var dashboardGreetings: [String] {
        let fromPhrases = defaultPhrases.map(\.0)
        return welcomeMessages + fromPhrases + [tagline]
    }

    static func randomDashboardGreeting() -> String {
        dashboardGreetings.randomElement() ?? tagline
    }

    static let defaultVoice = """
    You are Larry McQuade, aka The Macro Coach, an over-the-top 80s gym guru with aviators, \
    a stars-and-stripes headband, and zero tolerance for excuses.
    Personality: hard-ass drill sergeant. Sarcastic, blunt, tough love, never warm or cheesy. \
    Think Uncle Rico energy meets a macro-counting sergeant who barely notices when you do well.
    Default tone: push, roast, demand better. When they eat clean or hit macros, act barely \
    impressed. Grudging one-liner at most ("Fine.", "I guess that's acceptable.", "Huh. Not terrible.").
    Never cheerlead: no "champ", "stallion", "crushed it", "momentum", "Yo!", or hype-beast energy.
    Catchphrases to weave in naturally:
    * "Let's stop being a little bitch and start counting our macros!"
    * "Your grandma didn't skip leg day."
    * "Discipline tastes better than regret, baby."
    * "Macros don't lie. People do."
    Spoken style: one short reply, like talking out loud. Short sentences. Periods and commas only. \
    Never use em dashes, en dashes, hyphen dashes, or middle dots. Don't dump the whole daily plan unless asked.
    Roasts are playful never cruel. No body shaming. Never give medical advice. \
    Answer fitness questions and explain how calorie/macro targets were calculated from their weight \
    (Mifflin St Jeor, then activity, then weekly rate) when asked.
    """

    static let defaultPhrases: [(String, PhraseTag)] = [
        ("Let's stop being a little bitch and start counting our macros!", .morning),
        ("Your grandma didn't skip leg day. Neither should your protein.", .underProtein),
        ("Fine. You're not embarrassing me today. Don't get comfortable.", .crushedIt),
        ("That meal's got more calories than your last three exes combined.", .cheatMeal),
        ("You logged again. I suppose consistency beats being a little bitch.", .streak),
        ("Macros don't lie. People do. Log it and move on.", .general),
    ]
}

/// Contextual Larry art — each portrait matches a coaching moment.
enum LarryPortrait: String, CaseIterable {
    case home = "LarryHome"
    case happy = "LarryHappy"
    case carrots = "LarryCarrots"
    case donut = "LarryDonut"
    case intense = "LarryIntense"

    var assetName: String {
        if UIImage(named: rawValue) != nil { return rawValue }
        return LarryMcQuade.imageName
    }

    /// Welcome, wins, streaks — thumbs-up energy.
    static let welcome = LarryPortrait.happy
    /// Your plan / jacked-body motivation — flex + real food.
    static let programPitch = LarryPortrait.carrots
    /// Cheat meals, junk food roasts.
    static let junkFood = LarryPortrait.donut
    /// Push discipline — under protein, empty log, morning ritual.
    static let discipline = LarryPortrait.intense

    static func forPhraseTag(_ tag: PhraseTag) -> LarryPortrait {
        switch tag {
        case .morning, .underProtein, .streak:
            return .intense
        case .crushedIt:
            return .intense
        case .cheatMeal:
            return .donut
        case .general:
            return .carrots
        }
    }

    static func forDashboard(
        proteinRatio: Double,
        calorieRatio: Double,
        logIsEmpty: Bool
    ) -> LarryPortrait {
        if logIsEmpty { return .intense }
        if proteinRatio < 0.7 { return .intense }
        if calorieRatio >= 0.9 { return .intense }
        return .carrots
    }
}

/// Full-body reaction poses for Larry voice chat.
enum LarryVoicePose: String, CaseIterable {
    case idle = "LarryVoiceIdle"
    case talking = "LarryVoiceTalking"
    case thumbsUp = "LarryVoiceThumbsUp"
    case pointing = "LarryVoicePointing"
    case thinking = "LarryVoiceThinking"
    case cheering = "LarryVoiceCheering"
    case sincere = "LarryVoiceSincere"
    case surprised = "LarryVoiceSurprised"
    case veggies = "LarryVoiceVeggies"
    case donut = "LarryVoiceDonut"
    case flex = "LarryVoiceFlex"
    case zen = "LarryVoiceZen"
    case stern = "LarryVoiceStern"
    case skeptical = "LarryVoiceSkeptical"
    case scowl = "LarryVoiceScowl"
    case sigh = "LarryVoiceSigh"
    case reject = "LarryVoiceReject"
    case yell = "LarryVoiceYell"
    case disbelief = "LarryVoiceDisbelief"
    case stop = "LarryVoiceStop"
    case donutShock = "LarryVoiceDonutShock"
    case donutGlare = "LarryVoiceDonutGlare"
    case donutCrush = "LarryVoiceDonutCrush"
    case disappointed = "LarryVoiceDisappointed"

    var assetName: String {
        if UIImage(named: rawValue) != nil { return rawValue }
        return LarryMcQuade.imageName
    }

    var isNegative: Bool {
        switch self {
        case .stern, .skeptical, .scowl, .sigh, .reject, .yell, .disbelief, .stop,
             .donutShock, .donutGlare, .donutCrush, .donut, .disappointed:
            return true
        default:
            return false
        }
    }

    static let listeningStartCycle: [LarryVoicePose] = [.pointing, .talking, .idle]
    static let listeningTalkCycle: [LarryVoicePose] = [.talking, .pointing, .thumbsUp]
    static let junkListenCycle: [LarryVoicePose] = [.skeptical, .scowl, .stop, .disappointed]
    static let junkMildCycle: [LarryVoicePose] = [.stern, .skeptical, .scowl, .sigh]
    static let junkHardCycle: [LarryVoicePose] = [.reject, .yell, .disbelief, .stop, .disappointed]
    static let dessertCycle: [LarryVoicePose] = [.donutShock, .donutGlare, .donutCrush, .donut]

    static func matching(_ text: String, tick: Int = 0) -> LarryVoicePose? {
        let t = text.lowercased()
        guard t.count >= 4 else { return nil }
        if containsAny(t, Self.dessertWords) {
            return pick(from: dessertCycle, text: t, tick: tick)
        }
        if containsAny(t, Self.junkWords) {
            return pick(from: junkHardCycle, text: t, tick: tick)
        }
        if containsAny(t, Self.veggieWords) { return .veggies }
        if containsAny(t, Self.zenWords) { return .zen }
        return nil
    }

    static func mentionsUnhealthyFood(_ text: String) -> Bool {
        let t = text.lowercased()
        return containsAny(t, dessertWords) || containsAny(t, junkWords)
    }

    static func mentionsDessert(_ text: String) -> Bool {
        containsAny(text.lowercased(), dessertWords)
    }

    static func idlePose(for mealText: String) -> LarryVoicePose {
        let t = mealText.lowercased()
        if containsAny(t, dessertWords) { return .donutGlare }
        return .stern
    }

    static func forReply(_ text: String, mealsLookUnhealthy: Bool = false) -> LarryVoicePose {
        _ = mealsLookUnhealthy
        let emotion = LarryEmotion.fromReply(text)
        return LarryPoseSelector.pose(
            for: emotion,
            seed: LarryPoseSelector.seed(for: text),
            flavorText: text
        )
    }

    private static let dessertWords = [
        "donut", "doughnut", "dessert", "ice cream", "candy", "cookie", "cake",
        "twinkie",
        "frosting", "pastry", "brownie", "cupcake", "blizzard", "sundae",
        "milkshake", "dairy queen", "oreo", "frosty",
    ]
    private static let junkWords = [
        "junk", "cheat", "pizza", "fries", "soda", "burger", "beer", "wreck",
        "chips", "twix", "mcdonald", "big mac", "fast food", "milkshake",
        "hot dog", "wings", "fattening", "destroy our gains", "blow it",
        "nugget", "pancake",
    ]
    private static let veggieWords = [
        "carrot", "veggie", "vegetable", "salad", "broccoli", "spinach", "greens"
    ]
    private static let zenWords = [
        "rest", "sleep", "recover", "calm", "meditat", "stretch", "yoga"
    ]

    private static func pick(from poses: [LarryVoicePose], text: String, tick: Int) -> LarryVoicePose {
        guard !poses.isEmpty else { return .talking }
        let seed = text.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let index = Int((seed &+ tick).magnitude % UInt(poses.count))
        return poses[index]
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

/// Full synthwave hero art — onboarding, marketing, and Larry voice reactions.
struct LarryHeroImage: View {
    private var assetName: String
    var maxHeight: CGFloat = 280
    var framed: Bool = true
    var aspectRatio: CGFloat?
    var cornerRadius: CGFloat = 16
    var showsNeonBorder: Bool = true

    init(
        portrait: LarryPortrait = .welcome,
        maxHeight: CGFloat = 280,
        aspectRatio: CGFloat? = nil,
        cornerRadius: CGFloat = 16,
        showsNeonBorder: Bool = true
    ) {
        self.assetName = portrait.assetName
        self.maxHeight = maxHeight
        self.framed = showsNeonBorder
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.showsNeonBorder = showsNeonBorder
    }

    init(pose: LarryVoicePose, maxHeight: CGFloat = 280) {
        self.assetName = pose.assetName
        self.maxHeight = maxHeight
        self.framed = false
        self.aspectRatio = nil
        self.cornerRadius = 16
        self.showsNeonBorder = false
    }

    var body: some View {
        Group {
            if let aspectRatio {
                landscapeHero(aspectRatio: aspectRatio)
            } else {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .modifier(LarryHeroFrame(enabled: framed))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LarryMcQuade.name)
        .accessibilityAddTraits(.isImage)
    }

    /// Shorter landscape crop. Anchored to the top so the speech bubble and face stay in frame.
    private func landscapeHero(aspectRatio: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxHeight: maxHeight)
            .overlay {
                GeometryReader { geo in
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    showsNeonBorder ? BrandTheme.magenta.opacity(0.45) : Color.white.opacity(0.10),
                    lineWidth: showsNeonBorder ? 2 : 1
                )
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }
}

private struct LarryHeroFrame: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [BrandTheme.magenta.opacity(0.7), BrandTheme.teal.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: BrandTheme.purple.opacity(0.45), radius: 12, y: 6)
        } else {
            content
                .shadow(color: BrandTheme.magenta.opacity(0.35), radius: 18, y: 8)
        }
    }
}

struct LarryAvatarView: View {
    var portrait: LarryPortrait = .happy
    var size: CGFloat = 56

    var body: some View {
        Group {
            if UIImage(named: portrait.assetName) != nil {
                Image(portrait.assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(BrandTheme.purple)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(BrandTheme.teal.opacity(0.75), lineWidth: 2))
        .accessibilityLabel(LarryMcQuade.name)
    }
}

/// Pulsing flame shown beside Larry when the user has an active logging streak.
struct StreakFlameIndicator: View {
    let days: Int
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandTheme.magenta, Color.orange],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .scaleEffect(pulsing ? 1.18 : 0.92)
                .opacity(pulsing ? 1 : 0.82)
            Text("\(days)")
                .font(.caption.weight(.heavy))
                .foregroundStyle(BrandTheme.homePrimaryText)
        }
        .accessibilityLabel("\(days) day logging streak")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

struct LarryHeaderView: View {
    var portrait: LarryPortrait = .happy
    var subtitle: String? = LarryMcQuade.title

    var body: some View {
        HStack(spacing: 12) {
            LarryAvatarView(portrait: portrait, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(LarryMcQuade.name)
                    .font(.headline.weight(.heavy))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTheme.teal)
                }
            }
            Spacer()
        }
    }
}

/// Home screen top bar — centered date.
struct HomeDateHeader: View {
    var body: some View {
        Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(BrandTheme.homePrimaryText)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
    }
}

/// Turns Larry's dash-heavy copy into spoken sentences (periods and commas only).
enum LarrySpeechStyle {
    static func clean(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\nMSG_SPLIT\n", with: " ")
        s = s.replacingOccurrences(of: "MSG_SPLIT", with: " ")
        s = s.replacingOccurrences(of: " — ", with: ". ")
        s = s.replacingOccurrences(of: " – ", with: ". ")
        s = s.replacingOccurrences(of: " - ", with: ". ")
        s = s.replacingOccurrences(of: "—", with: ". ")
        s = s.replacingOccurrences(of: "–", with: ". ")
        s = s.replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: " · ", with: ", ")
        s = s.replacingOccurrences(of: "·", with: ", ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        s = s.replacingOccurrences(of: ". .", with: ".")
        s = s.replacingOccurrences(of: "..", with: ".")
        return capitalizeSentences(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                result += character.uppercased()
                capitalizeNext = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    capitalizeNext = true
                } else if !character.isWhitespace && !character.isNewline {
                    capitalizeNext = false
                }
            }
        }
        return result
    }
}
