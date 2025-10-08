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
        } else {
            cachedAccessToken = nil
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
                return true
            } else {
                cachedAccessToken = nil
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

    /// Online validation: verifies the current session with Supabase Auth.
    /// Returns true if a valid user is returned, otherwise clears cached token and returns false.
    @discardableResult
    func validateOnline() async -> Bool {
        do {
            // If there's no local session, treat as invalid quickly
            guard let _ = try? await client.auth.session else {
                cachedAccessToken = nil
                return false
            }
            // Ask server for current user; 401/invalid will throw
            _ = try await client.auth.getUser()
            // keep cached token in sync
            if let s = try? await client.auth.session, !s.accessToken.isEmpty {
                cachedAccessToken = s.accessToken
            }
            return true
        } catch {
            cachedAccessToken = nil
            return false
        }
    }
}
