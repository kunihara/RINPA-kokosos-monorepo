import UIKit

final class TabRootController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let home = UINavigationController(rootViewController: HomeModeViewController())
        home.tabBarItem = UITabBarItem(title: "帰るモード", image: UIImage(systemName: "house.fill"), selectedImage: UIImage(systemName: "house.fill"))

        let emergency = UINavigationController(rootViewController: MainViewController())
        emergency.tabBarItem = UITabBarItem(title: "緊急モード(SOS)", image: UIImage(systemName: "exclamationmark.triangle.fill"), selectedImage: UIImage(systemName: "exclamationmark.triangle.fill"))

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "設定", image: UIImage(systemName: "gearshape.fill"), selectedImage: UIImage(systemName: "gearshape.fill"))

        viewControllers = [home, emergency, settings]
    }
}

