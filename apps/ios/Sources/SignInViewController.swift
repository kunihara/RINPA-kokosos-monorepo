import UIKit

final class SignInViewController: UIViewController {
    private let titleLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = UIButton(type: .system)
    private let stack = UIStackView()
    private let infoLabel = UILabel()

    private let api = APIClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "サインイン"
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

        passwordField.placeholder = "パスワード"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect

        signInButton.setTitle("サインイン", for: .normal)
        signInButton.addTarget(self, action: #selector(tapSignIn), for: .touchUpInside)

        infoLabel.text = "Apple/Google/Facebookは後で追加予定です。まずはメールとパスワードでサインインしてください。"
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, emailField, passwordField, signInButton, infoLabel].forEach { stack.addArrangedSubview($0) }
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func tapSignIn() {
        guard let email = emailField.text, !email.isEmpty, let pass = passwordField.text, !pass.isEmpty else {
            showAlert("入力エラー", "メールとパスワードを入力してください")
            return
        }
        Task { @MainActor in
            signInButton.isEnabled = false
            defer { signInButton.isEnabled = true }
            guard let auth = AuthClient() else {
                showAlert("設定エラー", "Supabaseの設定が見つかりません。Info.plistの SupabaseURL / SupabaseAnonKey を設定してください。")
                return
            }
            do {
                let token = try await auth.signIn(email: email, password: pass)
                api.setAuthToken(token)
                // ルートをMainへ切替
                let main = MainViewController()
                navigationController?.setViewControllers([main], animated: true)
            } catch {
                showAlert("サインイン失敗", error.localizedDescription)
            }
        }
    }

    private func showAlert(_ title: String, _ msg: String) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

