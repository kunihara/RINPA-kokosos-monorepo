import UIKit
import Contacts
import ContactsUI

final class ContactsPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private struct DeviceEntry { let name: String; let email: String }
    var onDone: (([String]) -> Void)?
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private let client = ContactsClient()
    private var verifiedAll: [Contact] = []
    private var pendingAll: [Contact] = []
    private var verifiedDisplay: [Contact] = []
    private var pendingDisplay: [Contact] = []
    private var deviceEmails: [DeviceEntry] = []
    private var filteredDeviceEmails: [DeviceEntry] = []
    private var selectedEmails = Set<String>()
    private var emailInputs: [String] = [""]
    private let contactStore = CNContactStore()
    private var contactsAuthDenied = false
    private let inputContainer = UIStackView()
    private let addFieldButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private lazy var keyboardToolbar: UIToolbar = {
        let tb = UIToolbar()
        tb.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let close = UIBarButtonItem(title: "閉じる", style: .done, target: self, action: #selector(tapDismissKeyboard))
        tb.items = [flex, close]
        return tb
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "受信者を選択"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "決定", style: .done, target: self, action: #selector(tapDone))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(tapClose))
        searchBar.placeholder = "検索（名前/メール）"
        searchBar.delegate = self
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.translatesAutoresizingMaskIntoConstraints = false
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.inputAccessoryView = keyboardToolbar
        view.addSubview(searchBar)
        // Input container (always visible under search bar)
        inputContainer.axis = .vertical
        inputContainer.spacing = 8
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainer)

        addFieldButton.setTitle("＋ フィールドを追加", for: .normal)
        addFieldButton.addTarget(self, action: #selector(tapAddField), for: .touchUpInside)
        addFieldButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addFieldButton)

        view.addSubview(table)
        table.register(AddEmailCell.self, forCellReuseIdentifier: "AddEmailCell")
        let pickItem = UIBarButtonItem(title: "連絡先から選ぶ", style: .plain, target: self, action: #selector(tapPickDeviceContacts))
        navigationItem.rightBarButtonItem = pickItem

        // Bottom confirm button
        confirmButton.setTitle("決定して送信", for: .normal)
        confirmButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        confirmButton.backgroundColor = .systemBlue
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.layer.cornerRadius = 10
        confirmButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        confirmButton.addTarget(self, action: #selector(tapDone), for: .touchUpInside)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(confirmButton)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            addFieldButton.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 8),
            addFieldButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            table.topAnchor.constraint(equalTo: addFieldButton.bottomAnchor, constant: 8),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -8),
            confirmButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        rebuildInputRows()
        Task { await load(); await loadDeviceContacts() }
    }

    private func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    private func isValidEmail(_ s: String) -> Bool { let p = ".+@.+\\..+"; return s.range(of: p, options: .regularExpression) != nil }

    private func applyFilter(_ q: String?) {
        let query = (q ?? "").lowercased()
        let lcq = query
        let locale = Locale(identifier: "ja_JP")
        func displayName(_ c: Contact) -> String { (c.name?.isEmpty == false ? c.name! : c.email) }
        func surnameFirst(_ name: String) -> String {
            // Assume "姓 名" and prefer sorting by 姓 (first token). Fallback to whole.
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.split(separator: " ").first else { return trimmed }
            return String(first)
        }
        if lcq.isEmpty {
            // Ensure default displays are sorted by surname in ja_JP
            verifiedDisplay = verifiedAll.sorted { a, b in
                let aKey = surnameFirst(displayName(a))
                let bKey = surnameFirst(displayName(b))
                return aKey.compare(bKey, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
            }
            pendingDisplay  = pendingAll.sorted { a, b in
                let aKey = surnameFirst(displayName(a))
                let bKey = surnameFirst(displayName(b))
                return aKey.compare(bKey, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
            }
            filteredDeviceEmails = deviceEmails
        } else {
            verifiedDisplay = verifiedAll.filter { displayName($0).lowercased().contains(lcq) || $0.email.lowercased().contains(lcq) }
            pendingDisplay  = pendingAll.filter  { displayName($0).lowercased().contains(lcq) || $0.email.lowercased().contains(lcq) }
            filteredDeviceEmails = deviceEmails.filter { pair in
                pair.name.lowercased().contains(lcq) || pair.email.lowercased().contains(lcq)
            }
            // sort filtered as well
            verifiedDisplay.sort { surnameFirst(displayName($0)).compare(surnameFirst(displayName($1)), options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending }
            pendingDisplay.sort  { surnameFirst(displayName($0)).compare(surnameFirst(displayName($1)), options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending }
            filteredDeviceEmails.sort { ( $0.name as NSString).localizedStandardCompare($1.name) == .orderedAscending }
        }
        table.reloadData()
    }

    @objc private func tapDone() {
        // Process direct inputs: send verify for valid emails (non-empty)
        let emails = emailInputs.map { norm($0) }.filter { !$0.isEmpty && isValidEmail($0) }
        Task { @MainActor in
            if !emails.isEmpty {
                do {
                    _ = try await client.bulkUpsert(emails: emails, sendVerify: true)
                } catch {
                    let a = UIAlertController(title: "送信失敗", message: error.localizedDescription, preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    present(a, animated: true)
                    return
                }
            }
            // Close modal and return selected (verified) emails
            self.onDone?(Array(self.selectedEmails))
            self.dismiss(animated: true)
        }
    }

    @objc private func tapClose() { dismiss(animated: true) }

    private func setSelected(email: String, selected: Bool) {
        let v = norm(email)
        if selected { selectedEmails.insert(v) } else { selectedEmails.remove(v) }
    }

    private func isVerified(_ c: Contact) -> Bool { c.verified_at != nil }

    private func load() async {
        do {
            let items = try await client.list(status: "all")
            await MainActor.run {
                func displayName(_ c: Contact) -> String { (c.name?.isEmpty == false ? c.name! : c.email) }
                func surnameFirst(_ name: String) -> String {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard let first = trimmed.split(separator: " ").first else { return trimmed }
                    return String(first)
                }
                let locale = Locale(identifier: "ja_JP")
                self.verifiedAll = items.filter { $0.verified_at != nil }
                    .sorted {
                        let aKey = surnameFirst(displayName($0))
                        let bKey = surnameFirst(displayName($1))
                        return aKey.compare(bKey, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
                    }
                self.pendingAll  = items.filter { $0.verified_at == nil }
                    .sorted {
                        let aKey = surnameFirst(displayName($0))
                        let bKey = surnameFirst(displayName($1))
                        return aKey.compare(bKey, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
                    }
                self.filteredDeviceEmails = self.deviceEmails
                self.applyFilter(self.searchBar.text)
            }
        } catch {
            await MainActor.run {
                var message = error.localizedDescription
                var showReauth = false
                if let apiErr = error as? APIError, case let .http(status, _) = apiErr, status == 401 {
                    message = "サインインが期限切れ/無効です。サインインし直してください。"
                    showReauth = true
                }
                let alert = UIAlertController(title: "取得失敗", message: message, preferredStyle: .alert)
                if showReauth {
                    alert.addAction(UIAlertAction(title: "サインイン", style: .default, handler: { [weak self] _ in
                        self?.navigateToSignInRoot()
                    }))
                }
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }

    private func navigateToSignInRoot() {
        Task {
            // サインアウトは非同期。完了を待ってからUI遷移。
            try? await SupabaseAuthAdapter.shared.client.auth.signOut()
            await MainActor.run {
                let complete: (UINavigationController) -> Void = { nav in
                    nav.setViewControllers([SignInViewController()], animated: true)
                }
                if let rootNav = (self.view.window?.rootViewController as? UINavigationController) {
                    if rootNav.presentedViewController != nil {
                        rootNav.dismiss(animated: true) { complete(rootNav) }
                    } else if let _ = self.presentingViewController {
                        self.dismiss(animated: true) { complete(rootNav) }
                    } else {
                        complete(rootNav)
                    }
                } else {
                    // Fallback: try dismiss self, then attempt again
                    self.dismiss(animated: true) { [weak self] in
                        guard let self, let nav = (self.view.window?.rootViewController as? UINavigationController) else { return }
                        complete(nav)
                    }
                }
            }
        }
    }

    private func loadDeviceContacts() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                contactStore.requestAccess(for: .contacts) { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.contactsAuthDenied = !granted
                        cont.resume()
                    }
                }
            }
            await fetchDeviceContactsIfAuthorized()
        case .authorized:
            await fetchDeviceContactsIfAuthorized()
        case .denied, .restricted:
            contactsAuthDenied = true
        @unknown default:
            contactsAuthDenied = true
        }
        await MainActor.run {
            self.filteredDeviceEmails = self.deviceEmails
            self.applyFilter(self.searchBar.text)
        }
    }

    private func fetchDeviceContactsIfAuthorized() async {
        var results: [(sortKey: String, name: String, email: String)] = []
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as NSString,
            CNContactFamilyNameKey as NSString,
            CNContactPhoneticGivenNameKey as NSString,
            CNContactPhoneticFamilyNameKey as NSString,
            CNContactEmailAddressesKey as NSString
        ]
        let req = CNContactFetchRequest(keysToFetch: keys)
        req.sortOrder = .familyName
        do {
            try contactStore.enumerateContacts(with: req) { contact, _ in
                let name = (contact.familyName + " " + contact.givenName).trimmingCharacters(in: .whitespaces)
                // Prefer phonetic (ふりがな/ローマ字読み) of family name for sorting
                let familyKana = contact.phoneticFamilyName
                let givenKana = contact.phoneticGivenName
                let sortKeyBase: String
                if !familyKana.isEmpty {
                    sortKeyBase = (familyKana + " " + givenKana).trimmingCharacters(in: .whitespaces)
                } else {
                    sortKeyBase = name
                }
                for emailValue in contact.emailAddresses {
                    let em = self.norm(emailValue.value as String)
                    if !em.isEmpty && self.isValidEmail(em) {
                        let display = name.isEmpty ? em : name
                        let sortKey = (display.isEmpty ? em : sortKeyBase)
                        results.append((sortKey: sortKey, name: display, email: em))
                    }
                }
            }
        } catch {
            contactsAuthDenied = true
        }
        // Unique by email
        var seen = Set<String>()
        var unique: [(sortKey: String, entry: DeviceEntry)] = []
        for item in results {
            let e = item.email
            if !seen.contains(e) { seen.insert(e); unique.append((sortKey: item.sortKey, entry: DeviceEntry(name: item.name, email: e))) }
        }
        // 五十音順（日本語ローカライズ）でソート（氏名が空ならメールで代替）
        let locale = Locale(identifier: "ja_JP")
        deviceEmails = unique.sorted { a, b in
            let an = a.sortKey.isEmpty ? (a.entry.name.isEmpty ? a.entry.email : a.entry.name) : a.sortKey
            let bn = b.sortKey.isEmpty ? (b.entry.name.isEmpty ? b.entry.email : b.entry.name) : b.sortKey
            return an.compare(bn, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
        }.map { $0.entry }
    }

    // MARK: Table
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return contactsAuthDenied ? 1 : filteredDeviceEmails.count
        case 1: return verifiedDisplay.count
        default: return pendingDisplay.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if contactsAuthDenied {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
                cell.textLabel?.text = "連絡先へのアクセスが許可されていません"
                cell.detailTextLabel?.text = "設定アプリで許可するか、下の入力欄にメールを追加してください"
                cell.selectionStyle = .none
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
            let pair = filteredDeviceEmails[indexPath.row]
            cell.textLabel?.text = pair.name
            cell.detailTextLabel?.text = pair.email
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        } else if indexPath.section == 1 || indexPath.section == 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
            let c = (indexPath.section == 1 ? verifiedDisplay[indexPath.row] : pendingDisplay[indexPath.row])
            cell.textLabel?.text = c.name?.isEmpty == false ? c.name : c.email
            var detail = c.email
            if c.verified_at == nil { detail += " ・未検証" } else { detail += " ・検証済み" }
            cell.detailTextLabel?.text = detail
            cell.selectionStyle = .none
            let selected = selectedEmails.contains(norm(c.email))
            cell.accessoryType = selected ? .checkmark : .none
            cell.isUserInteractionEnabled = (c.verified_at != nil)
            cell.textLabel?.textColor = (c.verified_at != nil) ? .label : .secondaryLabel
            return cell
        } else {
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            // Device contacts: add to input fields
            guard !contactsAuthDenied else { return }
            let email = filteredDeviceEmails[indexPath.row].email
            handlePickedEmails([email])
        } else if indexPath.section == 1 {
            let c = verifiedDisplay[indexPath.row]
            let email = norm(c.email)
            let nowSelected = !selectedEmails.contains(email)
            setSelected(email: email, selected: nowSelected)
            table.reloadRows(at: [indexPath], with: .automatic)
        } else {
            return
        }
    }

    // MARK: Headers
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "端末の連絡先（検索可・タップで下に追加）"
        case 1: return "連絡先（検証済み・選択可）"
        default: return pendingDisplay.isEmpty ? nil : "連絡先（未検証・選択不可）"
        }
    }

    // MARK: Input rows
    @objc private func tapAddField() { emailInputs.append(""); rebuildInputRows() }

    @objc private func onInputEditingChanged(_ tf: UITextField) {
        let idx = tf.tag
        guard idx >= 0 && idx < emailInputs.count else { return }
        emailInputs[idx] = tf.text ?? ""
    }

    @objc private func onRemoveField(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < emailInputs.count else { return }
        if emailInputs.count > 1 { emailInputs.remove(at: idx) }
        rebuildInputRows()
    }

    private func rebuildInputRows() {
        // Clear existing
        for v in inputContainer.arrangedSubviews { inputContainer.removeArrangedSubview(v); v.removeFromSuperview() }
        for (i, value) in emailInputs.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .fill
            let tf = UITextField()
            tf.placeholder = "メールアドレス"
            tf.text = value
            tf.autocapitalizationType = .none
            tf.keyboardType = .emailAddress
            tf.borderStyle = .roundedRect
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.inputAccessoryView = keyboardToolbar
            tf.tag = i
            tf.addTarget(self, action: #selector(onInputEditingChanged(_:)), for: .editingChanged)
            let remove = UIButton(type: .system)
            remove.setTitle("−", for: .normal)
            remove.titleLabel?.font = .boldSystemFont(ofSize: 20)
            remove.tag = i
            remove.addTarget(self, action: #selector(onRemoveField(_:)), for: .touchUpInside)
            remove.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(tf)
            row.addArrangedSubview(remove)
            inputContainer.addArrangedSubview(row)
        }
    }

    @objc private func tapDismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: Footer for add button in inputs
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 3 else { return nil }
        let v = UIView()
        let btn = UIButton(type: .system)
        btn.setTitle("＋ フィールドを追加", for: .normal)
        btn.addAction(UIAction(handler: { [weak self] _ in self?.emailInputs.append(""); self?.table.reloadData() }), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            btn.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            btn.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8)
        ])
        return v
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { section == 3 ? 48 : 0 }

    // MARK: Search
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { applyFilter(searchText) }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    // MARK: Device Contacts Picker
    @objc private func tapPickDeviceContacts() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            contactStore.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async { if granted { self?.presentContactsPicker() } else { self?.showContactsDenied() } }
            }
        case .authorized:
            presentContactsPicker()
        case .denied, .restricted:
            showContactsDenied()
        @unknown default:
            showContactsDenied()
        }
    }

    private func presentContactsPicker() {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        // 有効化: メールを持つ連絡先のみ
        picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        // 連絡先単位の選択は不可、メールプロパティ選択のみ許可
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'emailAddresses'")
        present(picker, animated: true)
    }

    private func showContactsDenied() {
        let a = UIAlertController(title: "連絡先へのアクセスが許可されていません", message: "設定アプリで連絡先アクセスを許可するか、メールを直接入力してください。", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        a.addAction(UIAlertAction(title: "設定を開く", style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }))
        present(a, animated: true)
    }
}

