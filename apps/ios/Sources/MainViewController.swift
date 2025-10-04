import UIKit
import CoreLocation

final class MainViewController: UIViewController {
    private let titleLabel = UILabel()
    private let startEmergencyButton = UIButton(type: .system)
    private let startHomeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let controlsStack = UIStackView()
    private let stopButton = UIButton(type: .system)
    private let revokeButton = UIButton(type: .system)
    private let countdownView = UILabel()
    private var countdownTimer: Timer?
    private var updateTimer: Timer?
    private var remaining = 0
    private let locationService = LocationService()
    private let api = APIClient()
    private var session: AlertSession? { didSet { updateControls() } }
    private let updateIntervalSec: TimeInterval = 120 // 1〜5分の範囲で調整可（ここは2分）

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    private func setupUI() {
        titleLabel.text = "KokoSOS"
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        startEmergencyButton.setTitle("緊急モード開始", for: .normal)
        startEmergencyButton.addTarget(self, action: #selector(tapStartEmergency), for: .touchUpInside)
        startEmergencyButton.translatesAutoresizingMaskIntoConstraints = false

        startHomeButton.setTitle("帰るモード開始", for: .normal)
        startHomeButton.addTarget(self, action: #selector(tapStartHome), for: .touchUpInside)
        startHomeButton.translatesAutoresizingMaskIntoConstraints = false

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
        view.addSubview(startEmergencyButton)
        view.addSubview(startHomeButton)
        view.addSubview(statusLabel)
        view.addSubview(countdownView)
        controlsStack.axis = .horizontal
        controlsStack.spacing = 12
        controlsStack.alignment = .center
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        stopButton.setTitle("停止", for: .normal)
        stopButton.addTarget(self, action: #selector(tapStop), for: .touchUpInside)
        revokeButton.setTitle("即時失効", for: .normal)
        revokeButton.addTarget(self, action: #selector(tapRevoke), for: .touchUpInside)
        controlsStack.addArrangedSubview(stopButton)
        controlsStack.addArrangedSubview(revokeButton)
        view.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            startEmergencyButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32),
            startEmergencyButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            startHomeButton.topAnchor.constraint(equalTo: startEmergencyButton.bottomAnchor, constant: 16),
            startHomeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: startHomeButton.bottomAnchor, constant: 24),
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

    @objc private func tapStartEmergency() {
        startFlow(type: "emergency")
    }

    @objc private func tapStartHome() {
        startFlow(type: "going_home")
    }

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

    private func kickoff(type: String) {
        statusLabel.text = "位置情報を取得中…"
        locationService.requestOneShotLocation { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                do {
                    guard let loc = location else { throw NSError(domain: "loc", code: 1) }
                    let battery = LocationService.batteryPercent()
                    let res = try await api.startAlert(lat: loc.coordinate.latitude,
                                                        lng: loc.coordinate.longitude,
                                                        accuracy: loc.horizontalAccuracy,
                                                        battery: battery,
                                                        type: type,
                                                        maxDurationSec: 3600)
                    statusLabel.text = "共有を開始しました\nAlertID: \(res.id)\nToken: \(res.shareToken.prefix(16))…"
                    let mode: AlertSession.Mode = {
                        if let m = AlertSession.Mode(rawValue: res.type.rawValue) { return m }
                        return AlertSession.Mode(rawValue: type) ?? .emergency
                    }()
                    session = AlertSession(id: res.id, shareToken: res.shareToken, status: .active, mode: mode)
                    if mode == .going_home {
                        // 帰るモードでは送信者が手動停止する運用のため、明示ガイダンスを表示
                        statusLabel.text = "帰るモードを開始しました。到着したら『停止』をタップしてください。"
                    }
                    startPeriodicUpdates()
                } catch {
                    statusLabel.text = "開始に失敗しました: \(error.localizedDescription)"
                }
            }
        }
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
            do { try await api.stopAlert(id: session.id); self.session?.status = .ended; teardownActiveSession(with: "共有を停止しました") }
            catch { statusLabel.text = "停止に失敗: \(error.localizedDescription)" }
        }
    }

    @objc private func tapRevoke() {
        guard let session else { return }
        Task { @MainActor in
            do { try await api.revokeAlert(id: session.id); self.session?.status = .revoked; teardownActiveSession(with: "リンクを即時失効しました") }
            catch { statusLabel.text = "失効に失敗: \(error.localizedDescription)" }
        }
    }

    private func teardownActiveSession(with message: String) {
        updateTimer?.invalidate(); updateTimer = nil
        statusLabel.text = message
        session = nil
    }

    private func updateControls() {
        let active = (session?.status == .active)
        stopButton.isEnabled = active
        revokeButton.isEnabled = active
    }
}
