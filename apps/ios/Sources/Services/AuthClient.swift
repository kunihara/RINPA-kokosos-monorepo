import Foundation
import AuthenticationServices

struct AuthClient {
    struct Config {
        let supabaseURL: URL
        let anonKey: String
    }

    let config: Config

    init?() {
        // Read from Info.plist and validate/trim
        let info = Bundle.main.infoDictionary
        let rawURL = (info?["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHost = (info?["SupabaseHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAnon = (info?["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var base: URL? = nil
        if let s = rawURL, let u = URL(string: s), u.scheme == "https", u.host != nil {
            base = u
        } else if let host = rawHost, !host.isEmpty {
            // Build https URL from host fallback to avoid xcconfig '//' comment pitfalls
            base = URL(string: "https://\(host)")
        }
        guard let finalBase = base, let anon = rawAnon, !anon.isEmpty else { return nil }
        #if DEBUG
        print("[AuthClient] SupabaseURL=\(finalBase.absoluteString)")
               // Print only prefix of anon key for safety
        if let pref = rawAnon?.prefix(6) { print("[AuthClient] SupabaseAnonKey(6)=\(pref)…") }
        #endif
        self.config = Config(supabaseURL: finalBase, anonKey: anon)
    }

    func signIn(email: String, password: String) async throws -> String { // returns access_token
        var comps = URLComponents()
        comps.scheme = config.supabaseURL.scheme
        comps.host = config.supabaseURL.host
        comps.port = config.supabaseURL.port
        comps.path = "/auth/v1/token"
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

    /// Sign up with email & password.
    /// - Returns: access_token if即時ログインが成立、nilの場合はメール確認が必要
    func signUp(email: String, password: String, redirectTo: String? = nil) async throws -> String? {
        var comps = URLComponents()
        comps.scheme = config.supabaseURL.scheme
        comps.host = config.supabaseURL.host
        comps.port = config.supabaseURL.port
        comps.path = "/auth/v1/signup"
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["email": email, "password": password]
        if let redirectTo, !redirectTo.isEmpty {
            // Supabase: email confirmation redirect is specified via 'email_redirect_to'
            body["email_redirect_to"] = redirectTo
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "サインアップに失敗しました (\(http.statusCode)) \(msg)"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // メール確認がOFFな場合はaccess_tokenが返る。ONならnil。
        return json?["access_token"] as? String
    }

    /// Send password reset email
    func sendPasswordReset(email: String, redirectTo: String? = nil) async throws {
        var comps = URLComponents()
        comps.scheme = config.supabaseURL.scheme
        comps.host = config.supabaseURL.host
        comps.port = config.supabaseURL.port
        comps.path = "/auth/v1/recover"
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["email": email]
        if let redirectTo { body["redirect_to"] = redirectTo }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "パスワードリセットの送信に失敗しました"])
        }
    }

    // OAuth via ASWebAuthenticationSession (Apple/Google/Facebook)
    func signInWithOAuth(provider: String, presentationAnchor: ASPresentationAnchor?) async throws -> String {
        // Construct authorize URL from base components to avoid malformed hosts
        let redirectScheme = (Bundle.main.infoDictionary?["OAuthRedirectScheme"] as? String) ?? "kokosos"
        let redirectURI = "\(redirectScheme)://oauth-callback"
        var comps = URLComponents()
        comps.scheme = config.supabaseURL.scheme
        comps.host = config.supabaseURL.host
        comps.port = config.supabaseURL.port
        comps.path = "/auth/v1/authorize"
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
