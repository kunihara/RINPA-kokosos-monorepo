import Foundation

struct Contact: Codable, Hashable {
    let id: String
    let name: String?
    let email: String
    let role: String?
    let capabilities: [String: Bool]?
    let verified_at: String?
}

final class ContactsClient {
    private let api = APIClient()
    
    // Execute request with auto-refresh (once) on 401
    private func execute(_ build: () -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = build()
        var (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401, api.currentRefreshToken() != nil {
            if await AuthClient.performRefreshAndStore() {
                req = build()
                (data, resp) = try await URLSession.shared.data(for: req)
            }
        }
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    func list(status: String = "all") async throws -> [Contact] {
        var comps = URLComponents(url: api.baseURL, resolvingAgainstBaseURL: false)!
        comps.path = (comps.path as NSString).appendingPathComponent("contacts")
        comps.queryItems = [URLQueryItem(name: "status", value: status)]
        let (data, http) = try await execute {
            var req = URLRequest(url: comps.url!)
            apiApplyAuth(&req)
            return req
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = obj?["items"] as? [[String: Any]] ?? []
        let jsonData = try JSONSerialization.data(withJSONObject: items)
        return try JSONDecoder().decode([Contact].self, from: jsonData)
    }

    func bulkUpsert(emails: [String], sendVerify: Bool) async throws -> [Contact] {
        let contacts = emails.map { ["email": $0] }
        let body: [String: Any] = ["contacts": contacts, "send_verify": sendVerify]
        let (data, http) = try await execute {
            var req = URLRequest(url: api.baseURL.appendingPathComponent("contacts/bulk_upsert"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            apiApplyAuth(&req)
            req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
            return req
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = obj?["items"] as? [[String: Any]] ?? []
        let jsonData = try JSONSerialization.data(withJSONObject: items)
        return try JSONDecoder().decode([Contact].self, from: jsonData)
    }

    private func apiApplyAuth(_ req: inout URLRequest) {
        if let t = UserDefaults.standard.string(forKey: APIClient.authTokenUserDefaultsKey), !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
    }
}
