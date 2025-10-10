import UIKit
import CoreLocation

final class HomeModeViewController: UIViewController {
    private let titleLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let extendButton = UIButton(type: .system)
    private let countdownView = UILabel()
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

        view.addSubview(titleLabel)
        view.addSubview(startButton)
        view.addSubview(recipientsButton)
        view.addSubview(statusLabel)
        view.addSubview(countdownView)
        view.addSubview(extendButton)

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
            countdownView.heightAnchor.constraint(equalToConstant: 100)
        ])
    }

    private func updateRecipientsChip() {
        recipientsButton.setTitle("受信者: \(selectedRecipients.count)名", for: .normal)
    }

    @objc private func tapRecipients() {
        let picker = ContactsPickerViewController()
        picker.onDone = { [weak self] emails in
            self?.selectedRecipients = emails
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
