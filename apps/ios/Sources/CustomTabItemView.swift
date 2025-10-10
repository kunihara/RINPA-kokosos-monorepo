import UIKit

final class CustomTabItemView: UIControl {
    private let stack = UIStackView()
    let imageView = UIImageView()
    let titleLabel = UILabel()

    var selectedTintColor: UIColor = .label { didSet { applyStyle() } }
    var normalTintColor: UIColor = .secondaryLabel { didSet { applyStyle() } }

    override var isSelected: Bool { didSet { applyStyle() } }

    init(title: String, image: UIImage?) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title

        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 0 // ほぼ詰める
        stack.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = image?.withRenderingMode(.alwaysTemplate)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 24),
            imageView.widthAnchor.constraint(equalToConstant: 24)
        ])

        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyStyle() {
        let tint = isSelected ? selectedTintColor : normalTintColor
        imageView.tintColor = tint
        titleLabel.textColor = tint
    }
}
