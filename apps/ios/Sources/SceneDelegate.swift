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
}
