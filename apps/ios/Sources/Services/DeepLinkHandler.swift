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

        // Deep link handling: let Supabase SDK establish session from the URL
        Task { @MainActor in
            do {
                // Supabase Swift v2: recover session from redirect URL
                _ = try await SupabaseAuthAdapter.shared.client.auth.session(from: url)
                // Refresh cached token for APIClient headers
                await SupabaseAuthAdapter.shared.updateCachedToken()
                // Route by flow type
                let t = (params["type"] ?? params["flow"])?.lowercased()
                if t == "recovery" {
                    // Password reset flow: show reset UI
                    let reset = ResetPasswordViewController()
                    guard let nav = navigation else { return }
                    // push to keep back navigation natural
                    nav.pushViewController(reset, animated: true)
                } else {
                    // Signup/email confirmation etc: show main, enable onboarding flags
                    if t == "signup" || t == "email_confirmation" {
                        UserDefaults.standard.set(true, forKey: "ShouldShowRecipientsOnboardingOnce")
                        UserDefaults.standard.set(true, forKey: "ShouldShowProfileOnboardingOnce")
                    }
                    let main = MainViewController()
                    navigation?.setViewControllers([main], animated: true)
                }
                // After restoring session from deep link, try device registration
                PushRegistrationService.shared.ensureRegisteredIfPossible()
            } catch {
                // Even if session parsing fails, navigate to SignIn screen to avoid being stuck
                // and let the user proceed manually (e.g., password login after confirmation)
                let signIn = SignInViewController()
                if let nav = navigation {
                    nav.setViewControllers([signIn], animated: true)
                }
            }
        }
        return true
    }
}
