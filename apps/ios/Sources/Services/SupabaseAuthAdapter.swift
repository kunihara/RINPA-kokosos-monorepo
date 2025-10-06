import Foundation
import Supabase

final class SupabaseAuthAdapter {
    static let shared = SupabaseAuthAdapter()
    let client: SupabaseClient

    private init() {
        // Resolve from Info.plist (URL or Host) + anon key
        let info = Bundle.main.infoDictionary
        let rawURL = (info?["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHost = (info?["SupabaseHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAnon = (info?["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var base: URL = URL(string: "https://invalid.local")!
        if let s = rawURL, let u = URL(string: s), u.scheme == "https", u.host != nil {
            base = u
        } else if let h = rawHost, !h.isEmpty, let u = URL(string: "https://\(h)") {
            base = u
        }
        let key = (rawAnon?.isEmpty == false) ? rawAnon! : "" // SDKはKey必須
        client = SupabaseClient(supabaseURL: base, supabaseKey: key)
    }

    // Expose access token if SDKセッションがあれば
    var accessToken: String? { client.auth.session?.accessToken }

    // Try refresh via SDK; returns true on success
    @discardableResult
    func refresh() async -> Bool {
        do {
            _ = try await client.auth.refreshSession()
            return client.auth.session?.accessToken.isEmpty == false
        } catch {
            #if DEBUG
            print("[SupabaseSDK] refresh error=\(error.localizedDescription)")
            #endif
            return false
        }
    }
}