extension ContactsPickerViewController: CNContactPickerDelegate {
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        guard contactProperty.key == CNContactEmailAddressesKey, let val = contactProperty.value as? NSString else { return }
        let email = norm(val as String)
        handlePickedEmails([email])
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        // 連絡先単位で選択された場合は、その連絡先の全メールを対象（通常はpredicateで無効化済み）
        var emails: [String] = []
        for c in contacts { emails.append(contentsOf: c.emailAddresses.map { norm($0.value as String) }) }
        handlePickedEmails(emails)
    }

    private func handlePickedEmails(_ emailsRaw: [String]) {
        let emails = Array(Set(emailsRaw.filter { !$0.isEmpty && isValidEmail($0) }))
        guard !emails.isEmpty else { return }
        // すぐには送信せず、下の入力セクションに追加して最後にまとめて送信
        var existing = Set(emailInputs.map { norm($0) }.filter { !$0.isEmpty })
        var added = 0
        for e in emails {
            if !existing.contains(e) {
                if emailInputs.count == 1 && emailInputs[0].isEmpty {
                    emailInputs[0] = e
                } else {
                    emailInputs.append(e)
                }
                existing.insert(e)
                added += 1
            }
        }
        // Reflect newly added emails in the input UI immediately
        rebuildInputRows()
        table.reloadData()
        if added > 0 {
            let a = UIAlertController(title: "追加しました", message: "\(added)件のメールを入力欄に追加しました。確認後に『決定』で送信します。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
        }
    }
}
