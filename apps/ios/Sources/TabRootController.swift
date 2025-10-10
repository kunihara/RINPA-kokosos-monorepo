import UIKit

final class TabRootController: UITabBarController {
    private let centerButton = UIButton(type: .system)
    private let leftItem = CustomTabItemView(title: "帰るモード", image: UIImage(systemName: "location.circle"))
    private let rightItem = CustomTabItemView(title: "設定", image: UIImage(systemName: "gearshape"))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Replace default tab bar with custom one
        let customBar = CustomTabBar()
        setValue(customBar, forKey: "tabBar")
        // SOSの赤アーチをさらに下へ
        customBar.archYOffset = 24
        // 標準アイテムは見せないため、色はクリア（オーバーレイで表示）
        tabBar.tintColor = .clear
        tabBar.unselectedItemTintColor = .clear
        tabBar.clipsToBounds = false

        // 調整: 標準タイトルは描画しない（オーバーレイで表示）
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        let clearAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = clearAttrs
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = clearAttrs
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = clearAttrs
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = clearAttrs
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = clearAttrs
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = clearAttrs
        self.tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            self.tabBar.scrollEdgeAppearance = appearance
        }

        let home = UINavigationController(rootViewController: HomeModeViewController())
        // 標準表示は完全に透過（重複を避ける）
        home.tabBarItem = UITabBarItem(title: "", image: clearImage(), selectedImage: clearImage())

        let emergency = UINavigationController(rootViewController: MainViewController())
        emergency.tabBarItem = UITabBarItem(title: "緊急モード", image: UIImage(systemName: "phone.down.circle"), selectedImage: UIImage(systemName: "phone.down.circle.fill"))
        emergency.tabBarItem.imageInsets = UIEdgeInsets(top: 30, left: 0, bottom: -30, right: 0)

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "", image: clearImage(), selectedImage: clearImage())

        viewControllers = [home, emergency, settings]

        setupCenterButton()
        setupCustomItems()
        updateCustomSelection()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 内部のTabBarButtonが前面に来ることがあるため、カスタム項目と中央ボタンを常に最前面へ
        tabBar.bringSubviewToFront(centerButton)
        tabBar.bringSubviewToFront(leftItem)
        tabBar.bringSubviewToFront(rightItem)
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
            // SOSボタンもさらに下げてアーチと整合
            centerButton.centerYAnchor.constraint(equalTo: tabBar.topAnchor, constant: 20),
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
        // ヒット領域をさらに広げる
        leftItem.extraHitOutset = 24
        rightItem.extraHitOutset = 24

        leftItem.translatesAutoresizingMaskIntoConstraints = false
        rightItem.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(leftItem)
        tabBar.addSubview(rightItem)
        tabBar.bringSubviewToFront(leftItem)
        tabBar.bringSubviewToFront(rightItem)

        // 横幅をさらに拡大（中央との隙間を詰める）
        NSLayoutConstraint.activate([
            leftItem.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 6),
            leftItem.trailingAnchor.constraint(equalTo: tabBar.centerXAnchor, constant: -20),
            leftItem.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: 0),
            // さらに上げる（-18pt）
            leftItem.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: -18),

            rightItem.leadingAnchor.constraint(equalTo: tabBar.centerXAnchor, constant: 20),
            rightItem.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -6),
            rightItem.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: 0),
            rightItem.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: -18),
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

    // 1x1の透明画像（標準アイコンを不可視化するために使用）
    private func clearImage() -> UIImage {
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
}
