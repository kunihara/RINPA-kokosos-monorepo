import Foundation
import Supabase

final class SupabaseAuthAdapter {
    static let shared = SupabaseAuthAdapter()
    let client: SupabaseClient
    private(set) var cachedAccessToken: String? = nil

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
        // 現在のセッションからアクセストークンをキャッシュ（非同期）
        Task { await self.updateCachedToken() }
    }

    // Expose access token if SDKセッションがあれば
    // SDK v2では session の取得が async throws のため、同期的にはキャッシュを返す
    var accessToken: String? { cachedAccessToken }

    /// SDKから現在のセッションを取得してキャッシュを更新
    func updateCachedToken() async {
        if let s = try? await client.auth.session, !s.accessToken.isEmpty {
            cachedAccessToken = s.accessToken
            #if DEBUG
            print("[DEBUG] AuthAdapter updateCachedToken: session present (prefix=\(s.accessToken.prefix(8)))")
            #endif
        } else {
            cachedAccessToken = nil
            #if DEBUG
            print("[DEBUG] AuthAdapter updateCachedToken: no session")
            #endif
        }
    }

    // Try refresh via SDK; returns true on success
    @discardableResult
    func refresh() async -> Bool {
        do {
            _ = try await client.auth.refreshSession()
            // refresh成功後に最新セッションを取得してキャッシュ
            if let s = try? await client.auth.session, !s.accessToken.isEmpty {
                cachedAccessToken = s.accessToken
                #if DEBUG
                print("[DEBUG] AuthAdapter refresh: ok (prefix=\(s.accessToken.prefix(8)))")
                #endif
                return true
            } else {
                cachedAccessToken = nil
                #if DEBUG
                print("[DEBUG] AuthAdapter refresh: ok but no session")
                #endif
                return false
            }
        } catch {
#if DEBUG
            print("[SupabaseSDK] refresh error=\(error.localizedDescription)")
#endif
            cachedAccessToken = nil
            return false
        }
    }

    /// Online validation: verifies the current session with Supabase Auth by refreshing it.
    /// Returns true if a valid session is present after refresh, otherwise clears cached token and returns false.
    @discardableResult
    func validateOnline() async -> Bool {
        // Fast-fail if no local session at all
        guard let _ = try? await client.auth.session else {
            cachedAccessToken = nil
            #if DEBUG
            print("[DEBUG] AuthAdapter validateOnline: no local session")
            #endif
            return false
        }
        // Attempt to refresh; this performs a server-side validation implicitly
        let ok = await refresh()
        if !ok { cachedAccessToken = nil }
        #if DEBUG
        print("[DEBUG] AuthAdapter validateOnline result=\(ok)")
        #endif
        return ok
    }
}
