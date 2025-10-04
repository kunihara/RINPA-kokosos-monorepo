import Foundation

struct APIClient {
    let baseURL: URL
    static let authTokenUserDefaultsKey = "APIAuthToken"
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

    // 簡易的なトークン保存（将来Supabase Authのaccess_tokenを格納）
    func setAuthToken(_ token: String?) {
        if let t = token, !t.isEmpty {
            UserDefaults.standard.set(t, forKey: APIClient.authTokenUserDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: APIClient.authTokenUserDefaultsKey)
        }
    }

    private func applyAuth(_ req: inout URLRequest) {
        if let t = UserDefaults.standard.string(forKey: APIClient.authTokenUserDefaultsKey), !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
    }

    func currentAuthToken() -> String? {
        let t = UserDefaults.standard.string(forKey: APIClient.authTokenUserDefaultsKey)
        return (t?.isEmpty == false) ? t : nil
    }

    func startAlert(lat: Double, lng: Double, accuracy: Double?, battery: Int?, type: String = "emergency", maxDurationSec: Int = 3600) async throws -> StartAlertResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/alert/start"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        let body: [String: Any?] = [
            "lat": lat,
            "lng": lng,
            "accuracy_m": accuracy,
            "battery_pct": battery,
            "type": type,
            "max_duration_sec": maxDurationSec
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try JSONDecoder().decode(StartAlertResponse.self, from: data)
    }

    func updateAlert(id: String, lat: Double, lng: Double, accuracy: Double?, battery: Int?) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/alert/\(id)/update"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        let body: [String: Any?] = [
            "lat": lat,
            "lng": lng,
            "accuracy_m": accuracy,
            "battery_pct": battery,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    func stopAlert(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/alert/\(id)/stop"))
        req.httpMethod = "POST"
        applyAuth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    func revokeAlert(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/alert/\(id)/revoke"))
        req.httpMethod = "POST"
        applyAuth(&req)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func extendAlert(id: String, extendMinutes: Int) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/alert/\(id)/extend"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["extend_sec": extendMinutes * 60]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
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
