import UIKit
import CoreLocation

final class HomeModeViewController: UIViewController {
    private let titleLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let extendButton = UIButton(type: .system)
    private let countdownView = UILabel()
    // 受信者表示バッジ
    private let recipientsBadge = UIView()
    private let recipientsBadgeIcon = UIImageView()
    private let recipientsBadgeLabel = UILabel()
    private var countdownTimer: Timer?
    private var remaining = 0
    private let locationService = LocationService()
    private let api = APIClient()
    private let contactsClient = ContactsClient()
    private var selectedRecipients: [String] = [] { didSet { updateRecipientsChip() } }
    private let recipientsButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "帰るモード"
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
        titleLabel.text = "帰るモード"
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        startButton.setTitle("帰るモード開始", for: .normal)
        startButton.addTarget(self, action: #selector(tapStart), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false

        recipientsButton.setTitle("受信者: 0名", for: .normal)
        recipientsButton.addTarget(self, action: #selector(tapRecipients), for: .touchUpInside)
        recipientsButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        extendButton.setTitle("延長", for: .normal)
        extendButton.addTarget(self, action: #selector(tapExtend), for: .touchUpInside)
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
        view.addSubview(startButton)
        view.addSubview(recipientsButton)
        view.addSubview(statusLabel)
        view.addSubview(countdownView)
        view.addSubview(extendButton)
        view.addSubview(recipientsBadge)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            recipientsButton.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 16),
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

    @objc private func tapStart() { presentCountdown(seconds: 3) { [weak self] in self?.kickoff() } }

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

    private func kickoff() {
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
                } catch {
                    self.statusLabel.text = "開始に失敗しました: \(error.localizedDescription)"
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
}
