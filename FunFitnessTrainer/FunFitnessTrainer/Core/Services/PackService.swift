import Foundation

/// Minimal pack social: friends = shared invite code (see docs/THE_PACK.md).
@MainActor
final class PackService {
    static let shared = PackService()

    private let supabase = SupabaseService.shared

    private init() {}

    func ensurePackCode() async throws -> String? {
        guard supabase.isSignedIn, AppConfig.hasBackend else { return nil }
        return try await callRPCString(function: "ensure_my_pack", body: [:])
    }

    func joinPack(code: String) async throws -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw APIError.serverMessage("Enter a pack code.") }
        return try await callRPCString(function: "join_pack", body: ["invite": trimmed])
    }

    func shareMeal(name: String, calories: Double, proteinG: Double, loggedAt: Date) async {
        guard supabase.isSignedIn, AppConfig.hasBackend, let userId = supabase.userId else { return }
        guard let base = AppConfig.supabaseURL else { return }

        let url = base.appendingPathComponent("rest/v1/pack_meal_posts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        if let anon = AppConfig.supabaseAnonKey { request.setValue(anon, forHTTPHeaderField: "apikey") }
        if let token = supabase.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let body: [String: Any] = [
            "user_id": userId,
            "meal_name": name,
            "calories": calories,
            "protein_g": proteinG,
            "logged_at": ISO8601DateFormatter().string(from: loggedAt),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    func fetchPackFeed() async throws -> [PackFeedEntry] {
        guard supabase.isSignedIn, AppConfig.hasBackend else { return [] }

        guard let base = AppConfig.supabaseURL else { throw APIError.missingConfiguration }
        let start = PackInterestingPostBuilder.startOfWeek()
        let iso = ISO8601DateFormatter().string(from: start)

        var components = URLComponents(
            url: base.appendingPathComponent("rest/v1/pack_meal_posts"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,meal_name,calories,protein_g,logged_at,user_id,profiles(display_name)"),
            URLQueryItem(name: "logged_at", value: "gte.\(iso)"),
            URLQueryItem(name: "order", value: "logged_at.desc"),
            URLQueryItem(name: "limit", value: "200"),
        ]

        var request = URLRequest(url: components.url!)
        if let anon = AppConfig.supabaseAnonKey { request.setValue(anon, forHTTPHeaderField: "apikey") }
        if let token = supabase.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let rows = try JSONDecoder().decode([PackMealPostRow].self, from: data)
        let myId = supabase.userId
        return rows.map { row in
            let name = row.profiles?.display_name ?? "Pack member"
            return PackFeedEntry(
                id: row.id,
                memberName: row.user_id == myId ? "You" : name,
                mealName: row.meal_name,
                calories: Int(row.calories),
                proteinG: Int(row.protein_g),
                loggedAt: row.loggedAtDate,
                isYou: row.user_id == myId
            )
        }
    }

    private func callRPCString(function: String, body: [String: Any]) async throws -> String {
        guard let base = AppConfig.supabaseURL else { throw APIError.missingConfiguration }
        let url = base.appendingPathComponent("rest/v1/rpc/\(function)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let anon = AppConfig.supabaseAnonKey { request.setValue(anon, forHTTPHeaderField: "apikey") }
        if let token = supabase.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Pack request failed"
            throw APIError.serverMessage(msg)
        }

        if let str = try? JSONDecoder().decode(String.self, from: data) {
            return str
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n")) ?? ""
    }
}

private struct PackMealPostRow: Decodable {
    let id: UUID
    let meal_name: String
    let calories: Double
    let protein_g: Double
    let logged_at: String
    let user_id: String
    let profiles: PackProfileRow?

    var loggedAtDate: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: logged_at) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: logged_at) ?? Date()
    }
}

private struct PackProfileRow: Decodable {
    let display_name: String?
}
