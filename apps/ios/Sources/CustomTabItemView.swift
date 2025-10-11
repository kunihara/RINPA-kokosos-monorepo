import UIKit

final class CustomTabItemView: UIControl {
    private let stack = UIStackView()
    let imageView = UIImageView()
    let titleLabel = UILabel()

    var selectedTintColor: UIColor = .label { didSet { applyStyle() } }
    var normalTintColor: UIColor = .secondaryLabel { didSet { applyStyle() } }
    // タップしやすさ向上のためのヒット拡張（非対称対応）
    var extraHitOutset: CGFloat = 20 { didSet { hitOutsets = UIEdgeInsets(top: extraHitOutset, left: extraHitOutset, bottom: extraHitOutset, right: extraHitOutset) } }
    var hitOutsets: UIEdgeInsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

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
        // 上寄せで配置（スペーサは使わず、上側に寄せる）
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            imageView.heightAnchor.constraint(equalToConstant: 28),
            imageView.widthAnchor.constraint(equalToConstant: 28)
        ])

        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyStyle() {
        let tint = isSelected ? selectedTintColor : normalTintColor
        imageView.tintColor = tint
        titleLabel.textColor = tint
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // コントロールの周囲にヒット領域を拡張（最小56pt四方を目標）。非対称拡張に対応。
        let minSide: CGFloat = 56
        var bounds = self.bounds.inset(by: UIEdgeInsets(top: -hitOutsets.top, left: -hitOutsets.left, bottom: -hitOutsets.bottom, right: -hitOutsets.right))
        let addW = max(0, (minSide - bounds.width) / 2)
        let addH = max(0, (minSide - bounds.height) / 2)
        bounds = bounds.insetBy(dx: -addW, dy: -addH)
        return bounds.contains(point)
    }
}
