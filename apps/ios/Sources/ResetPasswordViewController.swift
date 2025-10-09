import UIKit
import Supabase

final class ResetPasswordViewController: UIViewController, UITextFieldDelegate {
    private let titleLabel = UILabel()
    private let newPasswordField = UITextField()
    private let confirmField = UITextField()
    private let updateButton = UIButton(type: .system)
    private let infoLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "パスワード再設定"
        view.backgroundColor = .systemBackground
        setupUI()
    }

    private func setupUI() {
        titleLabel.text = "新しいパスワードを入力してください"
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textAlignment = .center

        newPasswordField.placeholder = "新しいパスワード"
        newPasswordField.isSecureTextEntry = true
        newPasswordField.borderStyle = .roundedRect
        newPasswordField.returnKeyType = .next
        newPasswordField.delegate = self

        confirmField.placeholder = "確認用パスワード"
        confirmField.isSecureTextEntry = true
        confirmField.borderStyle = .roundedRect
        confirmField.returnKeyType = .done
        confirmField.delegate = self

        updateButton.setTitle("パスワードを更新", for: .normal)
        updateButton.addTarget(self, action: #selector(tapUpdate), for: .touchUpInside)

        infoLabel.text = "※ この画面はメールの再設定リンクから遷移しています"
        infoLabel.textColor = .secondaryLabel
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, newPasswordField, confirmField, updateButton, infoLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === newPasswordField { confirmField.becomeFirstResponder() }
        else { textField.resignFirstResponder() }
        return true
    }

    @objc private func tapUpdate() {
        guard let p1 = newPasswordField.text, !p1.isEmpty,
              let p2 = confirmField.text, !p2.isEmpty else {
            alert("入力エラー", "パスワードを入力してください")
            return
        }
        guard p1 == p2 else { alert("不一致", "同じパスワードを入力してください") ; return }
        Task { @MainActor in
            updateButton.isEnabled = false
            defer { updateButton.isEnabled = true }
            do {
                // Supabase Swift v2: update user attributes (password)
                let client = SupabaseAuthAdapter.shared.client
                // 事前にセッション有無を確認（ディープリンクでセッションが適用されなかった場合のガード）
                guard (try? await client.auth.session) != nil else {
                    alert("更新に失敗", "認証セッションが見つかりません。メールのリンクをもう一度開いてから、再度お試しください。")
                    return
                }
                _ = try await client.auth.update(user: UserAttributes(password: p1))
                alert("更新しました", "パスワードを更新しました。再度サインインしてください。") { [weak self] in
                    // セキュリティ方針: リセット直後は必ずサインインを要求
                    Task { @MainActor in
                        try? await SupabaseAuthAdapter.shared.client.auth.signOut()
                        await SupabaseAuthAdapter.shared.updateCachedToken()
                        self?.navigationController?.goToSignIn(animated: true)
                    }
                }
            } catch {
                alert("更新に失敗", error.localizedDescription)
            }
        }
    }

    private func alert(_ title: String, _ msg: String, completion: (() -> Void)? = nil) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion?() }))
        present(a, animated: true)
    }
}
