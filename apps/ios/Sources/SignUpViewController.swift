import UIKit

final class SignUpViewController: UIViewController {
    private let titleLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let signUpButton = UIButton(type: .system)
    private let infoLabel = UILabel()

    private let api = APIClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "新規登録"
        setupUI()
    }

    private func setupUI() {
        titleLabel.text = "KokoSOS"
        titleLabel.font = .boldSystemFont(ofSize: 28)
        titleLabel.textAlignment = .center

        emailField.placeholder = "メールアドレス"
        emailField.autocapitalizationType = .none
        emailField.keyboardType = .emailAddress
        emailField.borderStyle = .roundedRect

        passwordField.placeholder = "パスワード（8文字以上）"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect

        signUpButton.setTitle("登録する", for: .normal)
        signUpButton.addTarget(self, action: #selector(tapSignUp), for: .touchUpInside)

        infoLabel.text = "登録後に確認メールを送信します。メール内のリンクから確認を完了してください。"
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, emailField, passwordField, signUpButton, infoLabel])
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

    @objc private func tapSignUp() {
        guard let email = emailField.text, !email.isEmpty, let pass = passwordField.text, pass.count >= 8 else {
            showAlert("入力エラー", "メールアドレスと8文字以上のパスワードを入力してください")
            return
        }
        Task { @MainActor in
            signUpButton.isEnabled = false
            defer { signUpButton.isEnabled = true }
            guard let auth = AuthClient() else {
                showAlert("設定エラー", "Supabaseの設定が見つかりません。Info.plistの SupabaseURL/SupabaseAnonKey を設定してください。")
                return
            }
            do {
                // email_redirect_to を構築
                let info = Bundle.main.infoDictionary
                let base = (info?["EmailRedirectBase"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let host = (info?["EmailRedirectHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let scheme = (info?["OAuthRedirectScheme"] as? String) ?? "kokosos"
                let redirect: String
                if let b = base, !b.isEmpty {
                    redirect = b.replacingOccurrences(of: "/$", with: "", options: .regularExpression) + "/auth/callback"
                } else if let h = host, !h.isEmpty {
                    redirect = "https://\(h)/auth/callback"
                } else {
                    redirect = "\(scheme)://oauth-callback"
                }
                if let token = try await auth.signUp(email: email, password: pass, redirectTo: redirect) {
                    api.setAuthToken(token)
                    UserDefaults.standard.set(true, forKey: "ShouldShowRecipientsOnboardingOnce")
                    let main = MainViewController()
                    navigationController?.setViewControllers([main], animated: true)
                } else {
                    showAlert("確認メールを送信", "メールのリンクを開いて登録を完了してください。完了後、ログインしてください。")
                }
            } catch {
                showAlert("サインアップ失敗", error.localizedDescription)
            }
        }
    }

    private func showAlert(_ title: String, _ msg: String) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

