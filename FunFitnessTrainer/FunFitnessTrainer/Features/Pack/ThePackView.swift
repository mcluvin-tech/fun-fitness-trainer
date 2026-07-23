import SwiftUI
import SwiftData

struct ThePackView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meal.loggedAt, order: .reverse) private var allMeals: [Meal]
    @StateObject private var supabase = SupabaseService.shared

    @State private var feed: [PackFeedEntry] = []
    @State private var packCode: String?
    @State private var joinCode = ""
    @State private var isLoading = true
    @State private var packMessage: String?

    private var yourMealsThisWeek: [Meal] {
        let weekStart = PackInterestingPostBuilder.startOfWeek()
        return allMeals.filter { $0.loggedAt >= weekStart }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    packInviteCard

                    if isLoading && feed.isEmpty {
                        ProgressView("Loading the pack…")
                            .padding(.vertical, 24)
                    } else {
                        if !feed.filter(\.isYou).isEmpty {
                            feedSection(
                                title: "Your log",
                                entries: feed.filter(\.isYou)
                            )
                        }

                        feedSection(
                            title: "Pack eats",
                            entries: feed.filter { !$0.isYou }
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("The Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh pack feed")
                }
            }
            .task { await reload() }
        }
    }

    // MARK: - Pack invite (how we know who is a friend)

    private var packInviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Friends = your pack", systemImage: "person.3.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTheme.teal)

            Text("There’s no friends list. Anyone who joins your **pack code** eats with you in this feed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !supabase.isSignedIn {
                Text("Sign in under Settings to get your code and see real pack meals.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let packCode {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your pack code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(packCode)
                            .font(.title2.weight(.bold))
                            .monospaced()
                    }
                    Spacer()
                    ShareLink(item: "Join my Fun Fitness Trainer pack! Code: \(packCode)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .tint(BrandTheme.teal)
                }
            }

            HStack(spacing: 8) {
                TextField("Friend’s pack code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") {
                    Task { await joinPackTapped() }
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandTheme.teal)
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty || !supabase.isSignedIn)
            }

            if let packMessage {
                Text(packMessage)
                    .font(.caption)
                    .foregroundStyle(packMessage.contains("Joined") ? BrandTheme.teal : .red)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func feedSection(title: String, entries: [PackFeedEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if entries.isEmpty {
                Text("No interesting pack updates yet this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        PackFeedRow(entry: entry)
                        if entry.id != entries.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        if supabase.isSignedIn, AppConfig.hasBackend {
            packCode = try? await PackService.shared.ensurePackCode()
        }

        feed = await PackFeedService.loadFeedRemoteFirst(yourMealsThisWeek: yourMealsThisWeek)
    }

    private func joinPackTapped() async {
        packMessage = nil
        do {
            let code = try await PackService.shared.joinPack(code: joinCode)
            packMessage = "Joined pack \(code). Their meals will show up here."
            joinCode = ""
            await reload()
        } catch {
            packMessage = error.localizedDescription
        }
    }
}

private struct PackFeedRow: View {
    let entry: PackFeedEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.isYou ? BrandTheme.purple.opacity(0.2) : BrandTheme.teal.opacity(0.2))
                    .frame(width: 40, height: 40)
                Text(entry.memberName.prefix(1).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(entry.isYou ? BrandTheme.purple : BrandTheme.teal)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if !entry.isInterestingStat {
                        Text(entry.memberName)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Text(entry.loggedAt, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(entry.mealName)
                    .font(entry.isInterestingStat ? .body.weight(.medium) : .body)
                Text(entry.isInterestingStat
                    ? "This week · \(entry.calories) cal · P \(entry.proteinG)g"
                    : "\(entry.calories) cal · P \(entry.proteinG)g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isInterestingStat
            ? "\(entry.mealName), \(entry.calories) calories this week"
            : "\(entry.memberName) ate \(entry.mealName), \(entry.calories) calories")
    }
}
