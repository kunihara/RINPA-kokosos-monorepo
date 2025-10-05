import UIKit
import Contacts
import ContactsUI

final class ContactsPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onDone: (([String]) -> Void)?
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private let client = ContactsClient()
    private var verified: [Contact] = []
    private var pending: [Contact] = []
    private var selectedEmails = Set<String>()
    private var emailInputs: [String] = [""]
    private let contactStore = CNContactStore()

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
        view.addSubview(searchBar)
        view.addSubview(table)
        table.register(AddEmailCell.self, forCellReuseIdentifier: "AddEmailCell")
        let pickItem = UIBarButtonItem(title: "連絡先から選ぶ", style: .plain, target: self, action: #selector(tapPickDeviceContacts))
        let doneItem = UIBarButtonItem(title: "決定", style: .done, target: self, action: #selector(tapDone))
        navigationItem.rightBarButtonItems = [doneItem, pickItem]
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        Task { await load() }
    }

    private func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    private func isValidEmail(_ s: String) -> Bool { let p = ".+@.+\\..+"; return s.range(of: p, options: .regularExpression) != nil }

    private func applyFilter(_ q: String?) {
        let query = (q ?? "").lowercased()
        if query.isEmpty {
            // no-op; keep original ordering
        } else {
            verified = verified.filter { ( ($0.name ?? "").lowercased().contains(query) ) || $0.email.lowercased().contains(query) }
            pending = pending.filter { ( ($0.name ?? "").lowercased().contains(query) ) || $0.email.lowercased().contains(query) }
        }
        table.reloadData()
    }

    @objc private func tapDone() {
        // Process direct inputs: send verify for valid emails (non-empty)
        let emails = emailInputs.map { norm($0) }.filter { !$0.isEmpty && isValidEmail($0) }
        if !emails.isEmpty {
            Task { @MainActor in
                do {
                    _ = try await client.bulkUpsert(emails: emails, sendVerify: true)
                    let a = UIAlertController(title: "送信しました", message: "入力したメールに確認メールを送信しました。検証完了後に選択できるようになります。", preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                        self?.onDone?(Array(self?.selectedEmails ?? []))
                    })
                    present(a, animated: true)
                } catch {
                    let a = UIAlertController(title: "送信失敗", message: error.localizedDescription, preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    present(a, animated: true)
                }
            }
        } else {
            onDone?(Array(selectedEmails))
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
                self.verified = items.filter { $0.verified_at != nil }
                self.pending = items.filter { $0.verified_at == nil }
                self.applyFilter(self.searchBar.text)
            }
        } catch {
            await MainActor.run {
                let alert = UIAlertController(title: "取得失敗", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    // MARK: Table
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return verified.count
        case 1: return pending.count
        default: return emailInputs.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section <= 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
            let c = (indexPath.section == 0 ? verified[indexPath.row] : pending[indexPath.row])
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
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddEmailCell", for: indexPath) as! AddEmailCell
            cell.textField.text = emailInputs[indexPath.row]
            cell.onChange = { [weak self] text in self?.emailInputs[indexPath.row] = text }
            cell.onRemove = { [weak self] in
                guard let self else { return }
                if self.emailInputs.count > 1 { self.emailInputs.remove(at: indexPath.row); self.table.reloadSections(IndexSet(integer: 2), with: .automatic) }
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else { return }
        let c = verified[indexPath.row]
        let email = norm(c.email)
        let nowSelected = !selectedEmails.contains(email)
        setSelected(email: email, selected: nowSelected)
        table.reloadRows(at: [indexPath], with: .automatic)
    }

    // MARK: Headers
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "連絡先（検証済み・選択可）"
        case 1: return pending.isEmpty ? nil : "連絡先（未検証・選択不可）"
        default: return "メールを直接入力（1行=1件、＋で追加）"
        }
    }

    // MARK: Footer for add button in inputs
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 2 else { return nil }
        let v = UIView()
        let btn = UIButton(type: .system)
        btn.setTitle("＋ フィールドを追加", for: .normal)
        btn.addAction(UIAction(handler: { [weak self] _ in self?.emailInputs.append(""); self?.table.reloadSections(IndexSet(integer: 2), with: .automatic) }), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            btn.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            btn.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8)
        ])
        return v
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { section == 2 ? 48 : 0 }

    // MARK: Search
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { applyFilter(searchText) }

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
        table.reloadSections(IndexSet(integer: 2), with: .automatic)
        if added > 0 {
            let a = UIAlertController(title: "追加しました", message: "\(added)件のメールを入力欄に追加しました。確認後に『決定』で送信します。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
        }
    }
}
