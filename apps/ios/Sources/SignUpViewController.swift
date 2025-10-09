import UIKit
import Supabase

final class SignUpViewController: UIViewController, UITextFieldDelegate {
    private let titleLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let signUpButton = UIButton(type: .system)
    private let infoLabel = UILabel()
    private let oauthInfoLabel = UILabel()
    private let oauthStack = UIStackView()

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
        emailField.returnKeyType = .next
        emailField.delegate = self

        passwordField.placeholder = "パスワード（8文字以上）"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        passwordField.returnKeyType = .done
        passwordField.delegate = self

        signUpButton.setTitle("登録する", for: .normal)
        signUpButton.addTarget(self, action: #selector(tapSignUp), for: .touchUpInside)

        infoLabel.text = "登録後に確認メールを送信します。メール内のリンクから確認を完了してください。"
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        // OAuth セクション
        oauthInfoLabel.text = "他の方法で続行"
        oauthInfoLabel.font = .systemFont(ofSize: 13)
        oauthInfoLabel.textColor = .secondaryLabel
        oauthInfoLabel.textAlignment = .center
        oauthStack.axis = .vertical
        oauthStack.spacing = 8
        let appleBtn = makeOAuthButton(title: "Appleで続ける") { [weak self] in self?.startOAuth("apple") }
        let googleBtn = makeOAuthButton(title: "Googleで続ける") { [weak self] in self?.startOAuth("google") }
        let fbBtn = makeOAuthButton(title: "Facebookで続ける") { [weak self] in self?.startOAuth("facebook") }
        [appleBtn, googleBtn, fbBtn].forEach { oauthStack.addArrangedSubview($0) }

        let stack = UIStackView(arrangedSubviews: [titleLabel, emailField, passwordField, signUpButton, infoLabel, oauthInfoLabel, oauthStack])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // キーボードを閉じるアクセサリ & タップで閉じる
        let kbToolbar = makeKeyboardAccessoryToolbar()
        emailField.inputAccessoryView = kbToolbar
        passwordField.inputAccessoryView = kbToolbar
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func tapSignUp() {
        guard let email = emailField.text, !email.isEmpty, let pass = passwordField.text, pass.count >= 8 else {
            showAlert("入力エラー", "メールアドレスと8文字以上のパスワードを入力してください")
            return
        }
        Task { @MainActor in
            signUpButton.isEnabled = false
            defer { signUpButton.isEnabled = true }
            do {
                // Workers経由でユーザー作成 + 確認メール送信
                let info = Bundle.main.infoDictionary
                let base = (info?["EmailRedirectBase"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let host = (info?["EmailRedirectHost"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let scheme = (info?["OAuthRedirectScheme"] as? String) ?? "kokosos"
                let redirectURL: URL
                if let b = base, !b.isEmpty, let u = URL(string: b.replacingOccurrences(of: "/$", with: "", options: .regularExpression) + "/auth/callback") {
                    redirectURL = u
                } else if let h = host, !h.isEmpty, let u = URL(string: "https://\(h)/auth/callback") {
                    redirectURL = u
                } else {
                    redirectURL = URL(string: "\(scheme)://oauth-callback")!
                }
                try await AuthEmailClient().signUp(email: email, password: pass, redirectTo: redirectURL)
                showAlert("確認メールを送信", "メールのリンクを開いて登録を完了してください。完了後、サインインしてください。")
            } catch {
                let raw = error.localizedDescription
                let lower = raw.lowercased()
                // 既存メールでのサインアップ（GoTrueの一般的な文言: "User already registered" など）
                if lower.contains("already registered") || lower.contains("already exists") || raw.contains("既に") || raw.contains("すでに") {
                    let a = UIAlertController(title: "すでに登録済みです", message: "このメールアドレスは既に登録されています。サインインしてください。", preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
                    a.addAction(UIAlertAction(title: "サインインへ", style: .default, handler: { [weak self] _ in
                        self?.goBackToSignIn()
                    }))
                    self.presentAlertController(a)
                }
                // リクエスト頻度制限（60秒に1回など）
                else if lower.contains("once every") || lower.contains("60 seconds") || lower.contains("too many requests") {
                    showAlert("しばらく待ってから再試行", "短時間に複数回リクエストされました。1分ほど待ってからもう一度お試しください。")
                } else {
                    showAlert("サインアップ失敗", raw)
                }
            }
        }
    }

    private func showAlert(_ title: String, _ msg: String) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlertController(a)
    }

    private func presentAlertController(_ alert: UIAlertController) {
        func topViewController(from vc: UIViewController?) -> UIViewController? {
            if let nav = vc as? UINavigationController { return topViewController(from: nav.visibleViewController) }
            if let tab = vc as? UITabBarController { return topViewController(from: tab.selectedViewController) }
            if let presented = vc?.presentedViewController { return topViewController(from: presented) }
            return vc
        }
        DispatchQueue.main.async {
            let root = self.view.window?.rootViewController
            let presenter = topViewController(from: root) ?? topViewController(from: self) ?? self
            presenter.present(alert, animated: true)
        }
    }

    private func goBackToSignIn() {
        if let nav = navigationController {
            if let target = nav.viewControllers.first(where: { $0 is SignInViewController }) {
                nav.popToViewController(target, animated: true)
            } else {
                nav.popViewController(animated: true)
            }
        } else {
            dismiss(animated: true)
        }
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
                // サインアップ画面からのOAuthは新規/既存の区別が難しいため、オンボーディングを促す
                UserDefaults.standard.set(true, forKey: "ShouldShowRecipientsOnboardingOnce")
                let main = MainViewController()
                navigationController?.setViewControllers([main], animated: true)
                // OAuth後にデバイス登録を試行
                PushRegistrationService.shared.ensureRegisteredIfPossible()
            } catch {
                showAlert("サインイン失敗", error.localizedDescription)
            }
        }
    }
}
