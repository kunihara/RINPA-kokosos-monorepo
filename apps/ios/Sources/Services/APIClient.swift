import Foundation

struct APIClient {
    let baseURL: URL
    static let authTokenUserDefaultsKey = "APIAuthToken" // deprecated
    static let refreshTokenUserDefaultsKey = "APIRefreshToken" // deprecated
    static let baseURLOverrideKey = "APIBaseURLOverride"

    init() {
        let dict = Bundle.main.infoDictionary
        // 1) User override from Settings (for device testing or custom endpoints)
        if let override = UserDefaults.standard.string(forKey: APIClient.baseURLOverrideKey) {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let schemeOK = (comps.scheme == "http" || comps.scheme == "https")
                if schemeOK, let host = comps.host, !host.isEmpty {
                    self.baseURL = url
                    return
                }
            }
        }

        // Helper: treat unresolved $(VAR) as invalid
        func isUnresolvedVariable(_ s: String) -> Bool { s.contains("$(") }

        // 2) Info.plist URL value
        let base = (dict?["APIBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against placeholder domains left as-is and unresolved variables
        let invalidPlaceholders = ["YOUR_WORKERS_DOMAIN", "YOUR_PROD_DOMAIN", "YOUR_", "<", ">"]
        if let b = base, !isUnresolvedVariable(b), !invalidPlaceholders.contains(where: { b.contains($0) }), let url = URL(string: b), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), (comps.scheme == "http" || comps.scheme == "https"), let host = comps.host, !host.isEmpty {
            self.baseURL = url
            return
        }

        // 3) Info.plist Host + Scheme fallback (avoids xcconfig '//' comment pitfalls)
        let host = (dict?["APIBaseHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = ((dict?["APIBaseScheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "https"
        if let h = host, !h.isEmpty, !isUnresolvedVariable(h) {
            if var comps = URLComponents() as URLComponents? {
                comps.scheme = scheme.isEmpty ? "https" : scheme
                // Allow optional port specified as part of host like "localhost:8787"
                if h.contains(":"), let last = h.split(separator: ":").last, let p = Int(last) {
                    comps.host = String(h.split(separator: ":").dropLast().joined(separator: ":"))
                    comps.port = p
                } else {
                    comps.host = h
                }
                comps.path = "/"
                if let url = comps.url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let chost = c.host, !chost.isEmpty {
                    self.baseURL = url
                    return
                }
            }
        }

        // 4) Fallback (local dev)
        self.baseURL = URL(string: "http://localhost:8787")!
    }

    // Build endpoint URL by joining path segments safely (no leading slashes)
    private func endpoint(_ segments: String...) -> URL {
        return segments.reduce(baseURL) { url, seg in url.appendingPathComponent(seg) }
    }

    // 旧トークン保存APIは廃止（SDKセッションに統一）
    func setAuthToken(_ token: String?) { /* no-op (deprecated) */ }
    func setRefreshToken(_ token: String?) { /* no-op (deprecated) */ }

    private func applyAuth(_ req: inout URLRequest) {
        // Prefer supabase-swift session if available
        if let sdkToken = SupabaseAuthAdapter.shared.accessToken, !sdkToken.isEmpty {
            req.setValue("Bearer \(sdkToken)", forHTTPHeaderField: "Authorization")
            return
        }
        // Fallback: legacy storage (until完全移行)
        if let t = UserDefaults.standard.string(forKey: APIClient.authTokenUserDefaultsKey), !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
    }

    // 旧セッション参照は廃止（SDKに統一）
    func currentAuthToken() -> String? { SupabaseAuthAdapter.shared.accessToken }
    func currentRefreshToken() -> String? { nil }

    // Execute a request and if 401 occurs, attempt a one-time refresh and retry
    private func execute(_ build: () -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Proactive refresh across all requests (access token expiring soon)
        var didProactiveRefresh = false
        didProactiveRefresh = await SupabaseAuthAdapter.shared.refresh()
        var req = build()
        #if DEBUG
        let tokenPrefix = (SupabaseAuthAdapter.shared.accessToken ?? "nil").prefix(10)
        print("[API] -> \(req.httpMethod ?? "GET") \(req.url?.path ?? "") auth=\(tokenPrefix) proactiveRefresh=\(didProactiveRefresh)")
        #endif
        var (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            let refreshed = await SupabaseAuthAdapter.shared.refresh()
            #if DEBUG
            print("[API] 401 -> refresh=\(refreshed) retry \(req.url?.path ?? "")")
            #endif
            if refreshed {
                req = build()
                (data, resp) = try await URLSession.shared.data(for: req)
            }
        }
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        #if DEBUG
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "(binary)"
            print("[API] <- \(http.statusCode) \(req.url?.path ?? "") body=\(body.prefix(300))")
        } else {
            print("[API] <- \(http.statusCode) \(req.url?.path ?? "")")
        }
        #endif
        return (data, http)
    }

    func startAlert(lat: Double, lng: Double, accuracy: Double?, battery: Int?, type: String = "emergency", maxDurationSec: Int = 3600, recipients: [String]) async throws -> StartAlertResponse {
        let body: [String: Any?] = [
            "lat": lat,
            "lng": lng,
            "accuracy_m": accuracy,
            "battery_pct": battery,
            "type": type,
            "max_duration_sec": maxDurationSec,
            "recipients": recipients
        ]
        let (data, http) = try await execute {
            var req = URLRequest(url: endpoint("alert", "start"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var r = req; applyAuth(&r)
            r.httpBody = try? JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }, options: [])
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try JSONDecoder().decode(StartAlertResponse.self, from: data)
    }

    func updateAlert(id: String, lat: Double, lng: Double, accuracy: Double?, battery: Int?) async throws {
        let body: [String: Any?] = [
            "lat": lat,
            "lng": lng,
            "accuracy_m": accuracy,
            "battery_pct": battery,
        ]
        let (data, http) = try await execute {
            var req = URLRequest(url: endpoint("alert", id, "update"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var r = req; applyAuth(&r)
            r.httpBody = try? JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }, options: [])
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    // MARK: Profile - Avatar
    struct UploadURLResponse: Codable { let uploadUrl: String; let path: String; let expiresIn: Int }

    func profileAvatarUploadURL(ext: String) async throws -> UploadURLResponse {
        let (data, http) = try await execute {
            var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            comps.path = (comps.path as NSString).appendingPathComponent("profile/avatar/upload-url")
            comps.queryItems = [URLQueryItem(name: "ext", value: ext)]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "POST"
            applyAuth(&req)
            return req
        }
        if !(200..<300).contains(http.statusCode) { throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8)) }
        return try JSONDecoder().decode(UploadURLResponse.self, from: data)
    }

    func profileAvatarUpload(to uploadURL: String, data: Data, mime: String) async throws {
        let fullURL: URL
        if let u = URL(string: uploadURL), u.scheme != nil { fullURL = u }
        else { fullURL = baseURL.appendingPathComponent(uploadURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }

        let boundary = "Boundary-" + UUID().uuidString
        var body = Data()
        let crlf = "\r\n".data(using: .utf8)!
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append(crlf)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (respData, http) = try await URLSession.shared.data(for: {
            var req = URLRequest(url: fullURL)
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            return req
        }())
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: respData, encoding: .utf8))
        }
    }

