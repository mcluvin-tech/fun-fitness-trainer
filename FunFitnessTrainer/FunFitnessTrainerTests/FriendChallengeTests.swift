import XCTest
@testable import FunFitnessTrainer

final class FriendChallengeTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"

    func testParsesCustomSchemeChallengeLink() {
        let url = URL(string: "funfitnesstrainer://challenge/\(token)")!
        XCTAssertEqual(ChallengeLink.token(from: url), token)
    }

    func testParsesHTTPSChallengeLinkOnAnyHost() {
        let url = URL(string: "https://links.example.com/challenge/\(token)")!
        XCTAssertEqual(ChallengeLink.token(from: url), token)
    }

    func testIgnoresOAuthCallback() {
        let url = URL(string: "funfitnesstrainer://auth-callback#access_token=abc")!
        XCTAssertNil(ChallengeLink.token(from: url))
    }

    func testRejectsShortToken() {
        let url = URL(string: "funfitnesstrainer://challenge/short")!
        XCTAssertNil(ChallengeLink.token(from: url))
    }

    func testShareMessageIncludesLinkAndDoesNotMentionWeight() {
        let link = ChallengeLink.inviteURL(token: token)
        let message = ChallengeLink.shareMessage(link: link)
        XCTAssertTrue(message.contains(link.absoluteString))
        XCTAssertTrue(message.contains("Larry McQuade has officially called you out."))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("weight"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("calorie"))
        // HTTPS universal links are self-contained; custom-scheme shares append
        // App Store download text only when APP_STORE_URL / APP_STORE_ID is configured.
        if link.scheme?.lowercased() == "https" {
            XCTAssertFalse(message.contains("Don't have the app yet?"))
        }
    }

    func testPendingInviteExpiresSevenDaysAfterCreation() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let expires = FriendChallengeRules.inviteExpiresAt(createdAt: created)
        XCTAssertEqual(expires.timeIntervalSince(created), 7 * 24 * 60 * 60)
        XCTAssertFalse(FriendChallengeRules.isInviteExpired(status: .pending, expiresAt: expires, now: expires.addingTimeInterval(-1)))
        XCTAssertTrue(FriendChallengeRules.isInviteExpired(status: .pending, expiresAt: expires, now: expires))
    }

    func testCompetitionLastsSevenDaysAfterAcceptance() {
        let accepted = Date(timeIntervalSince1970: 1_700_000_000)
        let window = FriendChallengeRules.competitionWindow(acceptedAt: accepted)
        XCTAssertEqual(window.start, accepted)
        XCTAssertEqual(window.end.timeIntervalSince(accepted), 7 * 24 * 60 * 60)
    }

    func testWaitingLineHidesUnknownNames() {
        XCTAssertEqual(FriendChallengeRules.waitingLine(opponentName: nil), "Waiting for your opponent to accept")
        XCTAssertEqual(FriendChallengeRules.waitingLine(opponentName: "Athlete"), "Waiting for your opponent to accept")
        XCTAssertEqual(FriendChallengeRules.waitingLine(opponentName: "  "), "Waiting for your opponent to accept")
        XCTAssertEqual(FriendChallengeRules.waitingLine(opponentName: "Jake"), "Waiting for Jake to accept")
    }

    func testFavoriteChallengeQuoteUsesTheRivalName() {
        XCTAssertEqual(
            LarryChallengeQuotes.favorite(rivalName: "Jake"),
            "Jake's been hitting his protein. You gonna let that string bean outwork you?"
        )
        let unnamed = LarryChallengeQuotes.favorite(rivalName: "Athlete")
        XCTAssertEqual(unnamed, "You gonna let that string bean outwork you?")
        XCTAssertFalse(unnamed.contains("Jake"))
        XCTAssertFalse(unnamed.contains("Athlete"))
    }

    func testAcceptedChallengeQuotesStayCartoonishAndSkipAFakeScore() {
        let lines = LarryChallengeQuotes.acceptedLines(rivalName: "Jake")
        XCTAssertTrue(lines.contains("You gonna let that string bean beat you?"))
        XCTAssertTrue(lines.contains("Jake's ahead. By Jake. Come on, brother."))
        XCTAssertTrue(lines.contains("You're losing to a man built like a coat hanger."))
        XCTAssertTrue(lines.contains("That human breadstick just took the lead."))
        XCTAssertTrue(lines.contains("You're really gonna let Captain Chicken Legs win this thing?"))
        XCTAssertTrue(lines.contains("Brother. The scarecrow is beating you."))
        XCTAssertTrue(lines.contains("You have been overtaken by a guy with the wingspan of a pool noodle."))
        XCTAssertTrue(lines.contains("That lanky son of a gun is actually doing it."))
        XCTAssertTrue(lines.contains("Your buddy's outworking you and he looks like he orders dressing on the side."))
        XCTAssertFalse(lines.contains(LarryChallengeQuotes.pointsLeadLine))
        XCTAssertEqual(
            LarryChallengeQuotes.line(moment: .accepted, rivalName: "Jake", seed: 3),
            LarryChallengeQuotes.line(moment: .accepted, rivalName: "Jake", seed: 3)
        )
    }

    func testCalloutUsesInviterName() {
        XCTAssertEqual(
            FriendChallengeRules.calloutLine(inviterName: "Luke"),
            "Luke challenged you to a 7-day Larry showdown."
        )
        XCTAssertEqual(
            FriendChallengeRules.calloutLine(inviterName: "Athlete"),
            "A friend challenged you to a 7-day Larry showdown."
        )
    }

    func testIncomingStateEdgeCases() {
        let future = Date().addingTimeInterval(3600)
        let past = Date().addingTimeInterval(-3600)

        XCTAssertEqual(
            FriendChallengeRules.incomingState(found: false, status: nil, isOwnInvite: false, isInvitee: false, expiresAt: nil),
            .invalid
        )
        XCTAssertEqual(
            FriendChallengeRules.incomingState(found: true, status: .pending, isOwnInvite: true, isInvitee: false, expiresAt: future),
            .ownInvite
        )
        XCTAssertEqual(
            FriendChallengeRules.incomingState(found: true, status: .pending, isOwnInvite: false, isInvitee: false, expiresAt: past),
            .expired
        )
        XCTAssertEqual(
            FriendChallengeRules.incomingState(found: true, status: .accepted, isOwnInvite: false, isInvitee: true, expiresAt: future),
            .alreadyAcceptedByYou
        )
        XCTAssertEqual(
            FriendChallengeRules.incomingState(found: true, status: .accepted, isOwnInvite: false, isInvitee: false, expiresAt: future),
            .alreadyAcceptedBySomeoneElse
        )
        XCTAssertEqual(
            FriendChallengeRules.incomingState(found: true, status: .pending, isOwnInvite: false, isInvitee: false, expiresAt: future),
            .canAccept
        )
    }

    func testPreferredCardKeepsOnePendingInvite() {
        let now = Date()
        let pending = sample(status: .pending, isInviter: true, expiresAt: now.addingTimeInterval(3600), endsAt: nil)
        let accepted = sample(status: .accepted, isInviter: true, expiresAt: now, endsAt: now.addingTimeInterval(3600))
        let chosen = FriendChallengeRules.preferredCardChallenge([accepted, pending], now: now)
        XCTAssertEqual(chosen?.id, pending.id)
    }

    func testDecodesChallengePayload() throws {
        let json = """
        {
          "found": true,
          "id": "11111111-1111-1111-1111-111111111111",
          "invite_token": "\(token)",
          "status": "pending",
          "created": true,
          "inviter_display_name": "Luke",
          "is_own_invite": false,
          "created_at": "2026-10-09T22:00:00+00:00",
          "expires_at": "2026-10-16T22:00:00.123456+00:00",
          "expired_ids": ["22222222-2222-2222-2222-222222222222"]
        }
        """.data(using: .utf8)!
        let object = try JSONDecoder().decode(ChallengeRPCObject.self, from: json)
        let challenge = try XCTUnwrap(object.asChallenge())
        XCTAssertEqual(challenge.inviteToken, token)
        XCTAssertEqual(challenge.status, .pending)
        XCTAssertTrue(challenge.wasNewlyCreated)
        XCTAssertEqual(challenge.inviterDisplayName, "Luke")
        XCTAssertEqual(object.expiredIds?.count, 1)
        XCTAssertNotNil(challenge.expiresAt)
    }

    func testAnalyticsEventNames() {
        XCTAssertEqual(ProductAnalytics.Event.challengeInviteViewed.rawValue, "challenge_invite_viewed")
        XCTAssertEqual(ProductAnalytics.Event.challengeInviteCreated.rawValue, "challenge_invite_created")
        XCTAssertEqual(ProductAnalytics.Event.challengeShareOpened.rawValue, "challenge_share_opened")
        XCTAssertEqual(ProductAnalytics.Event.challengeLinkOpened.rawValue, "challenge_link_opened")
        XCTAssertEqual(ProductAnalytics.Event.challengeAccepted.rawValue, "challenge_accepted")
        XCTAssertEqual(ProductAnalytics.Event.challengeInviteExpired.rawValue, "challenge_invite_expired")
    }

    func testAnalyticsDropsPrivateFields() {
        var captured: [String: String] = [:]
        ProductAnalytics.sink = { _, metadata in captured = metadata }
        defer { ProductAnalytics.sink = nil }

        ProductAnalytics.track(.challengeAccepted, metadata: [
            "challenge_id": "abc",
            "status": "accepted",
            "invite_token": "secret",
            "calories": "900",
            "weight": "180",
        ])

        XCTAssertEqual(captured["challenge_id"], "abc")
        XCTAssertEqual(captured["status"], "accepted")
        XCTAssertNil(captured["invite_token"])
        XCTAssertNil(captured["calories"])
        XCTAssertNil(captured["weight"])
    }

    private func sample(
        status: FriendChallengeStatus,
        isInviter: Bool,
        expiresAt: Date,
        endsAt: Date?
    ) -> FriendChallenge {
        FriendChallenge(
            id: UUID(),
            inviteToken: isInviter ? token : nil,
            status: status,
            inviterDisplayName: "Luke",
            opponentDisplayName: nil,
            isOwnInvite: isInviter,
            isInvitee: !isInviter,
            isInviter: isInviter,
            createdAt: Date(),
            acceptedAt: status == .accepted ? Date() : nil,
            startsAt: status == .accepted ? Date() : nil,
            endsAt: endsAt,
            expiresAt: expiresAt,
            wasNewlyCreated: false,
            newlyAccepted: false,
            justExpired: false
        )
    }
}

