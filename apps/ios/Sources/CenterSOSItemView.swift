import UIKit

final class CenterSOSItemView: UIControl {
    var archRadius: CGFloat = 48 { didSet { setNeedsLayout() } }
    var archCenterOffset: CGFloat = 24 { didSet { setNeedsLayout() } }
    var circleSize: CGFloat = 64 { didSet { setNeedsLayout() } }
    var drawArch: Bool = true { didSet { setNeedsLayout() } }

    private let archLayer = CAShapeLayer()
    private let circleButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = true
        archLayer.fillColor = UIColor.kokoRed.cgColor
        archLayer.strokeColor = UIColor.clear.cgColor
        layer.addSublayer(archLayer)

        circleButton.translatesAutoresizingMaskIntoConstraints = false
        circleButton.backgroundColor = .white
        circleButton.setImage((UIImage(systemName: "bell.and.waveform") ?? UIImage(systemName: "bell.fill"))?.withRenderingMode(.alwaysTemplate), for: .normal)
        circleButton.tintColor = .kokoRed
        circleButton.isUserInteractionEnabled = false // ヒットはこのビューに集約
        addSubview(circleButton)

        NSLayoutConstraint.activate([
            circleButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleButton.centerYAnchor.constraint(equalTo: topAnchor, constant: archCenterOffset),
            circleButton.widthAnchor.constraint(equalToConstant: circleSize),
            circleButton.heightAnchor.constraint(equalToConstant: circleSize)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        archLayer.frame = bounds

        // Update circle corner
        circleButton.layer.cornerRadius = circleSize / 2
        if #available(iOS 13.0, *) { circleButton.layer.cornerCurve = .continuous }

        // Update constraints if size changed
        for c in constraints where (c.firstItem as? UIView) === circleButton && c.firstAttribute == .width {
            c.constant = circleSize
        }
        for c in constraints where (c.firstItem as? UIView) === circleButton && c.firstAttribute == .height {
            c.constant = circleSize
        }
        for c in constraints where (c.firstItem as? UIView) === circleButton && c.firstAttribute == .centerY && c.secondAttribute == .top {
            c.constant = archCenterOffset
        }

        // Draw arch path (semi-circle + rectangle to bottom)
        let w = bounds.width
        let h = bounds.height
        let cx = w / 2
        let topY = archCenterOffset
        let leftX = cx - archRadius
        let rightX = cx + archRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if drawArch && archRadius > 0 {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: leftX, y: topY))
            p.addArc(withCenter: CGPoint(x: cx, y: topY), radius: archRadius, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addLine(to: CGPoint(x: rightX, y: h))
            p.addLine(to: CGPoint(x: leftX, y: h))
            p.close()
            archLayer.path = p.cgPath
        } else {
            archLayer.path = nil
        }
        CATransaction.commit()
    }

    func applyActiveStyle(_ active: Bool) {
        if active {
            circleButton.backgroundColor = .kokoRed
            circleButton.tintColor = .white
            // アクティブ時は白い枠を付与
            circleButton.layer.borderWidth = 2
            circleButton.layer.borderColor = UIColor.white.cgColor
        } else {
            circleButton.backgroundColor = .white
            circleButton.tintColor = .kokoRed
            circleButton.layer.borderWidth = 2
            circleButton.layer.borderColor = UIColor.kokoRed.cgColor
        }
    }

    // タップ可能領域は円の少し外側まで許容（タップしやすさ向上）
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let cx = bounds.width/2
        let cy = archCenterOffset
        let dx = point.x - cx
        let dy = point.y - cy
        let r = max(circleSize/2 + 10, 1) // +10ptの余白を許容
        return (dx*dx + dy*dy) <= (r*r)
    }

    // タップされたら自身のイベントとして送出
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let t = touches.first else { return }
        if point(inside: t.location(in: self), with: event) {
            sendActions(for: .touchUpInside)
        }
    }
}
