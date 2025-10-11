import UIKit

final class TabRootController: UITabBarController {
    private let centerButton = UIButton(type: .system)
    private let centerSOS = CenterSOSItemView()
    private let leftItem = CustomTabItemView(title: "帰るモード", image: UIImage(systemName: "location.circle"))
    private let rightItem = CustomTabItemView(title: "設定", image: UIImage(systemName: "gearshape"))
    private let overlay = UIView()
    private let leftPad = UIControl()
    private let rightPad = UIControl()
    private let tabBgView = TabBackgroundView()

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
        // 標準表示は完全に透過（重複や内部レイアウト補正の影響を避ける）
        emergency.tabBarItem = UITabBarItem(title: "", image: clearImage(), selectedImage: clearImage())

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "", image: clearImage(), selectedImage: clearImage())

        viewControllers = [home, emergency, settings]

        setupOverlay()
        setupCenterButton()
        setupCenterSOS()
        setupCustomItems()
        // 初期選択状態の反映
        updateCustomSelection()
    }

    private func setupOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .clear
        // overlayは左右の位置決めのためだけに保持し、タッチは通す
        overlay.isUserInteractionEnabled = false
        // tabBar直下に配置して同一座標系で追従させる
        tabBar.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: tabBar.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor)
        ])
        tabBar.bringSubviewToFront(overlay)

        // 背景はCustomTabBarが描画するためoverlayでは描画しない

        // 左右はtabBar直下に配置するためoverlayでは操作しない
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 内部のTabBarButtonが前面に来ることがあるため、カスタム項目と中央ボタンを常に最前面へ
        // overlay（左右）と中央ボタンの順序を明示（中央ボタンを最前面へ）
        tabBar.bringSubviewToFront(overlay)
        tabBar.bringSubviewToFront(centerSOS)
        if let bar = self.tabBar as? CustomTabBar { bar.setNeedsLayout(); bar.layoutIfNeeded() }
        // 背景同期は不要
        // 既存の標準タブボタンはタップを無効化（カスタムで扱う）
        for v in tabBar.subviews {
            if NSStringFromClass(type(of: v)).contains("UITabBarButton") {
                v.isUserInteractionEnabled = false
            }
        }
    }

    private func setupCenterButton() {
        centerButton.translatesAutoresizingMaskIntoConstraints = false
        centerButton.backgroundColor = .white
        // I'm Safe画面と同じベルアイコンを使用
        let bell = UIImage(systemName: "bell.and.waveform") ?? UIImage(systemName: "bell.fill")
        centerButton.setImage(bell, for: .normal)
        centerButton.tintColor = .kokoRed
        centerButton.layer.cornerRadius = 32
        centerButton.layer.shadowColor = UIColor.black.cgColor
        centerButton.layer.shadowOpacity = 0.2
        centerButton.layer.shadowRadius = 8
        centerButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        centerButton.addTarget(self, action: #selector(tapCenter), for: .touchUpInside)
        tabBar.addSubview(centerButton)
        tabBar.bringSubviewToFront(centerButton)
        tabBar.clipsToBounds = false
        centerButton.isUserInteractionEnabled = true
        centerButton.layer.zPosition = 100

        NSLayoutConstraint.activate([
            centerButton.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            // アーチ中心に合わせる（CustomTabBar.archYOffset=24）
            centerButton.centerYAnchor.constraint(equalTo: tabBar.topAnchor, constant: 24),
            centerButton.widthAnchor.constraint(equalToConstant: 64),
            centerButton.heightAnchor.constraint(equalToConstant: 64),
        ])
        centerButton.layer.cornerRadius = 32
    }

    private func setupCenterSOS() {
        centerSOS.translatesAutoresizingMaskIntoConstraints = false
        centerSOS.archRadius = 48
        centerSOS.archCenterOffset = 24
        centerSOS.circleSize = 64
        centerSOS.addTarget(self, action: #selector(tapCenter), for: .touchUpInside)
        tabBar.addSubview(centerSOS)
        NSLayoutConstraint.activate([
            centerSOS.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            centerSOS.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            centerSOS.topAnchor.constraint(equalTo: tabBar.topAnchor),
            centerSOS.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor)
        ])
        // 旧ボタンは視覚上は隠す（段階移行のため残す）
        centerButton.isHidden = true
    }

    @objc private func tapCenter() {
        // Haptics and select middle tab (emergency)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred()
        selectedIndex = 1
        // Small tap animation
        UIView.animate(withDuration: 0.08, animations: {
            self.centerSOS.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.centerSOS.transform = .identity
            }
        }
        updateCustomSelection()
    }

    private func setupCustomItems() {
        leftItem.selectedTintColor = .label
        leftItem.normalTintColor = .secondaryLabel
        rightItem.selectedTintColor = .label
        rightItem.normalTintColor = .secondaryLabel
        // ヒット領域は中央側を小さく、外側を大きく（中央ボタンとの競合回避）
        leftItem.hitOutsets = UIEdgeInsets(top: 18, left: 26, bottom: 18, right: 6)
        rightItem.hitOutsets = UIEdgeInsets(top: 18, left: 6, bottom: 18, right: 26)
        // z順で左右は中央の下、ただしタップは有効
        leftItem.layer.zPosition = 80
        rightItem.layer.zPosition = 80

        leftItem.translatesAutoresizingMaskIntoConstraints = false
        rightItem.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(leftItem)
        tabBar.addSubview(rightItem)
        tabBar.bringSubviewToFront(leftItem)
        tabBar.bringSubviewToFront(rightItem)

        // 中央SOSボタンのヒット領域を確保するため、左右は中心から十分離す
        NSLayoutConstraint.activate([
            leftItem.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 8),
            leftItem.trailingAnchor.constraint(equalTo: tabBar.centerXAnchor, constant: -64),
            leftItem.topAnchor.constraint(equalTo: tabBar.topAnchor),
            leftItem.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

            rightItem.leadingAnchor.constraint(equalTo: tabBar.centerXAnchor, constant: 64),
            rightItem.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -8),
            rightItem.topAnchor.constraint(equalTo: tabBar.topAnchor),
            rightItem.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
        ])

        // 直接タップで切替（overlayパッド非依存）
        leftItem.isUserInteractionEnabled = true
        rightItem.isUserInteractionEnabled = true
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
        // SOS(中央)の見た目: アクティブ時=赤ベタ+白アイコン / 非アクティブ時=白ベタ+赤アウトライン
        let isActive = (selectedIndex == 1)
        centerSOS.applyActiveStyle(isActive)
        if let bar = self.tabBar as? CustomTabBar { bar.isCenterActive = isActive }
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
