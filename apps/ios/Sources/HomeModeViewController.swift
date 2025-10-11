import UIKit
import CoreLocation

final class HomeModeViewController: UIViewController {
    private let titleLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let extendButton = UIButton(type: .system)
    // SOSと同じ見出し/説明
    private let headlineLabel = UILabel()
    private let subLabel = UILabel()
    // SOSと同様のバックドロップ（薄い円）
    private let homeBackdrop = UIView()
    private var homeBackdropW: NSLayoutConstraint!
    private var homeBackdropH: NSLayoutConstraint!
    private let homeInitialSize: CGFloat = 280
    private let countdownView = UILabel()
    // 受信者表示バッジ
    private let recipientsBadge = UIView()
    private let recipientsBadgeIcon = UIImageView()
    private let recipientsBadgeLabel = UILabel()
    private var countdownTimer: Timer?
    private var remaining = 0
    // 3回連続タップ用のガード
    private var homeTripleTapCount = 0
    private var homeTripleTapTimer: Timer?
    private let locationService = LocationService()
    private let api = APIClient()
    private let contactsClient = ContactsClient()
    private var selectedRecipients: [String] = [] { didSet { updateRecipientsChip() } }
    private let recipientsButton = UIButton(type: .system)
    private let tripleTapHintLabel = UILabel()
    // Animation (B案: ソリッド・ニュートラル)
    private var overlayView: UIView?
    private var fullView: UIView?
    #if DEBUG
    private let debugAnimateOnlyHome = true
    #else
    private let debugAnimateOnlyHome = false
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // 画面上のナビタイトルは表示しない（SOSと同様の上部ラベルに統一）
        self.title = nil
        setupUI()
        // 保存された受信者を反映
        if let saved = UserDefaults.standard.stringArray(forKey: "SelectedRecipientsEmails"), !saved.isEmpty {
            selectedRecipients = saved
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 空なら保存値を再読込、それでも空なら検証済みから自動選択
        if selectedRecipients.isEmpty, let saved = UserDefaults.standard.stringArray(forKey: "SelectedRecipientsEmails"), !saved.isEmpty {
            selectedRecipients = saved
        }
        if selectedRecipients.isEmpty {
            Task { @MainActor in
                do {
                    let items = try await ContactsClient().list(status: "verified")
                    if !items.isEmpty {
                        self.selectedRecipients = items.map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    }
                } catch { /* ignore */ }
            }
        }
    }

