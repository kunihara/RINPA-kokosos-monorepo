import UIKit

final class TabBackgroundView: UIView {
    weak var centerRef: UIView?
    var archRadius: CGFloat = 48
    var archYOffset: CGFloat = 24
    var barCorner: CGFloat = 16
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        shape.fillColor = UIColor.clear.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        let topY: CGFloat = 0
        let path = UIBezierPath()
        // White bar background with rounded top
        path.move(to: CGPoint(x: 0, y: topY + barCorner))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w, y: topY + barCorner))
        path.addQuadCurve(to: CGPoint(x: w - barCorner, y: topY), controlPoint: CGPoint(x: w, y: topY))
        path.addLine(to: CGPoint(x: barCorner, y: topY))
        path.addQuadCurve(to: CGPoint(x: 0, y: topY + barCorner), controlPoint: CGPoint(x: 0, y: topY))

        // Arch based on center button
        var archCenterY = topY + archYOffset
        if let ref = centerRef, let sup = ref.superview {
            archCenterY = sup.convert(ref.center, to: self).y
        }
        let cx = w / 2
        let leftX = cx - archRadius
        let rightX = cx + archRadius
        let arch = UIBezierPath()
        arch.move(to: CGPoint(x: leftX, y: archCenterY))
        arch.addArc(withCenter: CGPoint(x: cx, y: archCenterY), radius: archRadius, startAngle: .pi, endAngle: 0, clockwise: true)
        arch.addLine(to: CGPoint(x: rightX, y: h))
        arch.addLine(to: CGPoint(x: leftX, y: h))
        arch.close()

        let combined = UIBezierPath()
        combined.append(path)
        combined.append(arch)
        shape.frame = bounds
        shape.path = combined.cgPath
        shape.fillColor = UIColor.systemBackground.cgColor
    }
}