final class MealReminderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testSchedulesBreakfastLunchAndDinner() {
        let now = date(2026, 10, 12, 8, 0)
        let reminders = MealReminderPlanner.reminders(now: now, loggedAt: [], rivalName: nil, calendar: calendar)
        let today = reminders.filter { calendar.isDate($0.fireDate, inSameDayAs: now) }
        XCTAssertEqual(today.map(\.slot), [.breakfast, .lunch, .dinner])
        XCTAssertEqual(today.map { calendar.component(.hour, from: $0.fireDate) }, [9, 12, 18])
    }

    func testSkipsAMealThatIsAlreadyLogged() {
        let now = date(2026, 10, 12, 8, 0)
        let lunch = date(2026, 10, 12, 12, 0)
        let reminders = MealReminderPlanner.reminders(now: now, loggedAt: [lunch], rivalName: nil, calendar: calendar)
        let today = reminders.filter { calendar.isDate($0.fireDate, inSameDayAs: now) }
        XCTAssertEqual(today.map(\.slot), [.breakfast, .dinner])
    }

    func testRivalJokeShowsUpSometimesAndNeverInventsAScore() {
        let now = date(2026, 10, 12, 8, 0)
        let reminders = MealReminderPlanner.reminders(now: now, loggedAt: [], rivalName: "Jake", calendar: calendar)
        let bodies = reminders.map(\.body)
        XCTAssertTrue(bodies.contains { $0.contains("string bean") || $0.contains("Jake") })
        XCTAssertTrue(bodies.contains { !$0.contains("Jake") && !$0.contains("string bean") })
        XCTAssertFalse(bodies.contains { $0.contains("20 points") })
    }

    func testNoRivalMeansNoFriendJoke() {
        let now = date(2026, 10, 12, 8, 0)
        let reminders = MealReminderPlanner.reminders(now: now, loggedAt: [], rivalName: "Athlete", calendar: calendar)
        XCTAssertFalse(reminders.contains { $0.body.contains("Jake") || $0.body.contains("string bean") })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