    private func setupUI() {
        // SOSと同じ『Home』表記（小さめラベル）
        titleLabel.text = "Home"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // SOSと同じ上部テキストを同じ位置/スタイルで表示
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

        // SOSボタンと同じ形状・配置（円形の大ボタン）をB案のモノトーンで
        startButton.setTitle("開始", for: .normal)
        startButton.setTitleColor(.white, for: .normal)
        startButton.titleLabel?.font = .boldSystemFont(ofSize: 32)
        // Light/Dark最適化した濃いグレー
        startButton.backgroundColor = .homeButtonFill
        startButton.addTarget(self, action: #selector(tapStart), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false

        recipientsButton.setTitle("受信者: 0名", for: .normal)
        recipientsButton.addTarget(self, action: #selector(tapRecipients), for: .touchUpInside)
        recipientsButton.translatesAutoresizingMaskIntoConstraints = false

        // 3回タップヒント（ボタン周辺グラフィックに被らないよう十分な余白）
        tripleTapHintLabel.text = "3回タップで開始"
        tripleTapHintLabel.textAlignment = .center
        // 見た目は "Are you in an emergency?" と同じスタイル
        tripleTapHintLabel.textColor = .label
        tripleTapHintLabel.font = .systemFont(ofSize: 24, weight: .heavy)
        tripleTapHintLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 画面上の単独ボタンは「即時失効」に変更
        extendButton.setTitle("即時失効", for: .normal)
        extendButton.addTarget(self, action: #selector(tapRevokeFromButton), for: .touchUpInside)
        extendButton.translatesAutoresizingMaskIntoConstraints = false

        countdownView.textAlignment = .center
        countdownView.font = .boldSystemFont(ofSize: 40)
        countdownView.isHidden = true
        countdownView.translatesAutoresizingMaskIntoConstraints = false

        // 受信者バッジ
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

        view.addSubview(titleLabel)
        // バックドロップ（薄い円）を追加して、影ではなくSOSと同じ周辺表現に
        homeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        homeBackdrop.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        homeBackdrop.alpha = 0.3
        if #available(iOS 13.0, *) { homeBackdrop.layer.cornerCurve = .continuous }

        view.addSubview(homeBackdrop)
        view.addSubview(startButton)
        view.addSubview(headlineLabel)
        view.addSubview(subLabel)
        view.addSubview(recipientsButton)
        view.addSubview(tripleTapHintLabel)
        view.addSubview(statusLabel)
        view.addSubview(countdownView)
        view.addSubview(extendButton)
        view.addSubview(recipientsBadge)

        // 事前にバックドロップのサイズ制約を作成
        homeBackdropW = homeBackdrop.widthAnchor.constraint(equalToConstant: homeInitialSize)
        homeBackdropH = homeBackdrop.heightAnchor.constraint(equalToConstant: homeInitialSize)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // SOSと同じ位置関係で上部テキストを配置
            headlineLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            headlineLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            subLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // バックドロップのサイズ（SOSと同じ280）
            homeBackdropW,
            homeBackdropH,
            homeBackdrop.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            homeBackdrop.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            // 開始ボタンはバックドロップ中央に配置（SOSと同じ）
            startButton.centerXAnchor.constraint(equalTo: homeBackdrop.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: homeBackdrop.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 220),
            startButton.heightAnchor.constraint(equalToConstant: 220),

            // ボタンの外周から十分下げる
            tripleTapHintLabel.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 28),
            tripleTapHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            recipientsButton.topAnchor.constraint(equalTo: tripleTapHintLabel.bottomAnchor, constant: 16),
            recipientsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: recipientsButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            extendButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            extendButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 設定に応じてヒント表示/非表示
        tripleTapHintLabel.isHidden = !SettingsStore.shared.requireTripleTap
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startButton.layer.cornerRadius = startButton.bounds.height / 2
        if #available(iOS 13.0, *) { startButton.layer.cornerCurve = .continuous }
        homeBackdrop.layer.cornerRadius = homeBackdrop.bounds.height / 2
        if #available(iOS 13.0, *) { homeBackdrop.layer.cornerCurve = .continuous }
    }

    private func updateRecipientsChip() {
        let count = selectedRecipients.count
        recipientsButton.setTitle("受信者: \(count)名", for: .normal)
        UserDefaults.standard.set(selectedRecipients, forKey: "SelectedRecipientsEmails")
        if count > 0 {
            recipientsBadge.isHidden = false
            let first = selectedRecipients.first ?? ""
            recipientsBadgeLabel.text = (count == 1) ? first : "\(first) ほか\(count-1)人"
        } else {
            recipientsBadge.isHidden = true
        }
    }

    @objc private func tapRecipients() {
        let picker = ContactsPickerViewController()
        picker.onDone = { [weak self] emails in
            self?.selectedRecipients = emails
            UserDefaults.standard.set(emails, forKey: "SelectedRecipientsEmails")
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    @objc private func tapStart() {
        // 設定が1回タップなら即時
        if SettingsStore.shared.requireTripleTap == false {
            // 単発開始時もハプティクスで確定フィードバック
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            animateExpand()
            if debugAnimateOnlyHome { simulateStartDebug(); return }
            presentCountdown(seconds: 3) { [weak self] in self?.kickoff() }
            return
        }
        // 3回連続タップで有効化
        homeTripleTapCount += 1
        homeTripleTapTimer?.invalidate()
        if homeTripleTapCount < 3 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            homeTripleTapTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                self?.homeTripleTapCount = 0
            }
            return
        }
        homeTripleTapCount = 0
        // 3回目は確定フィードバックとして強めのハプティクス
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // B案のフルスクリーン拡大演出を開始
        animateExpand()
        // デバッグ中はランダムで成功/失敗を返す（通信を行わない）
        if debugAnimateOnlyHome { simulateStartDebug(); return }
        presentCountdown(seconds: 3) { [weak self] in self?.kickoff() }
    }

    // DEBUG: 通信を行わず、ランダムで開始の成功/失敗をシミュレーション
    private func simulateStartDebug() {
        let delay: TimeInterval = 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let ok = Bool.random()
            if ok {
                self.showSnack("共有を開始しました")
            } else {
                self.statusLabel.text = "開始に失敗しました: デバッグ失敗"
                self.showAlert("開始処理", "開始に失敗しました（デバッグ）")
                self.closeFullScreen()
            }
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

    private func showAlert(_ title: String, _ msg: String) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    private func showSnack(_ message: String) {
        let container: UIView = self.view.window ?? self.view
        let bar = UILabel()
        bar.text = "  " + message + "  "
        bar.textColor = .white
        bar.font = .systemFont(ofSize: 14, weight: .semibold)
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        bar.numberOfLines = 1
        bar.layer.cornerRadius = 16
        bar.layer.masksToBounds = true
        bar.alpha = 0
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        let g = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -24)
        ])
        UIView.animate(withDuration: 0.2, animations: { bar.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.2, delay: 1.6, options: [], animations: { bar.alpha = 0 }) { _ in
                bar.removeFromSuperview()
            }
        }
    }

