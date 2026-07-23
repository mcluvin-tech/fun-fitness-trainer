import SwiftUI

/// Synthwave / retrowave palette from the Larry McQuade hero art.
enum BrandTheme {
    static let accent = Color("AccentOrange", bundle: .main)
    static let purple = Color("BrandPurple", bundle: .main)
    static let teal = Color("BrandTeal", bundle: .main)
    static let magenta = Color("BrandMagenta", bundle: .main)
    static let neonBlue = Color("BrandBlue", bundle: .main)

    // MARK: - Home (dark synthwave)

    static let homePrimaryText = Color.white.opacity(0.95)
    static let homeSecondaryText = Color.white.opacity(0.62)
    static let homeCard = Color(red: 0.11, green: 0.09, blue: 0.20)
    /// Translucent dock — purple tint, not flat black.
    static let homeActionBar = Color(red: 0.10, green: 0.06, blue: 0.18).opacity(0.72)

    static var homeDockGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.07, blue: 0.22).opacity(0.85),
                Color(red: 0.08, green: 0.05, blue: 0.16).opacity(0.95),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var homeBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.04, blue: 0.16),
                Color(red: 0.04, green: 0.05, blue: 0.12),
                Color(red: 0.09, green: 0.03, blue: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var homeAmbientGlow: LinearGradient {
        LinearGradient(
            colors: [purple.opacity(0.22), magenta.opacity(0.10), teal.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var homeTitleGradient: LinearGradient {
        LinearGradient(
            colors: [magenta, purple, teal],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var synthwaveGradient: LinearGradient {
        LinearGradient(
            colors: [purple.opacity(0.35), magenta.opacity(0.2), teal.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [purple.opacity(0.18), teal.opacity(0.12)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct HomeDarkBackground: View {
    var body: some View {
        ZStack {
            BrandTheme.homeBackgroundGradient
            BrandTheme.homeAmbientGlow
            RadialGradient(
                colors: [BrandTheme.purple.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )
            RadialGradient(
                colors: [BrandTheme.magenta.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

/// Frosted purple dock for home bottom actions.
struct HomeDockBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            BrandTheme.homeDockGradient
            BrandTheme.homeAmbientGlow.opacity(0.45)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

extension Color {
    /// Primary CTA / highlights (hot pink from hero art).
    static var brandAccent: Color { BrandTheme.accent }
}
