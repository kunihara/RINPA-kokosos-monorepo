import UIKit
import Supabase

enum DeepLinkHandler {
    /// Handle custom URL scheme callback like:
    /// kokosos(-dev)://oauth-callback#access_token=...&refresh_token=...&expires_in=3600&token_type=bearer&type=signup
    @discardableResult
    static func handle(url: URL, in navigation: UINavigationController?) -> Bool {
        guard let host = url.host?.lowercased(), host == "oauth-callback" else { return false }
        // Parse fragment as query parameters (type, access_token, refresh_token など)
        let fragment = url.fragment ?? ""
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0) }
            if kv.count == 2 { params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
        }
        // Also parse query string to supplement (e.g., flow=recovery)
        if let q = url.query, !q.isEmpty {
            for pair in q.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0) }
                if kv.count == 2, params[kv[0]] == nil { params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
        }

        // Deep link handling: for recovery flow, prioritize showing reset UI even if tokens are absent.
        Task { @MainActor in
            let flowType = (params["type"] ?? params["flow"])?.lowercased()
            // Try to recover session if tokens are present (does nothing if not)
            do { _ = try await SupabaseAuthAdapter.shared.client.auth.session(from: url) } catch {}
            await SupabaseAuthAdapter.shared.updateCachedToken()
            if flowType == "recovery" {
                let reset = ResetPasswordViewController()
                guard let nav = navigation else { return }
                nav.pushViewController(reset, animated: true)
                // After restoring session from deep link, try device registration
                PushRegistrationService.shared.ensureRegisteredIfPossible()
                return
            }
            // Non-recovery flows
            let hasSession = (SupabaseAuthAdapter.shared.accessToken != nil)
            if flowType == "signup" || flowType == "email_confirmation" {
                UserDefaults.standard.set(true, forKey: "ShouldShowRecipientsOnboardingOnce")
                UserDefaults.standard.set(true, forKey: "ShouldShowProfileOnboardingOnce")
            }
            if hasSession {
                let main = MainViewController()
                navigation?.setViewControllers([main], animated: true)
            } else {
                let signIn = SignInViewController()
                navigation?.setViewControllers([signIn], animated: true)
            }
            PushRegistrationService.shared.ensureRegisteredIfPossible()
        }
        return true
    }
}
