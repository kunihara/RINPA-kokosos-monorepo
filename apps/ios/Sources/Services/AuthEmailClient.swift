import Foundation

final class AuthEmailClient {
    private let api = APIClient()

    struct Result: Codable { let ok: Bool }

    func sendPasswordReset(email: String, redirectTo: URL?) async throws {
        var url = api.baseURL.appendingPathComponent("auth/email/reset")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["email": email]
        if let r = redirectTo { body["redirect_to"] = r.absoluteString }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: msg)
        }
        // Response is generic { ok: true } — ignore content
    }

    func sendMagicLink(email: String, redirectTo: URL?) async throws {
        let url = api.baseURL.appendingPathComponent("auth/email/magic")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["email": email]
        if let r = redirectTo { body["redirect_to"] = r.absoluteString }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: msg)
        }
    }

    func sendReauth(redirectTo: URL?) async throws {
        let url = api.baseURL.appendingPathComponent("auth/email/reauth")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SupabaseAuthAdapter.shared.accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = [:]
        if let r = redirectTo { body["redirect_to"] = r.absoluteString }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: msg)
        }
    }

    func changeEmail(newEmail: String, redirectTo: URL?) async throws {
        let url = api.baseURL.appendingPathComponent("auth/email/change")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SupabaseAuthAdapter.shared.accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["new_email": newEmail]
        if let r = redirectTo { body["redirect_to"] = r.absoluteString }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: msg)
        }
    }

    func signUp(email: String, password: String, redirectTo: URL?) async throws {
        let url = api.baseURL.appendingPathComponent("auth/signup")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["email": email, "password": password]
        if let r = redirectTo { body["redirect_to"] = r.absoluteString }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: msg)
        }
    }
}
