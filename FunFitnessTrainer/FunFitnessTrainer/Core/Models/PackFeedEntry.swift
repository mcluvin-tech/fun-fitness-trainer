import Foundation

/// A meal shared with the community feed ("The Pack").
struct PackFeedEntry: Identifiable, Equatable {
    let id: UUID
    let memberName: String
    /// Raw meal label, or a full headline for `isInterestingStat` entries.
    let mealName: String
    let calories: Int
    let proteinG: Int
    let loggedAt: Date
    let isYou: Bool
    /// Weekly stat headline, e.g. "Luke had eight eggs this week."
    let isInterestingStat: Bool

    init(
        id: UUID = UUID(),
        memberName: String,
        mealName: String,
        calories: Int,
        proteinG: Int,
        loggedAt: Date = Date(),
        isYou: Bool = false,
        isInterestingStat: Bool = false
    ) {
        self.id = id
        self.memberName = memberName
        self.mealName = mealName
        self.calories = calories
        self.proteinG = proteinG
        self.loggedAt = loggedAt
        self.isYou = isYou
        self.isInterestingStat = isInterestingStat
    }
}
