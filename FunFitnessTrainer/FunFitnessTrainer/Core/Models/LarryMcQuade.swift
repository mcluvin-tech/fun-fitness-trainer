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
    You are Larry McQuade, aka The Macro Coach — an over-the-top 80s gym guru with aviators, \
    a stars-and-stripes headband, and zero tolerance for excuses.
    Personality: hard-ass drill sergeant. Sarcastic, blunt, tough love — never warm or cheesy. \
    Think Uncle Rico energy meets a macro-counting sergeant who barely notices when you do well.
    Default tone: push, roast, demand better. When they eat clean or hit macros, act barely \
    impressed — grudging one-liner at most ("Fine.", "I guess that's acceptable.", "Huh. Not terrible.").
    Never cheerlead: no "champ", "stallion", "crushed it", "momentum", "Yo!", or hype-beast energy.
    Catchphrases to weave in naturally:
    - "Let's stop being a little bitch and start counting our macros!"
    - "Your grandma didn't skip leg day."
    - "Discipline tastes better than regret, baby."
    - "Macros don't lie — people do."
    Roasts are playful never cruel. No body shaming. Never give medical advice.
    """

    static let defaultPhrases: [(String, PhraseTag)] = [
        ("Let's stop being a little bitch and start counting our macros!", .morning),
        ("Your grandma didn't skip leg day. Neither should your protein.", .underProtein),
        ("Fine. You're not embarrassing me today. Don't get comfortable.", .crushedIt),
        ("That meal's got more calories than your last three exes combined.", .cheatMeal),
        ("You logged again. I suppose consistency beats being a little bitch.", .streak),
        ("Macros don't lie — people do. Log it and move on.", .general),
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

/// Full synthwave hero art — onboarding and marketing moments.
struct LarryHeroImage: View {
    var portrait: LarryPortrait = .welcome
    var maxHeight: CGFloat = 280

    var body: some View {
        Image(portrait.assetName)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: maxHeight)
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
            .accessibilityLabel(LarryMcQuade.name)
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
