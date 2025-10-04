import UIKit

final class SettingsViewController: UIViewController {
    // 到着リマインダー
    private let reminderSegmented = UISegmentedControl(items: ["15分", "30分", "45分", "60分"])
    private let reminderLabel = UILabel()
    private let reminderOptions = [15, 30, 45, 60]
    // 帰るモードの最大共有時間
    private let maxLabel = UILabel()
    private let maxSegmented = UISegmentedControl(items: ["60分", "90分", "120分", "180分", "240分"])
    private let maxOptions = [60, 90, 120, 180, 240]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "設定"
        setupUI()
        loadValues()
    }

    private func setupUI() {
        reminderSegmented.translatesAutoresizingMaskIntoConstraints = false
        reminderSegmented.addTarget(self, action: #selector(changeReminder), for: .valueChanged)

        reminderLabel.text = "到着リマインダーの時間"
        reminderLabel.textColor = .secondaryLabel
        reminderLabel.translatesAutoresizingMaskIntoConstraints = false

        maxLabel.text = "帰るモードの最大共有時間"
        maxLabel.textColor = .secondaryLabel
        maxLabel.translatesAutoresizingMaskIntoConstraints = false
        maxSegmented.translatesAutoresizingMaskIntoConstraints = false
        maxSegmented.addTarget(self, action: #selector(changeMax), for: .valueChanged)

        view.addSubview(reminderLabel)
        view.addSubview(reminderSegmented)
        view.addSubview(maxLabel)
        view.addSubview(maxSegmented)

        NSLayoutConstraint.activate([
            reminderLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            reminderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            reminderLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            reminderSegmented.topAnchor.constraint(equalTo: reminderLabel.bottomAnchor, constant: 12),
            reminderSegmented.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            maxLabel.topAnchor.constraint(equalTo: reminderSegmented.bottomAnchor, constant: 28),
            maxLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            maxLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            maxSegmented.topAnchor.constraint(equalTo: maxLabel.bottomAnchor, constant: 12),
            maxSegmented.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func loadValues() {
        let reminderCurrent = SettingsStore.shared.arrivalReminderMinutes
        if let idx = reminderOptions.firstIndex(of: reminderCurrent) {
            reminderSegmented.selectedSegmentIndex = idx
        } else {
            if let idx = reminderOptions.firstIndex(of: 30) { reminderSegmented.selectedSegmentIndex = idx }
        }
        let maxCurrent = SettingsStore.shared.goingHomeMaxMinutes
        if let idx = maxOptions.firstIndex(of: maxCurrent) {
            maxSegmented.selectedSegmentIndex = idx
        } else if let idx = maxOptions.firstIndex(of: 120) { maxSegmented.selectedSegmentIndex = idx }
    }

    @objc private func changeReminder() {
        let idx = reminderSegmented.selectedSegmentIndex
        guard idx >= 0 && idx < reminderOptions.count else { return }
        SettingsStore.shared.arrivalReminderMinutes = reminderOptions[idx]
    }

    @objc private func changeMax() {
        let idx = maxSegmented.selectedSegmentIndex
        guard idx >= 0 && idx < maxOptions.count else { return }
        SettingsStore.shared.goingHomeMaxMinutes = maxOptions[idx]
    }
}
