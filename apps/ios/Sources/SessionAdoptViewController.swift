import UIKit

final class SessionAdoptViewController: UIViewController {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let continueButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "ログインの確認"
        setupUI()
    }

    private func setupUI() {
        titleLabel.text = "前回のログイン情報が見つかりました"
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.textAlignment = .center

        messageLabel.text = "この端末で前回のログインを引き継ぎますか？"
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel

        continueButton.setTitle("引き継いで続ける", for: .normal)
        continueButton.addTarget(self, action: #selector(tapContinue), for: .touchUpInside)

        signOutButton.setTitle("ログアウトしてやり直す", for: .normal)
        signOutButton.setTitleColor(.systemRed, for: .normal)
        signOutButton.addTarget(self, action: #selector(tapSignOut), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, continueButton, signOutButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func tapContinue() {
        UserDefaults.standard.set(true, forKey: "HasLaunchedOnce")
        let main = MainViewController()
        navigationController?.setViewControllers([main], animated: true)
    }

    @objc private func tapSignOut() {
        Task { @MainActor in
            try? await SupabaseAuthAdapter.shared.client.auth.signOut()
            await SupabaseAuthAdapter.shared.updateCachedToken()
            UserDefaults.standard.set(true, forKey: "HasLaunchedOnce")
            let signin = SignInViewController()
            navigationController?.setViewControllers([signin], animated: true)
        }
    }
}

