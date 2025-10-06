import UIKit

final class AddEmailCell: UITableViewCell, UITextFieldDelegate {
    let textField = UITextField()
    let removeButton = UIButton(type: .system)
    var onChange: ((String) -> Void)?
    var onRemove: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        textField.placeholder = "メールアドレス"
        textField.autocapitalizationType = .none
        textField.keyboardType = .emailAddress
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.delegate = self

        removeButton.setTitle("−", for: .normal)
        removeButton.titleLabel?.font = .boldSystemFont(ofSize: 20)
        removeButton.setContentHuggingPriority(.required, for: .horizontal)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.addTarget(self, action: #selector(tapRemove), for: .touchUpInside)

        contentView.addSubview(textField)
        contentView.addSubview(removeButton)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            removeButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 32)
        ])

        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func editingChanged() { onChange?(textField.text ?? "") }
    @objc private func tapRemove() { onRemove?() }
}