    private func kickoff() {
        if debugAnimateOnlyHome { return }
        guard !selectedRecipients.isEmpty else {
            let a = UIAlertController(title: "受信者未選択", message: "まず『受信者』をタップして、送信先を選択してください。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        statusLabel.text = "位置情報を取得中…"
        locationService.requestOneShotLocation { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                do {
                    guard let loc = location else { throw NSError(domain: "loc", code: 1) }
                    let battery = LocationService.batteryPercent()
                    let maxMinutes = SettingsStore.shared.goingHomeMaxMinutes
                    let res = try await self.api.startAlert(lat: loc.coordinate.latitude,
                                                            lng: loc.coordinate.longitude,
                                                            accuracy: loc.horizontalAccuracy,
                                                            battery: battery,
                                                            type: "going_home",
                                                            maxDurationSec: maxMinutes * 60,
                                                            recipients: self.selectedRecipients)
                    self.statusLabel.text = "帰るモードを開始しました。到着したら『停止』をタップしてください。\nAlertID: \(res.id)"
                    // 延長のためにアクティブIDを保存
                    UserDefaults.standard.set(res.id, forKey: "GoingHomeActiveAlertID")
                    // 成功はスナックバーのみで通知し、そのまま移行
                    self.showSnack("共有を開始しました")
                } catch {
                    self.statusLabel.text = "開始に失敗しました: \(error.localizedDescription)"
                    // 失敗はアラートを表示し、自動遷移しないようUIを元に戻す
                    self.showAlert("開始処理", "開始に失敗しました: \(error.localizedDescription)")
                    self.closeFullScreen()
                }
            }
        }
    }

    @objc private func tapExtend() {
        guard let id = UserDefaults.standard.string(forKey: "GoingHomeActiveAlertID"), !id.isEmpty else {
            let a = UIAlertController(title: "延長できません", message: "延長可能な帰るモードが見つかりません。開始後に再度お試しください。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        let sheet = UIAlertController(title: "共有時間を延長", message: nil, preferredStyle: .actionSheet)
        func add(_ min: Int) {
            sheet.addAction(UIAlertAction(title: "+\(min)分", style: .default, handler: { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    do {
                        try await self.api.extendAlert(id: id, extendMinutes: min)
                        self.statusLabel.text = "共有を延長しました（+\(min)分）"
                    } catch {
                        self.statusLabel.text = "延長に失敗: \(error.localizedDescription)"
                    }
                }
            }))
        }
        [15,30,45,60].forEach(add)
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = extendButton; pop.sourceRect = extendButton.bounds }
        present(sheet, animated: true)
    }

    // 画面上の即時失効ボタン（旧: 延長）
    @objc private func tapRevokeFromButton() {
        revokeCurrentAlert()
    }
}

// MARK: - B案: ソリッド・ニュートラルの拡大/縮小演出
extension HomeModeViewController {
    private func animateExpand() {
        guard let container = view.window ?? view.superview ?? view else { return }
        // ボタン中心（コンテナ座標）
        let btnCenter: CGPoint = {
            if startButton.superview != nil {
                return startButton.superview!.convert(startButton.center, to: container)
            } else {
                return container.center
            }
        }()
        // 初期サイズはボタン直径
        let d = max(startButton.bounds.width, startButton.bounds.height)
        let ov = UIView(frame: CGRect(x: 0, y: 0, width: d, height: d))
        ov.backgroundColor = UIColor.homeButtonFill
        ov.layer.cornerRadius = d/2
        if #available(iOS 13.0, *) { ov.layer.cornerCurve = .continuous }
        ov.center = btnCenter
        ov.alpha = 1.0
        container.addSubview(ov)
        container.bringSubviewToFront(ov)
        overlayView = ov

        // 画面対角に十分広がるスケール
        let w = container.bounds.width
        let h = container.bounds.height
        let target = sqrt(w*w + h*h) * 1.15
        let scale = max(1.0, target / max(d, 1))
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut], animations: {
            ov.transform = CGAffineTransform(scaleX: scale, y: scale)
        }, completion: { _ in
            self.presentFullScreen(on: container)
        })
    }

    private func presentFullScreen(on container: UIView) {
        if fullView != nil { return }
        let full = UIView()
        full.translatesAutoresizingMaskIntoConstraints = false
        full.backgroundColor = UIColor.homeButtonFill
        full.alpha = 0.0
        container.addSubview(full)
        NSLayoutConstraint.activate([
            full.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            full.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            full.topAnchor.constraint(equalTo: container.topAnchor),
            full.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.fullView = full

        // アイコン/タイトル/説明（SOSと同様の文面。ただしモノトーンに合わせてlabel色）
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = (UIImage(systemName: "bell.and.waveform") ?? UIImage(systemName: "bell.fill"))?.withRenderingMode(.alwaysTemplate)
        icon.tintColor = .white

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

        // 中央白丸ボタン（I'm Safe と同様の見た目。演出確認用で閉じるのみ）
        let safeBtn = UIButton(type: .system)
        safeBtn.translatesAutoresizingMaskIntoConstraints = false
        safeBtn.backgroundColor = .white
        safeBtn.setTitle("I'm Safe", for: .normal)
        // I'm Safe の文字は背景ベタと同じ色に
        safeBtn.setTitleColor(.homeButtonFill, for: .normal)
        safeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        safeBtn.layer.cornerRadius = 44
        if #available(iOS 13.0, *) { safeBtn.layer.cornerCurve = .continuous }
        // SOSフルスクリーンと同じく成功ハプティクスを鳴らしてから閉じる
        safeBtn.addTarget(self, action: #selector(tapHomeSafe), for: .touchUpInside)
        full.addSubview(safeBtn)

        // 下部: 延長/即時失効（モノトーン）
        let extendBtn = UIButton(type: .system)
        extendBtn.translatesAutoresizingMaskIntoConstraints = false
        extendBtn.setTitle("  延長  ", for: .normal)
        extendBtn.setTitleColor(.white, for: .normal)
        extendBtn.layer.cornerRadius = 20
        extendBtn.layer.borderWidth = 1
        extendBtn.layer.borderColor = UIColor.white.cgColor
        extendBtn.addTarget(self, action: #selector(tapExtend), for: .touchUpInside)

        let revokeBtn = UIButton(type: .system)
        revokeBtn.translatesAutoresizingMaskIntoConstraints = false
        revokeBtn.setTitle("  即時失効  ", for: .normal)
        revokeBtn.setTitleColor(.white, for: .normal)
        revokeBtn.layer.cornerRadius = 20
        revokeBtn.layer.borderWidth = 1
        revokeBtn.layer.borderColor = UIColor.white.cgColor
        revokeBtn.addTarget(self, action: #selector(tapRevokeFromFull), for: .touchUpInside)

        let bottom = UIStackView(arrangedSubviews: [extendBtn, revokeBtn])
        bottom.translatesAutoresizingMaskIntoConstraints = false
        bottom.axis = .horizontal
        bottom.alignment = .center
        bottom.distribution = .fillEqually
        bottom.spacing = 16
        full.addSubview(bottom)

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

            bottom.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 24),
            bottom.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -24),
            bottom.bottomAnchor.constraint(equalTo: full.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            extendBtn.heightAnchor.constraint(equalToConstant: 40),
            revokeBtn.heightAnchor.constraint(equalToConstant: 40)
        ])

        UIView.animate(withDuration: 0.22) { full.alpha = 1.0 }
    }

    @objc private func tapHomeSafe() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        // 帰るモードでも停止+即時失効を実行
        stopAndRevokeCurrentAlert()
        closeFullScreen()
    }

    @objc private func closeFullScreen() {
        // 完全な対称: オーバーレイのみで縮小し、終わったら消す
        guard let container = view.window ?? view.superview ?? view else { return }
        guard let ov = overlayView else { return }
        // フル画面は先にフェード
        if let full = fullView {
            UIView.animate(withDuration: 0.18, animations: { full.alpha = 0 }) { _ in
                full.removeFromSuperview(); self.fullView = nil
            }
        }
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut], animations: {
            ov.transform = .identity
        }, completion: { _ in
            ov.removeFromSuperview(); self.overlayView = nil
        })
    }

    @objc private func tapRevokeFromFull() {
        revokeCurrentAlert()
    }

    private func stopAndRevokeCurrentAlert() {
        guard let id = UserDefaults.standard.string(forKey: "GoingHomeActiveAlertID"), !id.isEmpty else {
            // 起動中の共有が見つからない場合は案内のみ
            statusLabel.text = "停止できません（開始中の共有が見つかりません）"
            return
        }
        // デバッグ: 通信せず擬似応答
        if debugAnimateOnlyHome {
            simulateStopDebug()
            return
        }
        Task { @MainActor in
            do {
                // 1) 停止
                try await self.api.stopAlert(id: id)
                // 2) 即時失効（信頼性向上版：指数バックオフ＋冪等考慮）
                let revokedOK = await self.api.revokeAlertReliably(id: id)
                self.statusLabel.text = revokedOK ? "帰るモードを停止しました（リンクは即時失効）" : "帰るモードを停止しました（リンク失効は未確定）"
                // アクティブIDは不要になるためクリア
                UserDefaults.standard.removeObject(forKey: "GoingHomeActiveAlertID")
                // 成功はスナックバー、未確定/失敗のみアラート
                if revokedOK {
                    self.showSnack("共有を停止しました")
                } else {
                    self.showAlert("停止処理", "共有は停止しましたが、リンクの失効に失敗しました。通信状況をご確認の上、再度お試しください。")
                }
            } catch {
                self.statusLabel.text = "停止に失敗: \(error.localizedDescription)"
                self.showAlert("停止処理", "停止に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    // DEBUG: 停止処理をランダムで成功/失敗にするシミュレーション
    private func simulateStopDebug() {
        let delay: TimeInterval = 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let ok = Bool.random()
            if ok {
                self.statusLabel.text = "帰るモードを停止しました（リンクは即時失効・デバッグ）"
                UserDefaults.standard.removeObject(forKey: "GoingHomeActiveAlertID")
                self.showSnack("共有を停止しました")
            } else {
                self.statusLabel.text = "停止に失敗しました: デバッグ失敗"
                self.showAlert("停止処理", "停止に失敗しました（デバッグ）")
            }
        }
    }

    private func revokeCurrentAlert() {
        guard let id = UserDefaults.standard.string(forKey: "GoingHomeActiveAlertID"), !id.isEmpty else {
            let a = UIAlertController(title: "失効できません", message: "失効可能な共有が見つかりません。開始後に再度お試しください。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        Task { @MainActor in
            do {
                try await self.api.revokeAlert(id: id)
                self.statusLabel.text = "リンクを即時失効しました"
            } catch {
                self.statusLabel.text = "失効に失敗: \(error.localizedDescription)"
            }
        }
    }
}
