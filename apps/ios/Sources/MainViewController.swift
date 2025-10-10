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
        startEmergencyButton.backgroundColor = UIColor.systemRed
        startEmergencyButton.layer.shadowColor = UIColor.systemRed.cgColor
        startEmergencyButton.layer.shadowOpacity = 0.35
        startEmergencyButton.layer.shadowRadius = 16
        startEmergencyButton.layer.shadowOffset = CGSize(width: 0, height: 8)

        sosBackdrop.translatesAutoresizingMaskIntoConstraints = false
        sosBackdrop.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
        sosBackdrop.alpha = 0.3

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
        stopButton.setTitle("停止", for: .normal)
        stopButton.addTarget(self, action: #selector(tapStop), for: .touchUpInside)
        revokeButton.setTitle("即時失効", for: .normal)
        revokeButton.addTarget(self, action: #selector(tapRevoke), for: .touchUpInside)
        extendButton.setTitle("延長", for: .normal)
        extendButton.addTarget(self, action: #selector(tapExtend), for: .touchUpInside)
        controlsStack.addArrangedSubview(stopButton)
        controlsStack.addArrangedSubview(extendButton)
        controlsStack.addArrangedSubview(revokeButton)
        view.addSubview(controlsStack)
        // 設定はタブで提供、サインアウトは設定タブに移動（本画面のバーアイテムは設置しない）

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
            countdownView.heightAnchor.constraint(equalToConstant: 100)
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
    }

    // MARK: - SOS Animation
    private func animateSOSExpand() {
        #if DEBUG
        print("[DEBUG] animateSOSExpand")
        #endif
        // Haptic feedback for emphasis
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // 1) Path-based layer or overlay（より確実に視覚変化させる）
        animateSOSExpandLayer()
        // デバッグ中はオーバーレイでも強制表示
        #if DEBUG
        animateSOSExpandOverlay()
        #endif
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
        if let overlay = sosOverlay, let win = view.window ?? UIApplication.shared.windows.first {
            UIView.animate(withDuration: 0.3, animations: {
                overlay.alpha = 0.0
                overlay.transform = .identity
            }, completion: { _ in
                overlay.removeFromSuperview()
                self.sosOverlay = nil
            })
        }
        sosBackdropW.constant = sosInitialSize
        sosBackdropH.constant = sosInitialSize
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut], animations: {
            self.view.layoutIfNeeded()
            self.sosBackdrop.alpha = 0.3
            self.sosBackdrop.layer.cornerRadius = self.sosInitialSize / 2
        })
        animateSOSCollapseLayer()
        startEmergencyButton.setTitle("SOS", for: .normal)
        startEmergencyButton.removeTarget(self, action: #selector(tapStop), for: .touchUpInside)
        startEmergencyButton.addTarget(self, action: #selector(tapStartEmergency), for: .touchUpInside)
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

        let overlay = UIView(frame: CGRect(x: 0, y: 0, width: sosInitialSize, height: sosInitialSize))
        overlay.backgroundColor = UIColor.systemRed.withAlphaComponent(0.35)
        overlay.layer.cornerRadius = sosInitialSize / 2
        overlay.center = btnCenter
        overlay.alpha = 0.0

        container.addSubview(overlay)
        container.bringSubviewToFront(overlay)
        sosOverlay = overlay

        // 画面対角に十分広がるスケールを計算
        let w = container.bounds.width
        let h = container.bounds.height
        let target = sqrt(w*w + h*h) * 1.15
        let scale = max(1.0, target / sosInitialSize)
        UIView.animate(withDuration: 0.5 as TimeInterval, delay: 0, options: [.curveEaseInOut], animations: {
            overlay.alpha = 1.0
            overlay.transform = CGAffineTransform(scaleX: scale, y: scale)
        })
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
        layer.fillColor = UIColor.systemRed.withAlphaComponent(0.35).cgColor
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
                    if let urlErr = error as? URLError, urlErr.code == .cannotFindHost {
                        self.statusLabel.text = "開始に失敗しました: ホストが見つかりません。設定>APIベースURLで到達可能なURLを指定してください。\n現在: \(self.api.baseURL.absoluteString)"
                    } else {
                        self.statusLabel.text = "開始に失敗しました: \(error.localizedDescription)"
                    }
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
        guard let session else { return }
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
