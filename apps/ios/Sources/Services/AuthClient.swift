import Foundation
import AuthenticationServices

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

    // OAuth via ASWebAuthenticationSession (Apple/Google/Facebook)
    func signInWithOAuth(provider: String, presentationAnchor: ASPresentationAnchor?) async throws -> String {
        // Construct authorize URL
        let redirectScheme = (Bundle.main.infoDictionary?["OAuthRedirectScheme"] as? String) ?? "kokosos"
        let redirectURI = "\(redirectScheme)://oauth-callback"
        var comps = URLComponents(url: config.supabaseURL.appendingPathComponent("/auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectURI),
            URLQueryItem(name: "scopes", value: scopes(for: provider))
        ]
        let authURL = comps.url!
        // Start web auth session
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { callbackURL, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let url = callbackURL else {
                    cont.resume(throwing: NSError(domain: "auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "OAuthフローがキャンセルされました"]))
                    return
                }
                // Parse fragment for access_token
                if let token = Self.extractAccessToken(from: url) {
                    cont.resume(returning: token)
                } else {
                    cont.resume(throwing: NSError(domain: "auth", code: -3, userInfo: [NSLocalizedDescriptionKey: "トークンを取得できませんでした"]))
                }
            }
            if let anchor = presentationAnchor { session.presentationContextProvider = AnchorProvider(anchor: anchor) }
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    private func scopes(for provider: String) -> String {
        switch provider {
        case "google": return "email profile"
        case "facebook": return "email public_profile"
        case "apple": return "name email"
        default: return "email"
        }
    }

    private static func extractAccessToken(from url: URL) -> String? {
        // Supabase OAuth callback places tokens in URL fragment: #access_token=...&...
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else { return nil }
        let items = fragment.split(separator: "&").map { String($0) }
        var dict: [String: String] = [:]
        for item in items {
            let parts = item.split(separator: "=")
            if parts.count == 2 {
                let key = String(parts[0])
                let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                dict[key] = val
            }
        }
        return dict["access_token"]
    }
}

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
