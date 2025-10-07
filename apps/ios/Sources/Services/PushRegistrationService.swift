import Foundation

final class PushRegistrationService {
    static let shared = PushRegistrationService()
    private init() {}

    private let lastTokenKey = "LastFCMToken"

    func register(token: String) {
        guard !token.isEmpty else { return }
        UserDefaults.standard.set(token, forKey: lastTokenKey)
        Task { @MainActor in
            do { try await self.callRegister(token: token) } catch { /* noop */ }
        }
    }

    func unregisterLastToken() {
        let token = UserDefaults.standard.string(forKey: lastTokenKey) ?? ""
        guard !token.isEmpty else { return }
        Task { @MainActor in
            do { try await self.callUnregister(token: token) } catch { /* noop */ }
        }
    }

    private func callRegister(token: String) async throws {
        guard let url = URL(string: "devices/register", relativeTo: APIClient().baseURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = SupabaseAuthAdapter.shared.accessToken, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["platform": "ios", "fcm_token": token]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
    }

    private func callUnregister(token: String) async throws {
        guard let url = URL(string: "devices/unregister", relativeTo: APIClient().baseURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = SupabaseAuthAdapter.shared.accessToken, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["fcm_token": token]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
    }
}

