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
    private let profileButton = UIButton(type: .system)

    private let dangerLabel = UILabel()
    private let deleteAccountButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "設定"
        setupUI()
        loadValues()
    }

    // 設定画面では自動で「受信者の選択」を開かない（ユーザー操作で開く）
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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

        profileButton.setTitle("プロフィール設定", for: .normal)
        profileButton.addTarget(self, action: #selector(openProfile), for: .touchUpInside)
        profileButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(profileButton)

        // APIベースURLのUIは仕様変更により削除
        dangerLabel.text = "アカウント"
        dangerLabel.textColor = .secondaryLabel
        dangerLabel.translatesAutoresizingMaskIntoConstraints = false
        deleteAccountButton.setTitle("アカウント削除", for: .normal)
        deleteAccountButton.setTitleColor(.systemRed, for: .normal)
        deleteAccountButton.addTarget(self, action: #selector(tapDeleteAccount), for: .touchUpInside)
        deleteAccountButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.setTitle("サインアウト", for: .normal)
        signOutButton.addTarget(self, action: #selector(tapSignOut), for: .touchUpInside)
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dangerLabel)
        view.addSubview(signOutButton)
        view.addSubview(deleteAccountButton)

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

            profileButton.topAnchor.constraint(equalTo: recipientsButton.bottomAnchor, constant: 16),
            profileButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // 直後にアカウントセクション
            dangerLabel.topAnchor.constraint(equalTo: profileButton.bottomAnchor, constant: 32),
            dangerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dangerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            signOutButton.topAnchor.constraint(equalTo: dangerLabel.bottomAnchor, constant: 12),
            signOutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            deleteAccountButton.topAnchor.constraint(equalTo: signOutButton.bottomAnchor, constant: 12),
            deleteAccountButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
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
        // APIベースURLは非表示のためロード不要
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

    // APIベースURL編集ハンドラは削除

    @objc private func openRecipients() {
        // サインイン必須（トークン無し時は先にサインイン）
        if SupabaseAuthAdapter.shared.accessToken == nil {
            navigateToSignInRoot()
            return
        }
        let picker = ContactsPickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    @objc private func openProfile() {
        let vc = ProfileEditViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func navigateToSignInRoot() {
        // サインアウトは行わず、サインイン画面へ遷移のみ（インストール毎のセッション消失を避けるため）
        let complete: (UINavigationController) -> Void = { nav in
            nav.goToSignIn(animated: true)
        }
        if let rootNav = (view.window?.rootViewController as? UINavigationController) {
            if rootNav.presentedViewController != nil {
                rootNav.dismiss(animated: true) { complete(rootNav) }
            } else if let _ = self.presentingViewController {
                self.dismiss(animated: true) { complete(rootNav) }
            } else {
                complete(rootNav)
            }
        } else {
            self.dismiss(animated: true) { [weak self] in
                guard let self, let nav = (self.view.window?.rootViewController as? UINavigationController) else { return }
                complete(nav)
            }
        }
    }

    @objc private func tapDeleteAccount() {
        let alert = UIAlertController(title: "アカウント削除", message: "この操作は元に戻せません。全てのデータが削除され、ログアウトします。実行しますか？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "削除", style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            // 要トークン（サインイン）チェック
            if SupabaseAuthAdapter.shared.accessToken == nil {
                let a = UIAlertController(title: "サインインが必要です", message: "アカウント削除にはサインインが必要です。サインインし直してから実行してください。", preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(a, animated: true)
                return
            }
            Task { @MainActor in
                self.deleteAccountButton.isEnabled = false
                defer { self.deleteAccountButton.isEnabled = true }
                do {
                    try await APIClient().deleteAccount()
                    // Pushトークン解除→サインアウト
                    PushRegistrationService.shared.unregisterLastToken()
                    try? await SupabaseAuthAdapter.shared.client.auth.signOut()
                    // 仕様: pushではなくpopで戻る（必要に応じてpresentedを解消）
                    self.navigateToSignInRoot()
                } catch {
                    #if DEBUG
                    print("[DeleteAccount] error=\(error)")
                    #endif
                    let msg: String
                    if let apiErr = error as? APIError, case let .http(status, _) = apiErr, status == 401 {
                        msg = "サインインが期限切れ/不正です。サインインし直してから実行してください。"
                    } else {
                        msg = error.localizedDescription
                    }
                    let a = UIAlertController(title: "削除に失敗", message: msg, preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(a, animated: true)
                }
            }
        }))
        present(alert, animated: true)
    }

    @objc private func tapSignOut() {
        let a = UIAlertController(title: "サインアウト", message: "サインアウトしてよろしいですか？", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        a.addAction(UIAlertAction(title: "サインアウト", style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // SDKサインアウト（失敗は黙許）
                try? await SupabaseAuthAdapter.shared.client.auth.signOut()
                // FCMのサーバ有効フラグを下げる（最終登録トークン）
                PushRegistrationService.shared.unregisterLastToken()
                self.navigateToSignInRoot()
            }
        }))
        present(a, animated: true)
    }
}
