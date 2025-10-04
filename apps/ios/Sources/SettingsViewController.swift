import UIKit

final class SettingsViewController: UIViewController {
    private let segmented = UISegmentedControl(items: ["15分", "30分", "45分", "60分"])
    private let infoLabel = UILabel()

    private let options = [15, 30, 45, 60]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "設定"
        setupUI()
        loadValue()
    }

    private func setupUI() {
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.addTarget(self, action: #selector(changeSegment), for: .valueChanged)

        infoLabel.text = "帰るモードの到着リマインダー時間"
        infoLabel.textColor = .secondaryLabel
        infoLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(infoLabel)
        view.addSubview(segmented)

        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            segmented.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
            segmented.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func loadValue() {
        let current = SettingsStore.shared.arrivalReminderMinutes
        if let idx = options.firstIndex(of: current) {
            segmented.selectedSegmentIndex = idx
        } else {
            if let idx = options.firstIndex(of: 30) { segmented.selectedSegmentIndex = idx }
        }
    }

    @objc private func changeSegment() {
        let idx = segmented.selectedSegmentIndex
        guard idx >= 0 && idx < options.count else { return }
        SettingsStore.shared.arrivalReminderMinutes = options[idx]
    }
}