    func profileAvatarCommit(path: String?, name: String) async throws {
        let payload: [String: Any?] = ["path": path, "name": name]
        let (data, http) = try await execute {
            var req = URLRequest(url: baseURL.appendingPathComponent("profile/avatar/commit"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var r = req; applyAuth(&r)
            r.httpBody = try? JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    func stopAlert(id: String) async throws {
        let (data, http) = try await execute {
            var req = URLRequest(url: endpoint("alert", id, "stop"))
            req.httpMethod = "POST"
            var r = req; applyAuth(&r)
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    func revokeAlert(id: String) async throws {
        let (data, http) = try await execute {
            var req = URLRequest(url: endpoint("alert", id, "revoke"))
            req.httpMethod = "POST"
            var r = req; applyAuth(&r)
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    func extendAlert(id: String, extendMinutes: Int) async throws {
        let body: [String: Any] = ["extend_sec": extendMinutes * 60]
        let (data, http) = try await execute {
            var req = URLRequest(url: endpoint("alert", id, "extend"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var r = req; applyAuth(&r)
            r.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    func deleteAccount() async throws {
        _ = await SupabaseAuthAdapter.shared.refresh()
        let (data, http) = try await execute {
            var req = URLRequest(url: endpoint("account"))
            req.httpMethod = "DELETE"
            var r = req; applyAuth(&r)
            return r
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }
}

struct StartAlertResponse: Codable {
    enum Mode: String, Codable { case emergency, going_home }
    struct Latest: Codable {
        let lat: Double
        let lng: Double
        let accuracy_m: Double?
        let battery_pct: Int?
        let captured_at: String
    }
    let type: Mode
    let id: String
    let status: String
    let started_at: String
    let max_duration_sec: Int
    let latest: Latest
    let shareToken: String
}

enum APIError: LocalizedError {
    case http(status: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case let .http(status, body):
            let msg = (body?.isEmpty == false ? body! : nil) ?? ""
            // Try to extract {"error":"...","detail":"..."}
            if let data = msg.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let e = (json["error"] as? String) ?? ""
                let d = (json["detail"] as? String) ?? ""
                let joined = [e, d].filter { !$0.isEmpty }.joined(separator: ": ")
                if !joined.isEmpty { return "サーバーエラー(\(status)): \(joined)" }
            }
            return "サーバーエラー(\(status))"
        }
    }
}
