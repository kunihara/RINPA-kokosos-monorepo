import UIKit

final class ContactsPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onDone: (([String]) -> Void)?
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private let client = ContactsClient()
    private var all: [Contact] = []
    private var filtered: [Contact] = []
    private var selectedEmails = Set<String>()

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

    private func applyFilter(_ q: String?) {
        let query = (q ?? "").lowercased()
        if query.isEmpty { filtered = all }
        else {
            filtered = all.filter { c in
                let nm = (c.name ?? "").lowercased()
                let em = c.email.lowercased()
                return nm.contains(query) || em.contains(query)
            }
        }
        table.reloadData()
    }

    @objc private func tapDone() {
        onDone?(Array(selectedEmails))
    }

    @objc private func tapClose() { dismiss(animated: true) }

    private func setSelected(email: String, selected: Bool) {
        let v = norm(email)
        if selected { selectedEmails.insert(v) } else { selectedEmails.remove(v) }
    }

    private func isVerified(_ c: Contact) -> Bool { c.verified_at != nil }

    private func load() async {
        do {
            let items = try await client.list(status: "verified")
            await MainActor.run {
                self.all = items
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
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let c = filtered[indexPath.row]
        cell.textLabel?.text = c.name?.isEmpty == false ? c.name : c.email
        var detail = c.email
        if c.verified_at == nil { detail += " ・未検証" }
        cell.detailTextLabel?.text = detail
        cell.selectionStyle = .none
        let selected = selectedEmails.contains(norm(c.email))
        cell.accessoryType = selected ? .checkmark : .none
        cell.isUserInteractionEnabled = isVerified(c)
        cell.textLabel?.textColor = isVerified(c) ? .label : .secondaryLabel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let c = filtered[indexPath.row]
        guard isVerified(c) else { return }
        let email = norm(c.email)
        let nowSelected = !selectedEmails.contains(email)
        setSelected(email: email, selected: nowSelected)
        table.reloadRows(at: [indexPath], with: .automatic)
    }

    // MARK: Search
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { applyFilter(searchText) }
}

