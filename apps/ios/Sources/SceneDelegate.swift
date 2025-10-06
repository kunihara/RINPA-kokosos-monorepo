import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    let rootVC: UIViewController
    let api = APIClient()
    if api.currentAuthToken() != nil {
      rootVC = MainViewController()
    } else {
      // 初回はサインイン画面を表示
      rootVC = SignInViewController()
    }
    let root = UINavigationController(rootViewController: rootVC)
    window.rootViewController = root
    window.makeKeyAndVisible()
    self.window = window

    // Handle URL if app launched via deep link
    if let url = connectionOptions.urlContexts.first?.url {
      _ = DeepLinkHandler.handle(url: url, in: root)
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
      let api = APIClient()
      if api.currentRefreshToken() != nil {
        // しきい値は 2 分前
        _ = await AuthClient.performRefreshAndStore()
      }
    }
  }
}
