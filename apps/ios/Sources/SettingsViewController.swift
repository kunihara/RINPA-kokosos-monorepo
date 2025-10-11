import UIKit

final class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case sharing
        case recipients
        case profile
        case account
    }

    private enum Row {
        case arrivalReminder
        case maxSharing
        case startTapMode
        case recipients
        case profile
        case signOut
        case deleteAccount
    }

    private let arrivalOptions = [15, 30, 45, 60]
    private let maxOptions = [60, 90, 120, 180, 240]

    private var data: [[Row]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "設定"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        buildData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func buildData() {
        data = [
            [.arrivalReminder, .maxSharing, .startTapMode],
            [.recipients],
            [.profile],
            [.signOut, .deleteAccount],
        ]
    }

    // MARK: - UITableViewDataSource
    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { data[section].count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .sharing: return "共有"
        case .recipients: return "受信者"
        case .profile: return "プロフィール"
        case .account: return "アカウント"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .sharing:
            return "到着リマインダーと最大共有時間を選択できます。値はすぐに保存されます。"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        let row = data[indexPath.section][indexPath.row]
        switch row {
        case .arrivalReminder:
            cell.textLabel?.text = "到着リマインダー"
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .none
            cell.textLabel?.textColor = .label
            cell.contentConfiguration = valueConfig(title: "到着リマインダー", value: "\(SettingsStore.shared.arrivalReminderMinutes)分")
        case .maxSharing:
            cell.contentConfiguration = valueConfig(title: "最大共有時間", value: "\(SettingsStore.shared.goingHomeMaxMinutes)分")
        case .startTapMode:
            let mode = SettingsStore.shared.requireTripleTap ? "3回タップ" : "1回タップ"
            cell.contentConfiguration = valueConfig(title: "開始操作", value: mode)
        case .recipients:
            cell.contentConfiguration = valueConfig(title: "受信者の設定", value: nil)
        case .profile:
            cell.contentConfiguration = valueConfig(title: "プロフィール設定", value: nil)
        case .signOut:
            var cfg = UIListContentConfiguration.valueCell()
            cfg.text = "サインアウト"
            cfg.textProperties.color = .systemRed
            cell.contentConfiguration = cfg
            cell.accessoryType = .none
        case .deleteAccount:
            var cfg = UIListContentConfiguration.valueCell()
            cfg.text = "アカウント削除"
            cfg.textProperties.color = .systemRed
            cell.contentConfiguration = cfg
            cell.accessoryType = .none
        }
        return cell
    }

    private func valueConfig(title: String, value: String?) -> UIListContentConfiguration {
        var cfg = UIListContentConfiguration.valueCell()
        cfg.text = title
        if let v = value { cfg.secondaryText = v }
        return cfg
    }

    // MARK: - UITableViewDelegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = data[indexPath.section][indexPath.row]
        switch row {
        case .arrivalReminder:
            showMinutesSheet(title: "到着リマインダー", options: arrivalOptions, current: SettingsStore.shared.arrivalReminderMinutes) { m in
                SettingsStore.shared.arrivalReminderMinutes = m
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .maxSharing:
            showMinutesSheet(title: "最大共有時間", options: maxOptions, current: SettingsStore.shared.goingHomeMaxMinutes) { m in
                SettingsStore.shared.goingHomeMaxMinutes = m
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .startTapMode:
            showTapModeSheet(currentTriple: SettingsStore.shared.requireTripleTap) { triple in
                SettingsStore.shared.requireTripleTap = triple
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .recipients:
            openRecipients()
        case .profile:
            openProfile()
        case .signOut:
            tapSignOut()
        case .deleteAccount:
            tapDeleteAccount()
        }
    }

    private func showTapModeSheet(currentTriple: Bool, onSelect: @escaping (Bool) -> Void) {
        let sheet = UIAlertController(title: "開始操作", message: nil, preferredStyle: .actionSheet)
        let one = UIAlertAction(title: (currentTriple ? "1回タップ" : "1回タップ ✓"), style: .default) { _ in onSelect(false) }
        let three = UIAlertAction(title: (currentTriple ? "3回タップ ✓" : "3回タップ"), style: .default) { _ in onSelect(true) }
        sheet.addAction(one)
        sheet.addAction(three)
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = self.view; pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.maxY-1, width: 1, height: 1) }
        present(sheet, animated: true)
    }

    private func showMinutesSheet(title: String, options: [Int], current: Int, onSelect: @escaping (Int) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for m in options {
            let title = "\(m)分" + (m == current ? " ✓" : "")
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in onSelect(m) }))
        }
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = self.view; pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.maxY-1, width: 1, height: 1) }
        present(sheet, animated: true)
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
