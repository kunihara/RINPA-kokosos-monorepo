import UIKit

final class TabRootController: UITabBarController {
    private let centerButton = UIButton(type: .system)
    private let leftItem = CustomTabItemView(title: "帰るモード", image: UIImage(systemName: "location.circle"))
    private let rightItem = CustomTabItemView(title: "設定", image: UIImage(systemName: "gearshape"))
    private let overlay = UIView()
    private let leftPad = UIControl()
    private let rightPad = UIControl()

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

        setupOverlay()
        setupCenterButton()
        setupCustomItems()
        updateCustomSelection()
    }

    private func setupOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = true
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: tabBar.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor)
        ])
        view.bringSubviewToFront(overlay)

        // 広いヒットエリアの透明パッドを左右に配置（中央SOSとのギャップを確保）
        leftPad.translatesAutoresizingMaskIntoConstraints = false
        rightPad.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(leftPad)
        overlay.addSubview(rightPad)
        leftPad.addTarget(self, action: #selector(tapLeft), for: .touchUpInside)
        rightPad.addTarget(self, action: #selector(tapRight), for: .touchUpInside)
        leftPad.isExclusiveTouch = true
        rightPad.isExclusiveTouch = true
        leftPad.layer.zPosition = 30 // アイコン/ラベル(80)より下、SOS(100)より下
        rightPad.layer.zPosition = 30
        NSLayoutConstraint.activate([
            leftPad.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            leftPad.trailingAnchor.constraint(equalTo: overlay.centerXAnchor, constant: -64),
            leftPad.topAnchor.constraint(equalTo: overlay.topAnchor),
            leftPad.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),

            rightPad.leadingAnchor.constraint(equalTo: overlay.centerXAnchor, constant: 64),
            rightPad.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            rightPad.topAnchor.constraint(equalTo: overlay.topAnchor),
            rightPad.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
        ])
        overlay.bringSubviewToFront(centerButton)
        overlay.bringSubviewToFront(leftItem)
        overlay.bringSubviewToFront(rightItem)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 内部のTabBarButtonが前面に来ることがあるため、カスタム項目と中央ボタンを常に最前面へ
        view.bringSubviewToFront(overlay)
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
        centerButton.layer.cornerRadius = 28
        centerButton.layer.shadowColor = UIColor.black.cgColor
        centerButton.layer.shadowOpacity = 0.2
        centerButton.layer.shadowRadius = 8
        centerButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        centerButton.addTarget(self, action: #selector(tapCenter), for: .touchUpInside)
        overlay.addSubview(centerButton)
        overlay.bringSubviewToFront(centerButton)
        overlay.clipsToBounds = false
        centerButton.isUserInteractionEnabled = true
        centerButton.layer.zPosition = 100

        NSLayoutConstraint.activate([
            centerButton.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            // SOSボタンもさらに下げてアーチと整合
            centerButton.centerYAnchor.constraint(equalTo: overlay.topAnchor, constant: 20),
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
        // ヒット領域は中央側を小さく、外側を大きく（中央ボタンとの競合回避）
        leftItem.hitOutsets = UIEdgeInsets(top: 18, left: 26, bottom: 18, right: 6)
        rightItem.hitOutsets = UIEdgeInsets(top: 18, left: 6, bottom: 18, right: 26)
        // z順で左右は中央の下、ただしタップは有効
        leftItem.layer.zPosition = 80
        rightItem.layer.zPosition = 80

        leftItem.translatesAutoresizingMaskIntoConstraints = false
        rightItem.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(leftItem)
        overlay.addSubview(rightItem)
        overlay.bringSubviewToFront(leftItem)
        overlay.bringSubviewToFront(rightItem)

        // 中央SOSボタンのヒット領域を確保するため、左右は中心から十分離す
        NSLayoutConstraint.activate([
            leftItem.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            leftItem.trailingAnchor.constraint(equalTo: overlay.centerXAnchor, constant: -64),
            leftItem.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 0),
            leftItem.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -24),

            rightItem.leadingAnchor.constraint(equalTo: overlay.centerXAnchor, constant: 64),
            rightItem.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            rightItem.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 0),
            rightItem.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -24),
        ])

        // 表示専用（タップは透明パッドで処理）
        leftItem.isUserInteractionEnabled = false
        rightItem.isUserInteractionEnabled = false
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
