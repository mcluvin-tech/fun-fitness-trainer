import Foundation

/// Community feed for The Pack — interesting weekly stats from pack mates.
enum PackFeedService {
    /// Local + demo feed (offline or unsigned).
    static func loadFeed(yourMealsThisWeek: [Meal]) -> [PackFeedEntry] {
        var rawEntries: [PackFeedEntry] = []

        for meal in yourMealsThisWeek {
            rawEntries.append(
                PackFeedEntry(
                    memberName: "You",
                    mealName: FoodItemNaming.displayTitle(for: meal.name),
                    calories: Int(meal.calories),
                    proteinG: Int(meal.proteinG),
                    loggedAt: meal.loggedAt,
                    isYou: true
                )
            )
        }

        return PackInterestingPostBuilder.presentableFeed(
            from: rawEntries,
            pinnedStats: demoPackStats()
        )
    }

    /// Signed-in pack feed from Supabase; falls back to demo if empty or error.
    static func loadFeedRemoteFirst(yourMealsThisWeek: [Meal]) async -> [PackFeedEntry] {
        let signedIn = await MainActor.run { SupabaseService.shared.isSignedIn }
        guard signedIn, AppConfig.hasBackend else {
            return loadFeed(yourMealsThisWeek: yourMealsThisWeek)
        }

        do {
            let remote = try await PackService.shared.fetchPackFeed()
            if !remote.isEmpty {
                return PackInterestingPostBuilder.presentableFeed(from: remote)
            }
        } catch {
            /* fall through to local + demo */
        }

        return loadFeed(yourMealsThisWeek: yourMealsThisWeek)
    }

    private static func demoPackStats() -> [PackFeedEntry] {
        let now = Date()
        return [
            PackFeedEntry(
                memberName: "Maria",
                mealName: "Maria had eight eggs this week",
                calories: 560,
                proteinG: 48,
                loggedAt: now.addingTimeInterval(-42 * 60),
                isInterestingStat: true
            ),
            PackFeedEntry(
                memberName: "Chris",
                mealName: "Chris logged four cups of ground beef this week",
                calories: 1356,
                proteinG: 136,
                loggedAt: now.addingTimeInterval(-75 * 60),
                isInterestingStat: true
            ),
            PackFeedEntry(
                memberName: "Jake",
                mealName: "Jake had three Big Macs this week",
                calories: 1770,
                proteinG: 75,
                loggedAt: now.addingTimeInterval(-18 * 60),
                isInterestingStat: true
            ),
        ]
    }
}
