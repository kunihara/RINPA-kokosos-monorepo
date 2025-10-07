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

    /// Try registering the last known token if we have an auth session.
    func ensureRegisteredIfPossible() {
        guard let token = UserDefaults.standard.string(forKey: lastTokenKey), !token.isEmpty else { return }
        // Require Supabase access token to be present (signed in)
        guard let t = SupabaseAuthAdapter.shared.accessToken, !t.isEmpty else { return }
        Task { @MainActor in
            do { try await self.callRegister(token: token) } catch { /* noop */ }
        }
    }

    private func callRegister(token: String) async throws {
        guard let url = URL(string: "devices/register", relativeTo: APIClient().baseURL) else { return }
        _ = await SupabaseAuthAdapter.shared.refresh()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = SupabaseAuthAdapter.shared.accessToken, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["platform": "ios", "fcm_token": token]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[/devices/register] failed status=\((resp as? HTTPURLResponse)?.statusCode ?? -1) body=\(bodyText.prefix(200))")
            #endif
            return
        }
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
