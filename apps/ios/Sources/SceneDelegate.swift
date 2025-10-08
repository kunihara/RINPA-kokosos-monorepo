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
    if let url = connectionOptions.urlContexts.first?.url {
      didHandleDeepLink = DeepLinkHandler.handle(url: url, in: root)
    }
    // Decide initial root after loading persisted session
    Task { @MainActor in
      // Validate session with server (401/invalid will clear token)
      _ = await SupabaseAuthAdapter.shared.validateOnline()
      // If deep link already pushed ResetPassword, do not override the stack
      if didHandleDeepLink, let top = root.viewControllers.last, top is ResetPasswordViewController {
        PushRegistrationService.shared.ensureRegisteredIfPossible()
        return
      }
      // Decide initial root strictly by current Supabase session presence
      let has = (SupabaseAuthAdapter.shared.accessToken != nil)
      let target = has ? MainViewController() : SignInViewController()
      root.setViewControllers([target], animated: false)
      if has { PushRegistrationService.shared.ensureRegisteredIfPossible() }
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
