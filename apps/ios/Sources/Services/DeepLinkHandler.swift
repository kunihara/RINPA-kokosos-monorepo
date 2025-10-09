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
            let supaError = (params["error_description"] ?? params["error"] ?? params["error_code"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let supaMessage = (params["message"] ?? params["msg"] ?? params["m"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            let tt = flowType ?? "nil"
            let fragStr = url.fragment ?? ""
            let queryStr = url.query ?? ""
            print("[DEBUG] DeepLink type=\(tt) urlFrag=#\(fragStr) query=?\(queryStr)")
            #endif
            // Apply session from URL only for interactive flows (recovery/magic/reauth)
            let canApplySession: Bool = {
                switch (flowType ?? "") {
                    case "recovery", "magic_link", "magiclink", "reauthentication", "reauth": return true
                    default: return false
                }
            }()
            if canApplySession {
                // 1) Try SDK helper (PKCE用). リカバリ等では失敗するため例外は握りつぶす
                try? await SupabaseAuthAdapter.shared.client.auth.session(from: url)
                // 2) Fragmentに access_token / refresh_token がある場合は手動で適用
                if let at = params["access_token"], let rt = params["refresh_token"], !at.isEmpty, !rt.isEmpty {
                    try? await SupabaseAuthAdapter.shared.client.auth.setSession(accessToken: at, refreshToken: rt)
                    #if DEBUG
                    print("[DEBUG] DeepLink setSession(access_token, refresh_token) applied (at.len=\(at.count), rt.len=\(rt.count))")
                    #endif
                }
            } else {
                #if DEBUG
                print("[DEBUG] DeepLink skip applying session for flow=\(flowType ?? "nil")")
                #endif
            }
            // Validate session server-side so that stale tokens don't slip through
            let ok = await SupabaseAuthAdapter.shared.validateOnline()
            #if DEBUG
            print("[DEBUG] DeepLink validateOnline=\(ok)")
            #endif
            // Heuristic: treat as recovery if explicit or if we only have a PKCE code in query and no fragment tokens
            let implicitRecovery = (url.query?.contains("code=") ?? false) && ((url.fragment ?? "").isEmpty)
            // Store possible recovery context (email/token) for fallback (verifyOTP)
            if (flowType == "recovery" || implicitRecovery) {
                let recEmail = params["email"] ?? params["user_email"]
                let recToken = params["token_hash"] ?? params["token"]
                RecoveryStore.shared.set(email: recEmail, token: recToken)
            } else {
                RecoveryStore.shared.clear()
            }
            if flowType == "recovery" || implicitRecovery {
                let reset = ResetPasswordViewController()
                guard let nav = navigation else { return }
            #if DEBUG
                print("[DEBUG] DeepLink push ResetPasswordViewController (implicit=\(implicitRecovery))")
            #endif
                nav.pushViewController(reset, animated: true)
                // Show informational or error message for recovery flow
                if let e = supaError, !e.isEmpty {
                    presentGlobalAlert(title: "リンクの処理に失敗", message: e, in: nav)
                } else {
                    let msg = supaMessage?.isEmpty == false ? supaMessage! : "パスワード再設定リンクを確認しました。新しいパスワードを入力してください。"
                    presentGlobalAlert(title: "メールを確認", message: msg, in: nav)
                }
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
                if let nav = navigation {
                    nav.goToSignIn(animated: true)
                }
            }
            // Surface success / error messages from Supabase for non-recovery flows
            if let nav = navigation {
                let (title, body) = buildSupabaseMessage(flowType: flowType, ok: (supaError == nil), errorText: supaError, messageText: supaMessage)
                if let t = title, let b = body { presentGlobalAlert(title: t, message: b, in: nav) }
            }
            PushRegistrationService.shared.ensureRegisteredIfPossible()
        }
        return true
    }

    // Build a user-facing message based on Supabase deep link params
    private static func buildSupabaseMessage(flowType: String?, ok: Bool, errorText: String?, messageText: String?) -> (String?, String?) {
        if let e = errorText, !e.isEmpty { return ("エラー", e) }
        if let m = messageText, !m.isEmpty { return ("完了", m) }
        let t = (flowType ?? "").lowercased()
        switch t {
        case "signup", "email_confirmation":
            return ("登録が完了", "メールアドレスの確認が完了しました。サインインできます。")
        case "invite":
            return ("招待が完了", "招待リンクを確認しました。アカウントが有効化されました。")
        case "magiclink", "magic_link":
            return ("サインイン完了", "メールのリンクからサインインしました。")
        case "reauthentication", "reauth":
            return ("再認証完了", "再認証が完了しました。続行できます。")
        case "email_change", "email_change_current":
            return ("確認完了", "現在のメールの確認が完了しました。新しいメールの確認も必要な場合があります。")
        case "email_change_new":
            return ("メール変更完了", "新しいメールアドレスの確認が完了しました。変更が反映されました。")
        default:
            // Unknown but successful
            if ok { return ("完了", "操作が完了しました。") }
            return (nil, nil)
        }
    }

    private static func presentGlobalAlert(title: String, message: String, in navigation: UINavigationController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        func topViewController(from vc: UIViewController?) -> UIViewController? {
            if let nav = vc as? UINavigationController { return topViewController(from: nav.visibleViewController) }
            if let tab = vc as? UITabBarController { return topViewController(from: tab.selectedViewController) }
            if let presented = vc?.presentedViewController { return topViewController(from: presented) }
            return vc
        }
        DispatchQueue.main.async {
            let root = navigation.view.window?.rootViewController
            let presenter = topViewController(from: root) ?? navigation.visibleViewController ?? navigation
            presenter.present(alert, animated: true)
        }
    }
}
