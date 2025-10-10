import UIKit

final class TabRootController: UITabBarController {
    private let centerButton = UIButton(type: .system)
    private let leftItem = CustomTabItemView(title: "帰るモード", image: UIImage(systemName: "location.circle"))
    private let rightItem = CustomTabItemView(title: "設定", image: UIImage(systemName: "bell.badge"))

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
        // アイコンとタイトルを同時にさらに下へ移動（相対距離は維持）
        let offsetY: CGFloat = 2
        appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.inlineLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.inlineLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.compactInlineLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        appearance.compactInlineLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offsetY)
        self.tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            self.tabBar.scrollEdgeAppearance = appearance
        }

        let home = UINavigationController(rootViewController: HomeModeViewController())
        // 標準のタイトルは空にして、見た目はカスタム項目で表示
        home.tabBarItem = UITabBarItem(title: "", image: UIImage(systemName: "location.circle"), selectedImage: UIImage(systemName: "location.circle.fill"))

        let emergency = UINavigationController(rootViewController: MainViewController())
        emergency.tabBarItem = UITabBarItem(title: "緊急モード", image: UIImage(systemName: "phone.down.circle"), selectedImage: UIImage(systemName: "phone.down.circle.fill"))
        emergency.tabBarItem.imageInsets = UIEdgeInsets(top: 30, left: 0, bottom: -30, right: 0)

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "", image: UIImage(systemName: "bell.badge"), selectedImage: UIImage(systemName: "bell.badge.fill"))

        viewControllers = [home, emergency, settings]

        setupCenterButton()
        setupCustomItems()
        updateCustomSelection()
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
        updateCustomSelection()
    }

    private func setupCustomItems() {
        leftItem.selectedTintColor = .label
        leftItem.normalTintColor = .secondaryLabel
        rightItem.selectedTintColor = .label
        rightItem.normalTintColor = .secondaryLabel

        leftItem.translatesAutoresizingMaskIntoConstraints = false
        rightItem.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(leftItem)
        tabBar.addSubview(rightItem)
        tabBar.bringSubviewToFront(leftItem)
        tabBar.bringSubviewToFront(rightItem)

        NSLayoutConstraint.activate([
            leftItem.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 22),
            leftItem.trailingAnchor.constraint(equalTo: tabBar.centerXAnchor, constant: -60),
            leftItem.bottomAnchor.constraint(equalTo: tabBar.safeAreaLayoutGuide.bottomAnchor, constant: -10),

            rightItem.leadingAnchor.constraint(equalTo: tabBar.centerXAnchor, constant: 60),
            rightItem.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -22),
            rightItem.bottomAnchor.constraint(equalTo: tabBar.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])

        leftItem.addTarget(self, action: #selector(tapLeft), for: .touchUpInside)
        rightItem.addTarget(self, action: #selector(tapRight), for: .touchUpInside)
    }

    @objc private func tapLeft() {
        selectedIndex = 0
        updateCustomSelection()
    }

    @objc private func tapRight() {
        selectedIndex = 2
        updateCustomSelection()
    }

    private func updateCustomSelection() {
        leftItem.isSelected = (selectedIndex == 0)
        rightItem.isSelected = (selectedIndex == 2)
    }
}
