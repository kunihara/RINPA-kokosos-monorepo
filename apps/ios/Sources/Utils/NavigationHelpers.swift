import UIKit

extension UINavigationController {
    func goToSignIn(animated: Bool) {
        if let idx = viewControllers.firstIndex(where: { $0 is SignInViewController }) {
            popToViewController(viewControllers[idx], animated: animated)
        } else {
            setViewControllers([SignInViewController()], animated: animated)
        }
    }
}

