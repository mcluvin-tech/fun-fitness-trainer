import SwiftUI
import UIKit

/// Synthwave palette — Apple-level restraint with a playful fitness personality.
enum BrandTheme {
    static let accent = Color("AccentOrange", bundle: .main)
    static let purple = Color("BrandPurple", bundle: .main)
    static let teal = Color("BrandTeal", bundle: .main)
    static let magenta = Color("BrandMagenta", bundle: .main)
    static let neonBlue = Color("BrandBlue", bundle: .main)

    // MARK: - Typography (four levels)

    /// Big daily metric (e.g. 944)
    static let typeHero = Font.system(size: 42, weight: .bold, design: .rounded)
    /// Section title ("Daily Progress", "Today's log")
    static let typeSection = Font.system(.headline, design: .rounded).weight(.semibold)
    /// Primary item text (meal names)
    static let typeItem = Font.system(.body, design: .rounded).weight(.semibold)
    /// Subdued metadata
    static let typeMeta = Font.system(.caption, design: .rounded)

    // MARK: - Home surfaces (deep plum → elevated glass)

    static let homePrimaryText = Color.white.opacity(0.96)
    static let homeSecondaryText = Color.white.opacity(0.58)
    static let homeTertiaryText = Color.white.opacity(0.38)
    /// Elevated translucent card fill
    static let homeCard = Color(red: 0.14, green: 0.11, blue: 0.22).opacity(0.72)
    static let homeCardSolid = Color(red: 0.13, green: 0.10, blue: 0.20)
    /// Translucent dock — purple tint, not flat black.
    static let homeActionBar = Color(red: 0.08, green: 0.05, blue: 0.14).opacity(0.78)

    static var homeCardBorder: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.14),
                purple.opacity(0.28),
                Color.white.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var homeDockGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.06, blue: 0.18).opacity(0.88),
                Color(red: 0.05, green: 0.03, blue: 0.10).opacity(0.96),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var homeBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.02, blue: 0.08),
                Color(red: 0.06, green: 0.03, blue: 0.12),
                Color(red: 0.03, green: 0.02, blue: 0.07),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var homeAmbientGlow: LinearGradient {
        LinearGradient(
            colors: [purple.opacity(0.16), magenta.opacity(0.06), teal.opacity(0.04)],
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
            colors: [purple.opacity(0.28), magenta.opacity(0.14), teal.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [purple.opacity(0.14), teal.opacity(0.08)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Frosted elevated surface — layered, not flat purple-on-purple.
struct ElevatedSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(BrandTheme.homeCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(BrandTheme.homeCardBorder, lineWidth: 1)
                    )
                    .shadow(color: (glow ?? BrandTheme.purple).opacity(0.18), radius: 18, y: 8)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            }
    }
}

extension View {
    func elevatedSurface(cornerRadius: CGFloat = 18, glow: Color? = nil) -> some View {
        modifier(ElevatedSurface(cornerRadius: cornerRadius, glow: glow))
    }
}

struct HomeDarkBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.06)
            BrandTheme.homeBackgroundGradient
            BrandTheme.homeAmbientGlow
            RadialGradient(
                colors: [BrandTheme.purple.opacity(0.20), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 380
            )
            RadialGradient(
                colors: [BrandTheme.magenta.opacity(0.08), .clear],
                center: UnitPoint(x: 0.85, y: 0.75),
                startRadius: 10,
                endRadius: 320
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
            BrandTheme.homeAmbientGlow.opacity(0.35)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

extension Color {
    /// Primary CTA / highlights (hot pink from hero art).
    static var brandAccent: Color { BrandTheme.accent }
}

enum HomeHaptics {
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func ringComplete() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
    }
}
