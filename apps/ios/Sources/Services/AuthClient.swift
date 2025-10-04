import Foundation

struct AuthClient {
    struct Config {
        let supabaseURL: URL
        let anonKey: String
    }

    let config: Config

    init?() {
        let dict = Bundle.main.infoDictionary
        guard let supabase = dict?["SupabaseURL"] as? String,
              let url = URL(string: supabase),
              let anon = dict?["SupabaseAnonKey"] as? String,
              !anon.isEmpty else { return nil }
        self.config = Config(supabaseURL: url, anonKey: anon)
    }

    func signIn(email: String, password: String) async throws -> String { // returns access_token
        var comps = URLComponents(url: config.supabaseURL.appendingPathComponent("/auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["email": email, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "サインインに失敗しました (\(http.statusCode)) \(msg)"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            throw NSError(domain: "auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "トークンを取得できませんでした"])
        }
        return token
    }
}

