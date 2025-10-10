import UIKit
import CoreLocation

final class MainViewController: UIViewController {
    private let titleLabel = UILabel()
    private let headlineLabel = UILabel()
    private let subLabel = UILabel()
    private let startEmergencyButton = UIButton(type: .system)
    private let sosBackdrop = UIView()
    private var sosBackdropW: NSLayoutConstraint!
    private var sosBackdropH: NSLayoutConstraint!
    private let sosInitialSize: CGFloat = 280
    #if DEBUG
    private let debugAnimateOnlySOS = true
    #else
    private let debugAnimateOnlySOS = false
    #endif
    // Fallback overlay for robust animation (frame-based)
    private var sosOverlay: UIView?
    private var sosFullView: UIView?
    private var sosLayer: CAShapeLayer?
    private let statusLabel = UILabel()
    private let controlsStack = UIStackView()
    private let stopButton = UIButton(type: .system)
    private let revokeButton = UIButton(type: .system)
    private let extendButton = UIButton(type: .system)
    private let countdownView = UILabel()
    private var countdownTimer: Timer?
    private var updateTimer: Timer?
    private var reminderTimer: Timer?
    private var remaining = 0
    private let locationService = LocationService()
    private let bgTracker = BackgroundLocationTracker()
    private let api = APIClient()
    private let contactsClient = ContactsClient()
    private var selectedRecipients: [String] = [] { didSet { updateRecipientsChip() } }
    private let recipientsButton = UIButton(type: .system)
    // 画面下部に表示する受信者バッジ
    private let recipientsBadge = UIView()
    private let recipientsBadgeIcon = UIImageView()
    private let recipientsBadgeLabel = UILabel()
    private var session: AlertSession? { didSet { updateControls() } }
    private var didAutoShowOnboarding = false
    private let updateIntervalSec: TimeInterval = 60 // 1〜5分の範囲で調整可（ここは1分）
    private var reminderIntervalSec: TimeInterval { TimeInterval(SettingsStore.shared.arrivalReminderMinutes * 60) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(onSettingsChanged), name: SettingsStore.changedNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Guard against phantom sessions: validate with server; if invalid, force back to SignIn
        Task { @MainActor in
            let ok = await SupabaseAuthAdapter.shared.validateOnline()
            #if DEBUG
            print("[DEBUG] MainView appear validateOnline=\(ok)")
            #endif
            if !ok {
                self.navigationController?.goToSignIn(animated: true)
                return
            }
        }
        // プロフィールオンボーディング（初回1回だけ）
        if UserDefaults.standard.bool(forKey: "ShouldShowProfileOnboardingOnce"), presentedViewController == nil {
            UserDefaults.standard.set(false, forKey: "ShouldShowProfileOnboardingOnce")
            let vc = ProfileEditViewController()
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        // 1) サインアップ直後のワンショット誘導
        let onceKey = "ShouldShowRecipientsOnboardingOnce"
        if UserDefaults.standard.bool(forKey: onceKey), presentedViewController == nil {
            UserDefaults.standard.set(false, forKey: onceKey)
            let vc = ContactsPickerViewController()
            let nav = UINavigationController(rootViewController: vc)
            present(nav, animated: true)
            return
        }
        // 2) 送信に必要な「検証済みの受信者」が0件なら常に誘導
        if presentedViewController == nil && !didAutoShowOnboarding {
            Task { @MainActor in
                do {
                    let items = try await ContactsClient().list(status: "verified")
                    if items.isEmpty {
                        didAutoShowOnboarding = true
                        let vc = ContactsPickerViewController()
                        let nav = UINavigationController(rootViewController: vc)
                        present(nav, animated: true)
                    } else if self.selectedRecipients.isEmpty {
                        // 初回や未選択時は、検証済みの受信者を自動選択
                        self.selectedRecipients = items.map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    }
                } catch {
                    // 失敗時は誘導しない（次回以降に再評価）
                }
            }
        }
    }

    private func setupUI() {
        titleLabel.text = "Home"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Headline
        headlineLabel.text = "Are you in an\nemergency?"
        headlineLabel.numberOfLines = 0
        headlineLabel.textAlignment = .center
        headlineLabel.font = .systemFont(ofSize: 24, weight: .heavy)
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        subLabel.text = "Press the button below and help will\nreach you shortly."
        subLabel.numberOfLines = 0
        subLabel.textAlignment = .center
        subLabel.textColor = .secondaryLabel
        subLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        // SOS button (large circle)
        startEmergencyButton.setTitle("SOS", for: .normal)
        startEmergencyButton.addTarget(self, action: #selector(tapStartEmergency), for: .touchUpInside)
        startEmergencyButton.translatesAutoresizingMaskIntoConstraints = false
        startEmergencyButton.titleLabel?.font = .boldSystemFont(ofSize: 40)
        startEmergencyButton.setTitleColor(.white, for: .normal)
        startEmergencyButton.backgroundColor = UIColor.kokoRed
        startEmergencyButton.layer.shadowColor = UIColor.kokoRed.cgColor
        startEmergencyButton.layer.shadowOpacity = 0.35
        startEmergencyButton.layer.shadowRadius = 16
        startEmergencyButton.layer.shadowOffset = CGSize(width: 0, height: 8)

        sosBackdrop.translatesAutoresizingMaskIntoConstraints = false
        sosBackdrop.backgroundColor = UIColor.kokoRed.withAlphaComponent(0.15)
        sosBackdrop.alpha = 0.3
        if #available(iOS 13.0, *) {
            sosBackdrop.layer.cornerCurve = .continuous
        }

        // 帰るモード開始は緊急タブから削除（帰るモードは専用タブへ）

        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        countdownView.textAlignment = .center
        countdownView.font = .boldSystemFont(ofSize: 40)
        countdownView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        countdownView.textColor = .white
        countdownView.layer.cornerRadius = 12
        countdownView.layer.masksToBounds = true
        countdownView.isHidden = true
        countdownView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(headlineLabel)
        view.addSubview(subLabel)
        view.addSubview(sosBackdrop)
        view.addSubview(startEmergencyButton)
        // 確実にボタンが前面、バックドロップが背面になるように調整
        sosBackdrop.layer.zPosition = -1
        view.bringSubviewToFront(startEmergencyButton)
        view.addSubview(statusLabel)
        view.addSubview(countdownView)
        recipientsButton.setTitle("受信者: 0名", for: .normal)
        recipientsButton.addTarget(self, action: #selector(tapRecipients), for: .touchUpInside)
        recipientsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recipientsButton)
        controlsStack.axis = .horizontal
        controlsStack.spacing = 12
        controlsStack.alignment = .center
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        revokeButton.setTitle("即時失効", for: .normal)
        revokeButton.addTarget(self, action: #selector(tapRevoke), for: .touchUpInside)
        // SOS画面から「停止」ボタンは削除。必要なら即時失効のみ残す。
        controlsStack.addArrangedSubview(revokeButton)
        view.addSubview(controlsStack)
        // 設定はタブで提供、サインアウトは設定タブに移動（本画面のバーアイテムは設置しない）

        // 受信者バッジ（画面左下）
        recipientsBadge.translatesAutoresizingMaskIntoConstraints = false
        recipientsBadge.backgroundColor = .systemBackground
        recipientsBadge.layer.cornerRadius = 14
        recipientsBadge.layer.shadowColor = UIColor.black.cgColor
        recipientsBadge.layer.shadowOpacity = 0.12
        recipientsBadge.layer.shadowRadius = 8
        recipientsBadge.layer.shadowOffset = CGSize(width: 0, height: 4)
        recipientsBadge.isHidden = true
        recipientsBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
        recipientsBadgeIcon.image = UIImage(systemName: "person.crop.circle")
        recipientsBadgeIcon.tintColor = .systemGray
        recipientsBadgeIcon.contentMode = .scaleAspectFit
        recipientsBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        recipientsBadgeLabel.text = "受信者: 0名"
        recipientsBadgeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        recipientsBadgeLabel.textColor = .label
        recipientsBadge.addSubview(recipientsBadgeIcon)
        recipientsBadge.addSubview(recipientsBadgeLabel)
        view.addSubview(recipientsBadge)

        // Prepare constraints for animated sizing of SOS backdrop
        sosBackdropW = sosBackdrop.widthAnchor.constraint(equalToConstant: sosInitialSize)
        sosBackdropH = sosBackdrop.heightAnchor.constraint(equalToConstant: sosInitialSize)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            headlineLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            headlineLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            subLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // keep references to animate size
            sosBackdropW,
            sosBackdropH,
            sosBackdrop.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sosBackdrop.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            startEmergencyButton.widthAnchor.constraint(equalToConstant: 220),
            startEmergencyButton.heightAnchor.constraint(equalToConstant: 220),
            startEmergencyButton.centerXAnchor.constraint(equalTo: sosBackdrop.centerXAnchor),
            startEmergencyButton.centerYAnchor.constraint(equalTo: sosBackdrop.centerYAnchor),

            recipientsButton.topAnchor.constraint(equalTo: startEmergencyButton.bottomAnchor, constant: 20),
            recipientsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: recipientsButton.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            controlsStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            controlsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            countdownView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            countdownView.widthAnchor.constraint(equalToConstant: 160),
            countdownView.heightAnchor.constraint(equalToConstant: 100),

            recipientsBadge.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            recipientsBadge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            recipientsBadgeIcon.leadingAnchor.constraint(equalTo: recipientsBadge.leadingAnchor, constant: 10),
            recipientsBadgeIcon.centerYAnchor.constraint(equalTo: recipientsBadge.centerYAnchor),
            recipientsBadgeIcon.widthAnchor.constraint(equalToConstant: 24),
            recipientsBadgeIcon.heightAnchor.constraint(equalToConstant: 24),
            recipientsBadgeLabel.leadingAnchor.constraint(equalTo: recipientsBadgeIcon.trailingAnchor, constant: 8),
            recipientsBadgeLabel.trailingAnchor.constraint(equalTo: recipientsBadge.trailingAnchor, constant: -12),
            recipientsBadgeLabel.topAnchor.constraint(equalTo: recipientsBadge.topAnchor, constant: 8),
            recipientsBadgeLabel.bottomAnchor.constraint(equalTo: recipientsBadge.bottomAnchor, constant: -8)
        ])
    }

