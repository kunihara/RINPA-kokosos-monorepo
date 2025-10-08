import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    // 一旦プレースホルダを表示し、非同期にセッションを確認してから初期画面を決定
    let placeholder = UIViewController()
    placeholder.view.backgroundColor = .systemBackground
    let root = UINavigationController(rootViewController: placeholder)
    window.rootViewController = root
    window.makeKeyAndVisible()
    self.window = window

    // Handle URL if app launched via deep link
    var didHandleDeepLink = false
    var isRecoveryLaunch = false
    if let url = connectionOptions.urlContexts.first?.url {
      // Detect recovery in query or fragment (type/flow)
      let frag = url.fragment ?? ""
      let que = url.query ?? ""
      let hasRecoveryInFrag = frag.contains("type=recovery") || frag.contains("flow=recovery")
      let hasRecoveryInQuery = que.contains("type=recovery") || que.contains("flow=recovery")
      isRecoveryLaunch = hasRecoveryInFrag || hasRecoveryInQuery
      DLog("launchURL=\(url.absoluteString.prefix(200)) isRecovery=\(isRecoveryLaunch)")
      didHandleDeepLink = DeepLinkHandler.handle(url: url, in: root)
      DLog("didHandleDeepLink=\(didHandleDeepLink)")
    }
    // Decide initial root after loading persisted session
    Task { @MainActor in
      // Policy: 初回起動かつローカルにSupabaseセッションが存在する場合は、前回インストールの残骸とみなし一度サインアウト
      let firstRun = (UserDefaults.standard.string(forKey: "InstallSentinel") == nil)
      if firstRun && !isRecoveryLaunch {
        DLog("firstRun=true & non-recovery: signing out any residual session")
        if let _ = try? await SupabaseAuthAdapter.shared.client.auth.session {
          try? await SupabaseAuthAdapter.shared.client.auth.signOut()
          await SupabaseAuthAdapter.shared.updateCachedToken()
        }
      }
      // Validate session with server (401/invalid will clear token)
      let valid = await SupabaseAuthAdapter.shared.validateOnline()
      DLog("validateOnline=\(valid)")
      // If deep link already pushed ResetPassword, do not override the stack
      if didHandleDeepLink, let top = root.viewControllers.last, top is ResetPasswordViewController {
        DLog("keep ResetPassword on stack; skip root override")
        PushRegistrationService.shared.ensureRegisteredIfPossible()
        return
      }
      // Decide initial root by validated session presence only
      let has = (SupabaseAuthAdapter.shared.accessToken != nil)
      DLog("routeInitial hasSession=\(has)")
      let target = has ? MainViewController() : SignInViewController()
      root.setViewControllers([target], animated: false)
      if has { PushRegistrationService.shared.ensureRegisteredIfPossible() }
      // After routing, align install sentinel across storages
      InstallGuard.ensureSentinel()
    }
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let nav = (window?.rootViewController as? UINavigationController) else { return }
    for context in URLContexts {
      if DeepLinkHandler.handle(url: context.url, in: nav) { return }
    }
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    // アプリ復帰時にトークンが間もなく失効なら静かに更新
    Task { @MainActor in
      _ = await SupabaseAuthAdapter.shared.refresh()
    }
    // After refresh, if signed in, ensure device registration
    PushRegistrationService.shared.ensureRegisteredIfPossible()
  }
}
