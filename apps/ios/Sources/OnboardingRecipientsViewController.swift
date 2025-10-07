import UIKit

final class OnboardingRecipientsViewController: UIViewController, UITableViewDataSource {
    private let infoLabel = UILabel()
    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let client = ContactsClient()
    private var items: [Contact] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "受信者の設定"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "閉じる", style: .plain, target: self, action: #selector(closeSelf))

        infoLabel.text = "メールアドレスを入力して受信者に追加します。追加後に確認メールを送信します。複数は改行・カンマ区切りで入力できます。"
        infoLabel.numberOfLines = 0
        infoLabel.textColor = .secondaryLabel

        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.cornerRadius = 8
        textView.font = .systemFont(ofSize: 16)
        textView.text = ""

        sendButton.setTitle("検証メールを送信", for: .normal)
        sendButton.addTarget(self, action: #selector(tapSend), for: .touchUpInside)

        table.dataSource = self

        [infoLabel, textView, sendButton, table].forEach { v in
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 100),

            sendButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 12),
            sendButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            table.topAnchor.constraint(equalTo: sendButton.bottomAnchor, constant: 16),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        Task { await refreshList() }
    }

    @objc private func closeSelf() { dismiss(animated: true) }

    @objc private func tapSend() {
        let raw = textView.text ?? ""
        let seps = CharacterSet(charactersIn: ",\n ")
        let parts = raw.components(separatedBy: seps).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            let a = UIAlertController(title: "入力がありません", message: "メールアドレスを入力してください", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        Task { @MainActor in
            do {
                let res = try await client.bulkUpsert(emails: parts, sendVerify: true)
                textView.text = ""
                let failed = res.verifyFailed
                let sentCount = parts.count - failed.count
                let title = failed.isEmpty ? "送信しました" : "送信完了（一部エラー）"
                let msg: String = failed.isEmpty
                    ? "\(sentCount)件の宛先に確認メールを送信しました。"
                    : "\(sentCount)件に送信しました。送信できなかった宛先:\n\(failed.joined(separator: ", "))"
                let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                present(a, animated: true)
                await refreshList()
            } catch {
                let a = UIAlertController(title: "送信失敗", message: error.localizedDescription, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                present(a, animated: true)
            }
        }
    }

    private func refreshList() async {
        do {
            let res = try await client.list(status: "all")
            await MainActor.run {
                self.items = res
                self.table.reloadData()
            }
        } catch { /* noop */ }
    }

    // MARK: Table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let c = items[indexPath.row]
        cell.textLabel?.text = c.name?.isEmpty == false ? c.name : c.email
        var detail = c.email
        detail += c.verified_at == nil ? " ・未検証" : " ・検証済み"
        cell.detailTextLabel?.text = detail
        cell.selectionStyle = .none
        return cell
    }
}
