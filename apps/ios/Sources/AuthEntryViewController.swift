import UIKit

final class AuthEntryViewController: UIViewController {
    private let titleLabel = UILabel()
    private let signInButton = UIButton(type: .system)
    private let signUpButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "ようこそ"
        setupUI()
    }

    private func setupUI() {
        titleLabel.text = "KokoSOS"
        titleLabel.font = .boldSystemFont(ofSize: 28)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        signInButton.setTitle("ログイン", for: .normal)
        signInButton.addTarget(self, action: #selector(tapSignIn), for: .touchUpInside)
        signInButton.translatesAutoresizingMaskIntoConstraints = false

        signUpButton.setTitle("新規登録", for: .normal)
        signUpButton.addTarget(self, action: #selector(tapSignUp), for: .touchUpInside)
        signUpButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(signInButton)
        view.addSubview(signUpButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            signInButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 48),
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            signUpButton.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 16),
            signUpButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func tapSignIn() {
        navigationController?.pushViewController(SignInViewController(), animated: true)
    }

    @objc private func tapSignUp() {
        navigationController?.pushViewController(SignUpViewController(), animated: true)
    }
}

