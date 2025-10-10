import UIKit

final class TabRootController: UITabBarController {
    private let centerButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Replace default tab bar with custom one
        let customBar = CustomTabBar()
        setValue(customBar, forKey: "tabBar")
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.clipsToBounds = false

        // 調整: 文字位置をわずかに下げ、アイコンが高く見えないようにする
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        // アイコン/タイトルをまとめて下方向へオフセット（白背景内に収める）
        let offsetY: CGFloat = 5
        // stacked（通常のタブ表示）
        appearance.stackedLayoutAppearance.normal.iconPositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.stackedLayoutAppearance.selected.iconPositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        // inline/compactInline（iPadや横向きなど）にも適用
        appearance.inlineLayoutAppearance.normal.iconPositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.inlineLayoutAppearance.selected.iconPositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.inlineLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.inlineLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.compactInlineLayoutAppearance.normal.iconPositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.compactInlineLayoutAppearance.selected.iconPositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.compactInlineLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.compactInlineLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        self.tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            self.tabBar.scrollEdgeAppearance = appearance
        }

        let home = UINavigationController(rootViewController: HomeModeViewController())
        home.tabBarItem = UITabBarItem(title: "帰るモード", image: UIImage(systemName: "location.circle"), selectedImage: UIImage(systemName: "location.circle.fill"))

        let emergency = UINavigationController(rootViewController: MainViewController())
        emergency.tabBarItem = UITabBarItem(title: "緊急モード", image: UIImage(systemName: "phone.down.circle"), selectedImage: UIImage(systemName: "phone.down.circle.fill"))

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "設定", image: UIImage(systemName: "bell.badge"), selectedImage: UIImage(systemName: "bell.badge.fill"))

        viewControllers = [home, emergency, settings]

        setupCenterButton()
    }

    private func setupCenterButton() {
        centerButton.translatesAutoresizingMaskIntoConstraints = false
        centerButton.backgroundColor = .white
        // I'm Safe画面と同じベルアイコンを使用
        let bell = UIImage(systemName: "bell.and.waveform") ?? UIImage(systemName: "bell.fill")
        centerButton.setImage(bell, for: .normal)
        centerButton.tintColor = .systemRed
        centerButton.layer.cornerRadius = 28
        centerButton.layer.shadowColor = UIColor.black.cgColor
        centerButton.layer.shadowOpacity = 0.2
        centerButton.layer.shadowRadius = 8
        centerButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        centerButton.addTarget(self, action: #selector(tapCenter), for: .touchUpInside)
        tabBar.addSubview(centerButton)
        tabBar.bringSubviewToFront(centerButton)
        tabBar.clipsToBounds = false

        NSLayoutConstraint.activate([
            centerButton.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            // タブ全体を高くしたので突出量をさらに抑制
            centerButton.centerYAnchor.constraint(equalTo: tabBar.topAnchor, constant: 10),
            centerButton.widthAnchor.constraint(equalToConstant: 56),
            centerButton.heightAnchor.constraint(equalToConstant: 56),
        ])
        centerButton.layer.cornerRadius = 28
    }

    @objc private func tapCenter() {
        // Haptics and select middle tab (emergency)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred()
        selectedIndex = 1
        // Small tap animation
        UIView.animate(withDuration: 0.08, animations: {
            self.centerButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.centerButton.transform = .identity
            }
        }
    }
}
