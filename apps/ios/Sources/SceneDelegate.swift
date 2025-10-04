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
    }
}