    private func showAlert(_ title: String, _ msg: String) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    private func updateRecipientsChip() {
        let count = selectedRecipients.count
        recipientsButton.setTitle("受信者: \(count)名", for: .normal)
        // 永続化して他画面と共有
        UserDefaults.standard.set(selectedRecipients, forKey: "SelectedRecipientsEmails")
        // バッジ表示も更新
        if count > 0 {
            recipientsBadge.isHidden = false
            let first = selectedRecipients.first ?? ""
            let text: String
            if count == 1 {
                text = first
            } else {
                text = "\(first) ほか\(count-1)人"
            }
            recipientsBadgeLabel.text = text
        } else {
            recipientsBadge.isHidden = true
        }
    }

    @objc private func tapStartEmergency() {
        // 先にアニメーションを開始
        animateSOSExpand()
        // デバッグ中はアニメーションのみ確認
        if debugAnimateOnlySOS { return }
        startFlow(type: "emergency")
    }

    // 帰るモード開始は専用タブ（HomeModeViewController）で提供する

    private func startFlow(type: String) {
        presentCountdown(seconds: 3) { [weak self] in
            self?.kickoff(type: type)
        }
    }

    private func presentCountdown(seconds: Int, completion: @escaping () -> Void) {
        remaining = seconds
        countdownView.isHidden = false
        countdownView.text = "開始まで: \(remaining)"
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                countdownView.isHidden = true
                completion()
            } else {
                countdownView.text = "開始まで: \(remaining)"
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 丸ボタンの角丸をレイアウト後に適用
        startEmergencyButton.layer.cornerRadius = startEmergencyButton.bounds.height / 2
        sosBackdrop.layer.cornerRadius = sosBackdrop.bounds.height / 2
        if #available(iOS 13.0, *) {
            startEmergencyButton.layer.cornerCurve = .continuous
            sosBackdrop.layer.cornerCurve = .continuous
        }
    }

    // MARK: - SOS Animation
    private func animateSOSExpand() {
        #if DEBUG
        print("[DEBUG] animateSOSExpand")
        #endif
        // Haptic feedback for emphasis
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // 単一方式で描画の競合を避けるため、オーバーレイ方式のみを使用
        animateSOSExpandOverlay()
        // ボタン自体の軽いスケールで押下感を出す
        UIView.animate(withDuration: 0.12, animations: {
            self.startEmergencyButton.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }) { _ in
            UIView.animate(withDuration: 0.18) {
                self.startEmergencyButton.transform = .identity
            }
        }
        startEmergencyButton.setTitle("停止", for: .normal)
        startEmergencyButton.removeTarget(self, action: #selector(tapStartEmergency), for: .touchUpInside)
        startEmergencyButton.addTarget(self, action: #selector(tapStop), for: .touchUpInside)
    }

    private func animateSOSCollapse() {
        #if DEBUG
        print("[DEBUG] animateSOSCollapse")
        #endif

        // 3段階: 1) フル画面UIをフェード → 2) 赤オーバーレイを縮小しながらフェード → 3) 元の背景/ボタンに戻す

        func restoreBackgroundAndButton() {
            // 背景円は一気に元のサイズへ（重ねアニメでのカクつきを避ける）
            self.sosBackdropW.constant = self.sosInitialSize
            self.sosBackdropH.constant = self.sosInitialSize
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
                self.sosBackdrop.alpha = 0.3
                self.sosBackdrop.layer.cornerRadius = self.sosInitialSize / 2
            }
            self.startEmergencyButton.setTitle("SOS", for: .normal)
            self.startEmergencyButton.removeTarget(self, action: #selector(self.tapStop), for: .touchUpInside)
            self.startEmergencyButton.addTarget(self, action: #selector(self.tapStartEmergency), for: .touchUpInside)
        }

        func collapseOverlayThenRestore() {
            if let overlay = self.sosOverlay {
                // 拡大の完全な逆アニメーション（同じduration/curve、アルファ変更なし）
                self.sosBackdrop.isHidden = true
                UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut], animations: {
                    overlay.transform = .identity
                }, completion: { _ in
                    overlay.removeFromSuperview()
                    self.sosOverlay = nil
                    self.sosBackdrop.isHidden = false
                    restoreBackgroundAndButton()
                })
            } else {
                restoreBackgroundAndButton()
            }
        }

        if let full = sosFullView {
            UIView.animate(withDuration: 0.22, animations: {
                // まず文言やボタンをフェードアウト
                full.alpha = 0.0
            }, completion: { _ in
                full.removeFromSuperview()
                self.sosFullView = nil
                // 次に赤オーバーレイを縮小
                collapseOverlayThenRestore()
            })
        } else {
            // フル画面がなければ、すぐに赤オーバーレイ縮小へ
            collapseOverlayThenRestore()
        }
    }

    private func animateSOSExpandOverlay() {
        // 決してオプショナルにしないように明示的にコンテナを決定
        let container: UIView
        if let win = self.view.window {
            container = win
        } else if let superview = self.view.superview {
            container = superview
        } else {
            container = self.view
        }

        // ボタン中心をコンテナ座標に変換（安全にフォールバック）
        let btnCenter: CGPoint = {
            if let sp = startEmergencyButton.superview {
                return sp.convert(startEmergencyButton.center, to: container)
            } else {
                return container.center
            }
        }()

        // オーバーレイの初期サイズを『SOSボタンの直径』に合わせる
        let buttonDiameter = max(startEmergencyButton.bounds.width, startEmergencyButton.bounds.height)
        let overlay = UIView(frame: CGRect(x: 0, y: 0, width: buttonDiameter, height: buttonDiameter))
        overlay.backgroundColor = UIColor.kokoRed
        overlay.layer.cornerRadius = buttonDiameter / 2
        if #available(iOS 13.0, *) {
            overlay.layer.cornerCurve = .continuous
        }
        overlay.center = btnCenter
        // 拡大は不透明の赤で。フェードインは行わない
        overlay.alpha = 1.0

        container.addSubview(overlay)
        container.bringSubviewToFront(overlay)
        sosOverlay = overlay
        // 背景の丸はオーバーレイ拡大中は隠す（戻すときにフェード）
        sosBackdrop.isHidden = true

        // 画面対角に十分広がるスケールを計算（基準はボタン直径）
        let w = container.bounds.width
        let h = container.bounds.height
        let target = sqrt(w*w + h*h) * 1.15
        let scale = max(1.0, target / max(buttonDiameter, 1))
        UIView.animate(withDuration: 0.5 as TimeInterval, delay: 0, options: [.curveEaseInOut], animations: {
            overlay.transform = CGAffineTransform(scaleX: scale, y: scale)
        }, completion: { _ in
            self.presentSOSFullScreen(on: container)
        })
    }

    // 画面いっぱいになった後のフルスクリーンSOS画面
    private func presentSOSFullScreen(on container: UIView) {
        // 既に表示済みならスキップ
        if sosFullView != nil { return }

        let full = UIView()
        full.translatesAutoresizingMaskIntoConstraints = false
        full.backgroundColor = UIColor.kokoRed
        full.alpha = 0.0
        container.addSubview(full)
        NSLayoutConstraint.activate([
            full.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            full.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            full.topAnchor.constraint(equalTo: container.topAnchor),
            full.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // 上部の✕とCall 112は非表示（仕様変更）

        // 中央：アイコン、SOSタイトル、説明
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let bell = UIImage(systemName: "bell.and.waveform") ?? UIImage(systemName: "bell.fill") {
            icon.image = bell.withRenderingMode(.alwaysTemplate)
            icon.tintColor = .white
        }
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "SOS"
        title.textColor = .white
        title.font = .systemFont(ofSize: 28, weight: .heavy)
        title.textAlignment = .center

        let desc = UILabel()
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.text = "SOS alert has been sent to\nyour companions."
        desc.textColor = .white
        desc.numberOfLines = 0
        desc.textAlignment = .center
        desc.font = .systemFont(ofSize: 14, weight: .regular)

        full.addSubview(icon)
        full.addSubview(title)
        full.addSubview(desc)

        // 中央の白丸 "I'm Safe"
        let safeBtn = UIButton(type: .system)
        safeBtn.translatesAutoresizingMaskIntoConstraints = false
        safeBtn.backgroundColor = .white
        safeBtn.setTitle("I'm Safe", for: .normal)
        safeBtn.setTitleColor(.systemRed, for: .normal)
        safeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        safeBtn.layer.cornerRadius = 44
        // 『I'm Safe』はハプティクスを出した上で停止処理へ
        safeBtn.addTarget(self, action: #selector(tapSafeButton), for: .touchUpInside)
        full.addSubview(safeBtn)

        // 下部ボタン: 延長 / 即時失効 （アウトライン）
        let extendOutlined = UIButton(type: .system)
        extendOutlined.translatesAutoresizingMaskIntoConstraints = false
        extendOutlined.setTitle("  延長  ", for: .normal)
        extendOutlined.setTitleColor(.white, for: .normal)
        extendOutlined.layer.cornerRadius = 20
        extendOutlined.layer.borderWidth = 1
        extendOutlined.layer.borderColor = UIColor.white.cgColor
        extendOutlined.addTarget(self, action: #selector(tapExtend), for: .touchUpInside)

        let revokeOutlined = UIButton(type: .system)
        revokeOutlined.translatesAutoresizingMaskIntoConstraints = false
        revokeOutlined.setTitle("  即時失効  ", for: .normal)
        revokeOutlined.setTitleColor(.white, for: .normal)
        revokeOutlined.layer.cornerRadius = 20
        revokeOutlined.layer.borderWidth = 1
        revokeOutlined.layer.borderColor = UIColor.white.cgColor
        revokeOutlined.addTarget(self, action: #selector(tapRevoke), for: .touchUpInside)

        let bottomStack = UIStackView(arrangedSubviews: [extendOutlined, revokeOutlined])
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.distribution = .fillEqually
        bottomStack.spacing = 16
        full.addSubview(bottomStack)

        // レイアウト制約
        let g = full.layoutMarginsGuide
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: full.safeAreaLayoutGuide.topAnchor, constant: 40),
            icon.centerXAnchor.constraint(equalTo: full.centerXAnchor),
            icon.heightAnchor.constraint(equalToConstant: 44),
            icon.widthAnchor.constraint(equalToConstant: 44),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            title.centerXAnchor.constraint(equalTo: full.centerXAnchor),

            desc.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            desc.centerXAnchor.constraint(equalTo: full.centerXAnchor),

            safeBtn.topAnchor.constraint(equalTo: desc.bottomAnchor, constant: 28),
            safeBtn.centerXAnchor.constraint(equalTo: full.centerXAnchor),
            safeBtn.heightAnchor.constraint(equalToConstant: 88),
            safeBtn.widthAnchor.constraint(equalToConstant: 88),

            bottomStack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -24),
            bottomStack.bottomAnchor.constraint(equalTo: full.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            extendOutlined.heightAnchor.constraint(equalToConstant: 40),
            revokeOutlined.heightAnchor.constraint(equalToConstant: 40)
        ])

        self.sosFullView = full
        UIView.animate(withDuration: 0.22, animations: {
            full.alpha = 1.0
        })
    }

    @objc private func tapSafeButton() {
        // 成功系のフィードバック
        let h = UINotificationFeedbackGenerator()
        h.prepare()
        h.notificationOccurred(.success)
        // 既存の停止処理へ
        tapStop()
    }

    @objc private func tapMessage() {
        // TODO: メッセージ送信UIへ遷移（現状はプレースホルダー）
        showAlert("Message", "このボタンの挙動は後で接続します。")
    }

    @objc private func tapCall112() {
        if let url = URL(string: "tel://112") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func animateSOSExpandLayer() {
        let center = startEmergencyButton.superview?.convert(startEmergencyButton.center, to: view) ?? view.center
        let startRect = CGRect(x: center.x - sosInitialSize/2, y: center.y - sosInitialSize/2, width: sosInitialSize, height: sosInitialSize)
        let startPath = UIBezierPath(ovalIn: startRect)
        let w = view.bounds.width, h = view.bounds.height
        let target = sqrt(w*w + h*h) * 1.15
        let endRect = CGRect(x: center.x - target/2, y: center.y - target/2, width: target, height: target)
        let endPath = UIBezierPath(ovalIn: endRect)

        let layer = CAShapeLayer()
        layer.path = startPath.cgPath
        // パスアニメーションも不透明の赤に統一
        // パスアニメーションも不透明のブランド赤に統一
        layer.fillColor = UIColor.kokoRed.cgColor
        view.layer.insertSublayer(layer, below: startEmergencyButton.layer)
        sosLayer = layer

        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = startPath.cgPath
        anim.toValue = endPath.cgPath
        anim.duration = 0.5
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "expandPath")
    }

    private func animateSOSCollapseLayer() {
        guard let layer = sosLayer else { return }
        let center = startEmergencyButton.superview?.convert(startEmergencyButton.center, to: view) ?? view.center
        let endRect = CGRect(x: center.x - sosInitialSize/2, y: center.y - sosInitialSize/2, width: sosInitialSize, height: sosInitialSize)
        let endPath = UIBezierPath(ovalIn: endRect)
        let anim = CABasicAnimation(keyPath: "path")
        anim.toValue = endPath.cgPath
        anim.duration = 0.35
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.sosLayer?.removeFromSuperlayer()
            self?.sosLayer = nil
        }
        layer.add(anim, forKey: "collapsePath")
        CATransaction.commit()
    }

    private func kickoff(type: String) {
        if debugAnimateOnlySOS { return }
        // Require at least one recipient
        guard !selectedRecipients.isEmpty else {
            showAlert("受信者未選択", "まず『受信者』をタップして、送信先を選択してください。")
            return
        }
        statusLabel.text = "位置情報を取得中…"
        locationService.requestOneShotLocation { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                do {
                    guard let loc = location else { throw NSError(domain: "loc", code: 1) }
                    let battery = LocationService.batteryPercent()
                    // 共有時間: 緊急は既定60分、帰るモードは設定値から
                    let maxMinutes = (type == "going_home") ? SettingsStore.shared.goingHomeMaxMinutes : 60
                    let res = try await self.api.startAlert(lat: loc.coordinate.latitude,
                                                        lng: loc.coordinate.longitude,
                                                        accuracy: loc.horizontalAccuracy,
                                                        battery: battery,
                                                        type: type,
                                                        maxDurationSec: maxMinutes * 60,
                                                        recipients: self.selectedRecipients)
                    self.statusLabel.text = "共有を開始しました\nAlertID: \(res.id)\nToken: \(res.shareToken.prefix(16))…"
                    let mode: AlertSession.Mode = {
                        if let m = AlertSession.Mode(rawValue: res.type.rawValue) { return m }
                        return AlertSession.Mode(rawValue: type) ?? .emergency
                    }()
                    self.session = AlertSession(id: res.id, shareToken: res.shareToken, status: .active, mode: mode)
                    if mode == .going_home {
                        // 帰るモードでは送信者が手動停止する運用のため、明示ガイダンスを表示
                        self.statusLabel.text = "帰るモードを開始しました。到着したら『停止』をタップしてください。"
                        self.scheduleArrivalReminder()
                    }
                    // 緊急モードではバックグラウンド追跡を開始
                    if mode == .emergency {
                        self.bgTracker.start(alertId: res.id)
                    }
                    self.startPeriodicUpdates()
                } catch {
                    self.statusLabel.text = "開始に失敗しました: \(error.localizedDescription)\n接続先の設定とネットワーク状況をご確認ください。"
                }
            }
        }
    }

    @objc private func tapRecipients() {
        let picker = ContactsPickerViewController()
        picker.onDone = { [weak self] emails in
            self?.selectedRecipients = emails
            self?.dismiss(animated: true)
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    private func startPeriodicUpdates() {
        updateTimer?.invalidate()
        guard let session else { return }
        // going_home モードでは経路共有を行わないため定期更新を行わない
        guard session.mode == .emergency else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateIntervalSec, repeats: true) { [weak self] _ in
            self?.sendUpdate(session: session)
        }
        // 直ちに初回アップデートも実行
        sendUpdate(session: session)
    }

    private func sendUpdate(session: AlertSession) {
        locationService.requestOneShotLocation { [weak self] location in
            guard let self else { return }
            Task.detached {
                guard let loc = location else { return }
                let battery = LocationService.batteryPercent()
                do {
                    try await self.api.updateAlert(id: session.id,
                                                   lat: loc.coordinate.latitude,
                                                   lng: loc.coordinate.longitude,
                                                   accuracy: loc.horizontalAccuracy,
                                                   battery: battery)
                } catch {
                    // 軽微な失敗は無視（ログ化予定）
                }
            }
        }
    }

    @objc private func tapStop() {
        // セッションが無い（デバッグ検証やプレビュー）の場合もUIだけは戻す
        guard let session else {
            self.animateSOSCollapse()
            return
        }
        Task { @MainActor in
            do {
                try await self.api.stopAlert(id: session.id)
                self.session?.status = .ended
                self.teardownActiveSession(with: "共有を停止しました")
                self.animateSOSCollapse()
            } catch {
                self.statusLabel.text = "停止に失敗: \(error.localizedDescription)"
            }
        }
    }

    @objc private func tapRevoke() {
        guard let session else { return }
        Task { @MainActor in
            do { try await self.api.revokeAlert(id: session.id); self.session?.status = .revoked; self.teardownActiveSession(with: "リンクを即時失効しました") }
            catch { self.statusLabel.text = "失効に失敗: \(error.localizedDescription)" }
        }
    }

    private func teardownActiveSession(with message: String) {
        updateTimer?.invalidate(); updateTimer = nil
        reminderTimer?.invalidate(); reminderTimer = nil
        NotificationService.shared.cancelArrivalReminder()
        bgTracker.stop()
        statusLabel.text = message
        session = nil
    }

    private func updateControls() {
        let active = (session?.status == .active)
        stopButton.isEnabled = active
        revokeButton.isEnabled = active
        extendButton.isEnabled = active
    }

    @objc private func tapExtend() {
        guard let session else { return }
        let sheet = UIAlertController(title: "共有時間を延長", message: nil, preferredStyle: .actionSheet)
        func add(_ min: Int) {
            sheet.addAction(UIAlertAction(title: "+\(min)分", style: .default, handler: { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    do { try await self.api.extendAlert(id: session.id, extendMinutes: min); self.statusLabel.text = "共有を延長しました（+\(min)分）" }
                    catch { self.statusLabel.text = "延長に失敗: \(error.localizedDescription)" }
                }
            }))
        }
        [15,30,45,60].forEach(add)
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = extendButton; pop.sourceRect = extendButton.bounds }
        present(sheet, animated: true)
    }

    private func scheduleArrivalReminder() {
        // 可能ならローカル通知を使う。拒否された場合のみフォアグラウンド用タイマーにフォールバック。
        reminderTimer?.invalidate()
        NotificationService.shared.requestAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            if granted {
                NotificationService.shared.cancelArrivalReminder()
                NotificationService.shared.scheduleArrivalReminder(after: reminderIntervalSec)
            } else {
                // フォアグラウンド時のみの簡易リマインダー
                Task { @MainActor in
                    self.reminderTimer = Timer.scheduledTimer(withTimeInterval: self.reminderIntervalSec, repeats: false) { [weak self] _ in
                        guard let self else { return }
                        let alert = UIAlertController(title: "到着リマインダー",
                                                      message: "到着したら『停止』をタップしてください。",
                                                      preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }

    // 設定はタブで提供するため本画面からの遷移は持たない

    @objc private func onSettingsChanged() {
        // 帰るモードで共有中なら、新しい間隔でリマインダーを再スケジュール
        guard session?.status == .active, session?.mode == .going_home else { return }
        reminderTimer?.invalidate(); reminderTimer = nil
        NotificationService.shared.cancelArrivalReminder()
        scheduleArrivalReminder()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // サインアウトは設定タブに移動済み
}

// Helper to await inside @objc
fileprivate func awaitTask(_ block: @escaping () async throws -> Void) {
    Task { try? await block() }
}
