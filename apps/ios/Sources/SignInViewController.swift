import UIKit
import Supabase

final class SignInViewController: UIViewController, UITextFieldDelegate {
    private let titleLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = UIButton(type: .system)
    private let signUpLinkButton = UIButton(type: .system)
    // サインアップは別画面に分離
    private let resetButton = UIButton(type: .system)
    private let stack = UIStackView()
    private let oauthStack = UIStackView()
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
        emailField.returnKeyType = .next
        emailField.delegate = self

        passwordField.placeholder = "パスワード"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        passwordField.returnKeyType = .done
        passwordField.delegate = self

        signInButton.setTitle("サインイン", for: .normal)
        signInButton.addTarget(self, action: #selector(tapSignIn), for: .touchUpInside)


        resetButton.setTitle("パスワードをお忘れですか？", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13)
        resetButton.addTarget(self, action: #selector(tapReset), for: .touchUpInside)


        infoLabel.text = "メール+パスワード または SNS でサインイン"
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        oauthStack.axis = .vertical
        oauthStack.spacing = 8
        let appleBtn = makeOAuthButton(title: "Appleで続ける") { [weak self] in self?.startOAuth("apple") }
        let googleBtn = makeOAuthButton(title: "Googleで続ける") { [weak self] in self?.startOAuth("google") }
        let fbBtn = makeOAuthButton(title: "Facebookで続ける") { [weak self] in self?.startOAuth("facebook") }
        [appleBtn, googleBtn, fbBtn].forEach { oauthStack.addArrangedSubview($0) }

        [titleLabel, emailField, passwordField, signInButton, resetButton, infoLabel, oauthStack].forEach { stack.addArrangedSubview($0) }
        // 画面下に「新規登録の方はこちら」導線
        signUpLinkButton.setTitle("新規登録の方はこちら", for: .normal)
        signUpLinkButton.titleLabel?.font = .systemFont(ofSize: 14)
        signUpLinkButton.addTarget(self, action: #selector(openSignUp), for: .touchUpInside)
        stack.addArrangedSubview(signUpLinkButton)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // キーボードを閉じるボタン（アクセサリ）
        let kbToolbar = makeKeyboardAccessoryToolbar()
        emailField.inputAccessoryView = kbToolbar
        passwordField.inputAccessoryView = kbToolbar

        // 画面タップでキーボードを閉じる
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func makeKeyboardAccessoryToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let close = UIBarButtonItem(title: "キーボードを閉じる", style: .plain, target: self, action: #selector(dismissKeyboard))
        toolbar.items = [flex, close]
        return toolbar
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    // MARK: UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField {
            passwordField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    @objc private func tapSignIn() {
        guard let email = emailField.text, !email.isEmpty, let pass = passwordField.text, !pass.isEmpty else {
            showAlert("入力エラー", "メールとパスワードを入力してください")
            return
        }
        Task { @MainActor in
            signInButton.isEnabled = false
            defer { signInButton.isEnabled = true }
            do {
                let client = SupabaseAuthAdapter.shared.client
                // Supabase Swift v2 uses signIn(email:password:)
                try await client.auth.signIn(email: email, password: pass)
                // Mainへ遷移（pop系で戻せるよう push を採用）
                let main = MainViewController()
                navigationController?.pushViewController(main, animated: true)
                // サインイン直後にデバイス登録を試行
                PushRegistrationService.shared.ensureRegisteredIfPossible()
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

    @objc private func openSignUp() { navigationController?.pushViewController(SignUpViewController(), animated: true) }

    @objc private func tapReset() {
        guard let email = emailField.text, !email.isEmpty else {
            showAlert("入力エラー", "登録メールアドレスを入力してください")
            return
        }
        Task { @MainActor in
            resetButton.isEnabled = false
            defer { resetButton.isEnabled = true }
            do {
                // redirect_to は Info から導出（存在しなければ省略）
                let info = Bundle.main.infoDictionary
                let base = (info?["EmailRedirectBase"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let host = (info?["EmailRedirectHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let scheme = (info?["OAuthRedirectScheme"] as? String) ?? "kokosos"
                let redirect: String?
                if let b = base, !b.isEmpty { redirect = b.replacingOccurrences(of: "/$", with: "", options: .regularExpression) + "/auth/callback" }
                else if let h = host, !h.isEmpty { redirect = "https://\(h)/auth/callback" }
                else { redirect = nil }
                let client = SupabaseAuthAdapter.shared.client
                if let redirect, let url = URL(string: redirect) {
                    try await client.auth.resetPasswordForEmail(email, redirectTo: url)
                } else {
                    try await client.auth.resetPasswordForEmail(email)
                }
                showAlert("送信しました", "パスワード再設定メールを送信しました。メール内の手順に従ってください。")
            } catch {
                showAlert("送信失敗", error.localizedDescription)
            }
        }
    }

    // 確認メール再送はUIからは提供しない（混乱防止のため）

    private func makeOAuthButton(title: String, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.backgroundColor = .secondarySystemBackground
        b.layer.cornerRadius = 8
        b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        b.addAction(UIAction(handler: { _ in action() }), for: .touchUpInside)
        return b
    }

    private func startOAuth(_ provider: String) {
        Task { @MainActor in
            do {
                let info = Bundle.main.infoDictionary
                let scheme = (info?["OAuthRedirectScheme"] as? String) ?? "kokosos"
                let redirectURI = URL(string: "\(scheme)://oauth-callback")!
                let client = SupabaseAuthAdapter.shared.client
                let prov: Provider
                switch provider.lowercased() {
                case "apple": prov = .apple
                case "google": prov = .google
                case "facebook": prov = .facebook
                default: prov = .google
                }
                try await client.auth.signInWithOAuth(provider: prov, redirectTo: redirectURI, scopes: "email profile offline_access")
                let main = MainViewController()
                navigationController?.pushViewController(main, animated: true)
            } catch {
                showAlert("サインイン失敗", error.localizedDescription)
            }
        }
    }
}
