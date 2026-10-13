import SwiftUI
import UIKit

/// Inviter flow. Lives on the Progress tab.
struct ChallengeFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseService.shared

    @State private var invite: FriendChallenge?
    @State private var shareOutcome: ShareOutcome = .none
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var isSharing = false
    @State private var shareText = ""

    private enum ShareOutcome {
        case none
        case cancelled
        case completed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("🥊")
                            .font(.largeTitle)
                        Text("Challenge a Friend")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(BrandTheme.homePrimaryText)
                            .minimumScaleFactor(0.7)
                            .lineLimit(2)

                        statusBlock

                        Text("You'll compete on consistency, not bodyweight.")
                            .font(BrandTheme.typeMeta)
                            .foregroundStyle(BrandTheme.homeTertiaryText)

                        if supabase.isSignedIn, AppConfig.hasBackend {
                            sendButton
                        } else if !supabase.isSignedIn {
                            Text("Sign in so Larry knows who threw the challenge.")
                                .font(.subheadline)
                                .foregroundStyle(BrandTheme.homeSecondaryText)
                            AuthSignInSection()
                        } else {
                            Text(ChallengeFailure.missingBackend.localizedDescription)
                                .font(.subheadline)
                                .foregroundStyle(BrandTheme.homeSecondaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandTheme.homePrimaryText)
                }
            }
            .task {
                ProductAnalytics.track(.challengeInviteViewed, metadata: inviteMetadata)
                await loadExistingInvite()
            }
            .onChange(of: supabase.isSignedIn) { _, signedIn in
                if signedIn {
                    Task { await loadExistingInvite() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var statusBlock: some View {
        if shareOutcome == .completed {
            Text("Challenge sent.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            larryLine(LarryChallengeQuotes.favorite(rivalName: invite?.opponentDisplayName), portrait: .intense)
            if invite != nil {
                Text(FriendChallengeRules.waitingLine(opponentName: invite?.opponentDisplayName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.teal)
            }
        } else if shareOutcome == .cancelled {
            Text("Invite ready.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("It hasn't been shared yet.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
        } else if invite != nil {
            Text(FriendChallengeRules.waitingLine(opponentName: invite?.opponentDisplayName))
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            larryLine(LarryChallengeQuotes.favorite(rivalName: invite?.opponentDisplayName), portrait: .intense)
        } else {
            Text("Who's got better discipline? There's one way to find out.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("Invite a friend to a 7-day Larry challenge.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            larryLine(LarryChallengeQuotes.favorite(rivalName: nil), portrait: .intense)
        }
    }

    private var sendButton: some View {
        Button {
            Task { await sendChallenge() }
        } label: {
            HStack {
                Text(invite == nil ? "Send Challenge" : "Share again")
                    .font(.headline)
                if isWorking {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.teal)
        .disabled(isWorking || isSharing)
    }

    private var inviteMetadata: [String: String] {
        guard let invite else { return [:] }
        return [
            "challenge_id": invite.id.uuidString,
            "status": invite.status.rawValue,
        ]
    }

    private func loadExistingInvite() async {
        guard supabase.isSignedIn, AppConfig.hasBackend else { return }
        guard let mine = try? await ChallengeService.shared.fetchMyChallenges() else { return }
        invite = mine.first {
            $0.isInviter && FriendChallengeRules.isCurrent($0) && $0.status == .pending
        }
    }

    private func sendChallenge() async {
        guard !isWorking, !isSharing else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let created = try await ChallengeService.shared.createChallenge()
            invite = created.challenge
            guard let token = created.challenge.inviteToken else {
                errorMessage = ChallengeFailure.unavailable.localizedDescription
                return
            }
            shareText = ChallengeLink.shareMessage(link: ChallengeLink.inviteURL(token: token))
            ProductAnalytics.track(.challengeShareOpened, metadata: [
                "challenge_id": created.challenge.id.uuidString,
                "status": created.challenge.status.rawValue,
            ])
            presentShareSheet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Present on the challenge sheet. Embedding UIActivityViewController as another
    /// SwiftUI sheet crashes when Messages tries to open on top of it.
    private func presentShareSheet() {
        guard !shareText.isEmpty, let presenter = topPresenter() else {
            errorMessage = "Couldn't open the share sheet. Try again."
            shareOutcome = .cancelled
            return
        }

        let activity = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async {
                isSharing = false
                if completed {
                    shareOutcome = .completed
                    HomeHaptics.success()
                } else if shareOutcome != .completed {
                    shareOutcome = .cancelled
                }
            }
        }

        if presenter.traitCollection.userInterfaceIdiom == .pad,
           let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            let bounds = presenter.view.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        isSharing = true
        presenter.present(activity, animated: true)
    }

    private func topPresenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else { return nil }
        var presenter = root
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }
        guard presenter.view.window != nil, presenter.presentedViewController == nil else { return nil }
        return presenter
    }
}

/// Invitee flow. The token survives signup in AppState.
struct ChallengeAcceptView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var supabase = SupabaseService.shared

    @State private var challenge: FriendChallenge?
    @State private var phase: Phase = .loading
    @State private var isAccepting = false
    @State private var forcedState: IncomingChallengeState?

    private enum Phase: Equatable {
        case loading
        case ready
        case accepted
        case failed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeDarkBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        content
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(phase == .accepted ? "Done" : "Not Now") {
                        if phase == .accepted {
                            appState.completeChallengeHandoff()
                        } else {
                            appState.postponeIncomingChallenge()
                        }
                    }
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                }
            }
            .task { await load() }
            .onChange(of: supabase.isSignedIn) { _, signedIn in
                if signedIn { Task { await load() } }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAccepting)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading challenge…")
                .tint(BrandTheme.homeSecondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed:
            Text("Couldn't load this challenge.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text(ChallengeFailure.unavailable.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            primaryButton("Try Again", action: { Task { await load() } })
        case .accepted:
            acceptedBlock
        case .ready:
            readyBlock
        }
    }

    @ViewBuilder
    private var readyBlock: some View {
        let state = forcedState ?? FriendChallengeRules.incomingState(
            found: challenge != nil,
            status: challenge?.status,
            isOwnInvite: challenge?.isOwnInvite ?? false,
            isInvitee: challenge?.isInvitee ?? false,
            expiresAt: challenge?.expiresAt
        )

        switch state {
        case .canAccept:
            calloutHeader
            if supabase.isSignedIn {
                primaryButton(isAccepting ? "Accepting…" : "Accept Challenge") {
                    Task { await accept() }
                }
                .disabled(isAccepting)
            } else {
                Text("Sign in to accept. Your invite stays right here.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTheme.homeSecondaryText)
                AuthSignInSection()
            }
        case .alreadyAcceptedByYou:
            acceptedBlock
        case .ownInvite:
            Text("This is your challenge.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("Your opponent has to accept it.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            primaryButton("Done") { appState.clearIncomingChallenge() }
        case .expired:
            Text("This challenge expired.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("Ask them to send a new one.")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.homeSecondaryText)
            primaryButton("Done") { appState.clearIncomingChallenge() }
        case .alreadyAcceptedBySomeoneElse:
            Text("This challenge has already been accepted.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            primaryButton("Done") { appState.clearIncomingChallenge() }
        case .cancelled:
            Text("This challenge was cancelled.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            primaryButton("Done") { appState.clearIncomingChallenge() }
        case .invalid:
            Text("This challenge link isn't valid.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            primaryButton("Done") { appState.clearIncomingChallenge() }
        }
    }

    private var calloutHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🥊")
                .font(.largeTitle)
            Text("YOU'VE BEEN CALLED OUT")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.teal)
            Text(FriendChallengeRules.calloutLine(inviterName: challenge?.inviterDisplayName))
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            larryLine(LarryChallengeQuotes.line(moment: .calledOut, rivalName: challenge?.inviterDisplayName), portrait: .intense)
        }
    }

    private var acceptedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Challenge accepted.")
                .font(BrandTheme.typeSection)
                .foregroundStyle(BrandTheme.homePrimaryText)
            Text("7 days. One winner.")
                .font(.title3.weight(.bold))
                .foregroundStyle(BrandTheme.homePrimaryText)
            larryLine(
                LarryChallengeQuotes.line(
                    moment: .accepted,
                    rivalName: challenge?.inviterDisplayName,
                    seed: challenge?.id.hashValue ?? 0
                ),
                portrait: .happy
            )
            primaryButton("Back to training") {
                appState.completeChallengeHandoff()
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.teal)
    }

    private func releaseTokenIfResolved(_ state: IncomingChallengeState) {
        switch state {
        case .canAccept:
            return
        case .ownInvite, .expired, .alreadyAcceptedByYou, .alreadyAcceptedBySomeoneElse, .cancelled, .invalid:
            appState.dropIncomingToken()
        }
    }

    private func load() async {
        forcedState = nil
        guard let token = appState.pendingChallengeToken, ChallengeLink.isValidToken(token) else {
            challenge = nil
            phase = .ready
            return
        }
        phase = .loading
        do {
            challenge = try await ChallengeService.shared.fetchChallenge(inviteToken: token)
            let state = FriendChallengeRules.incomingState(
                found: challenge != nil,
                status: challenge?.status,
                isOwnInvite: challenge?.isOwnInvite ?? false,
                isInvitee: challenge?.isInvitee ?? false,
                expiresAt: challenge?.expiresAt
            )
            releaseTokenIfResolved(state)
            phase = state == .alreadyAcceptedByYou ? .accepted : .ready
        } catch ChallengeFailure.invalidInvite {
            challenge = nil
            releaseTokenIfResolved(.invalid)
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    private func accept() async {
        guard !isAccepting, let token = appState.pendingChallengeToken else { return }
        isAccepting = true
        defer { isAccepting = false }
        do {
            let accepted = try await ChallengeService.shared.acceptChallenge(inviteToken: token)
            challenge = accepted
            appState.dropIncomingToken()
            phase = .accepted
            HomeHaptics.success()
        } catch let error as ChallengeFailure {
            switch error {
            case .ownInvite:
                forcedState = .ownInvite
            case .expiredInvite:
                forcedState = .expired
            case .alreadyAccepted:
                forcedState = .alreadyAcceptedBySomeoneElse
            case .cancelledInvite:
                forcedState = .cancelled
            case .invalidInvite:
                forcedState = .invalid
            case .notSignedIn, .missingBackend, .unavailable:
                phase = .failed
            }
            if let forcedState {
                releaseTokenIfResolved(forcedState)
                phase = .ready
            }
        } catch {
            phase = .failed
        }
    }
}

private func larryLine(_ quote: String, portrait: LarryPortrait) -> some View {
    HStack(alignment: .top, spacing: 12) {
        LarryAvatarView(portrait: portrait, size: 48)
        Text("“\(quote)”")
            .font(.subheadline)
            .foregroundStyle(BrandTheme.homeSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
