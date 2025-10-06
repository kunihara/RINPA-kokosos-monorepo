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

    // Serialize refresh to a single in-flight task to avoid token reuse/rotation競合
    actor RefreshCoordinator {
        static let shared = RefreshCoordinator()
        private var inFlight: Task<Bool, Never>? = nil
        func run(_ block: @escaping () async -> Bool) async -> Bool {
            if let t = inFlight { return await t.value }
            let task = Task { await block() }
            inFlight = task
            let result = await task.value
            inFlight = nil
            return result
        }
    }

    static func performRefreshAndStore() async -> Bool {
        return await RefreshCoordinator.shared.run {
            await _performRefreshAndStore()
        }
    }

    // Actual refresh implementation (do not call directly; use performRefreshAndStore)
    private static func _performRefreshAndStore() async -> Bool {
        let api = APIClient()
        guard let refresh = api.currentRefreshToken() else { return false }
        guard let client = AuthClient() else { return false }
        do {
            var comps = URLComponents()
            comps.scheme = client.config.supabaseURL.scheme
            comps.host = client.config.supabaseURL.host
            comps.port = client.config.supabaseURL.port
            comps.path = "/auth/v1/token"
            comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(client.config.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(client.config.anonKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = ["refresh_token": refresh]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            #if DEBUG
            print("[Auth] refresh start rt=\(refresh.prefix(6))… host=\(client.config.supabaseURL.host ?? "")")
            #endif
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            if !(200..<300).contains(http.statusCode) {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? "(binary)"
                print("[Auth] refresh failed status=\(http.statusCode) body=\(body.prefix(200))")
                #endif
                return false
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let newAccess = json?["access_token"] as? String else { return false }
            let newRefresh = json?["refresh_token"] as? String
            api.setAuthToken(newAccess)
            if let rt = newRefresh { api.setRefreshToken(rt) }
            #if DEBUG
            print("[Auth] refresh ok at=\(newAccess.prefix(10)) rt=\((newRefresh ?? "nil").prefix(6))…")
            #endif
            return true
        } catch {
#if DEBUG
            print("[Auth] refresh exception=\(error.localizedDescription)")
#endif
            return false
        }
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
        let refresh = json?["refresh_token"] as? String
        let api = APIClient()
        api.setAuthToken(token)
        api.setRefreshToken(refresh)
        // Try import into supabase-swift session (best-effort)
        _ = await SupabaseAuthAdapter.shared.refresh()
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
        if let token = json?["access_token"] as? String {
            let refresh = json?["refresh_token"] as? String
            let api = APIClient(); api.setAuthToken(token); api.setRefreshToken(refresh)
            return token
        }
        // メール確認がONな場合はnilが返る
        return nil
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

    /// Resend signup confirmation email
    func resendSignup(email: String, redirectTo: String? = nil) async throws {
        var comps = URLComponents()
        comps.scheme = config.supabaseURL.scheme
        comps.host = config.supabaseURL.host
        comps.port = config.supabaseURL.port
        comps.path = "/auth/v1/resend"
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["email": email, "type": "signup"]
        if let redirectTo, !redirectTo.isEmpty { body["redirect_to"] = redirectTo }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "確認メールの再送に失敗しました"])
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
            URLQueryItem(name: "scopes", value: scopes(for: provider)),
            URLQueryItem(name: "response_type", value: "token")
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
                if let (access, refresh) = Self.extractTokens(from: url) {
                    let api = APIClient(); api.setAuthToken(access); api.setRefreshToken(refresh)
                    cont.resume(returning: access)
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
        // refresh_token を確実に得るため offline_access を付与
        switch provider {
        case "google": return "email profile offline_access"
        case "facebook": return "email public_profile offline_access"
        case "apple": return "name email offline_access"
        default: return "email offline_access"
        }
    }

    private static func extractTokens(from url: URL) -> (String, String?)? {
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
        if let at = dict["access_token"] { return (at, dict["refresh_token"]) }
        return nil
    }
}

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
