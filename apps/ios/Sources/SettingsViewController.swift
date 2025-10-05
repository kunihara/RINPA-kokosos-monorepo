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
    private let recipientsButton = UIButton(type: .system)

    // API Base URL override
    private let apiGroupLabel = UILabel()
    private let apiTextField = UITextField()
    private let apiHelpLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "設定"
        setupUI()
        loadValues()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // サインイン済み かつ 受信者が未登録の場合はオンボーディングを提示
        if presentedViewController == nil {
            Task { @MainActor in
                do {
                    let items = try await ContactsClient().list(status: "all")
                    if items.isEmpty {
                        let vc = OnboardingRecipientsViewController()
                        let nav = UINavigationController(rootViewController: vc)
                        present(nav, animated: true)
                    }
                } catch {
                    // 取得失敗時は黙って無視（次回以降に再評価）
                }
            }
        }
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
        recipientsButton.setTitle("受信者の設定", for: .normal)
        recipientsButton.addTarget(self, action: #selector(openRecipients), for: .touchUpInside)
        recipientsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recipientsButton)

        // API override UI
        apiGroupLabel.text = "APIベースURL(上級者向け)"
        apiGroupLabel.textColor = .secondaryLabel
        apiGroupLabel.translatesAutoresizingMaskIntoConstraints = false
        apiTextField.borderStyle = .roundedRect
        apiTextField.placeholder = "例: http://<MacのIP>:8787 または https://<公開API>"
        apiTextField.keyboardType = .URL
        apiTextField.autocapitalizationType = .none
        apiTextField.autocorrectionType = .no
        apiTextField.clearButtonMode = .whileEditing
        apiTextField.translatesAutoresizingMaskIntoConstraints = false
        apiTextField.addTarget(self, action: #selector(apiEditingDidEnd), for: .editingDidEnd)
        apiHelpLabel.text = "未設定時はInfo.plistのAPIBaseURLを使用。実機はlocalhost不可のためLAN IPや公開ドメインを指定してください。"
        apiHelpLabel.textColor = .tertiaryLabel
        apiHelpLabel.numberOfLines = 0
        apiHelpLabel.font = .systemFont(ofSize: 12)
        apiHelpLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(apiGroupLabel)
        view.addSubview(apiTextField)
        view.addSubview(apiHelpLabel)

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
            maxSegmented.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            recipientsButton.topAnchor.constraint(equalTo: maxSegmented.bottomAnchor, constant: 28),
            recipientsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            apiGroupLabel.topAnchor.constraint(equalTo: recipientsButton.bottomAnchor, constant: 32),
            apiGroupLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            apiGroupLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            apiTextField.topAnchor.constraint(equalTo: apiGroupLabel.bottomAnchor, constant: 8),
            apiTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            apiTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            apiHelpLabel.topAnchor.constraint(equalTo: apiTextField.bottomAnchor, constant: 6),
            apiHelpLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            apiHelpLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
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
        // API override
        apiTextField.text = SettingsStore.shared.apiBaseURLOverride
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

    @objc private func apiEditingDidEnd() {
        let text = apiTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.shared.apiBaseURLOverride = text
    }

    @objc private func openRecipients() {
        let vc = OnboardingRecipientsViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
}
