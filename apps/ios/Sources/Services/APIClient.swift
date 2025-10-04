import Foundation

struct APIClient {
    let baseURL: URL
    static let authTokenUserDefaultsKey = "APIAuthToken"

    init() {
        let dict = Bundle.main.infoDictionary
        let base = dict?["APIBaseURL"] as? String ?? "http://localhost:8787"
        self.baseURL = URL(string: base) ?? URL(string: "http://localhost:8787")!
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
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
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
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func stopAlert(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/alert/\(id)/stop"))
        req.httpMethod = "POST"
        applyAuth(&req)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
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
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
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
