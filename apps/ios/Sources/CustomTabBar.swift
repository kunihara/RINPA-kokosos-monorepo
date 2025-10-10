import UIKit

final class CustomTabBar: UITabBar {
    private let barLayer = CAShapeLayer()
    private let archLayer = CAShapeLayer()
    var archRadius: CGFloat = 34
    var archWidth: CGFloat = 86
    var barCorner: CGFloat = 16
    var barHeightExtra: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundImage = UIImage()
        shadowImage = UIImage()
        isTranslucent = true
        layer.insertSublayer(barLayer, at: 0)
        layer.insertSublayer(archLayer, above: barLayer)
        clipsToBounds = false
        layer.masksToBounds = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLayers()
    }

    private func layoutLayers() {
        let w = bounds.width
        let h = bounds.height + barHeightExtra
        let topY: CGFloat = 0

        // Bar background (rounded top corners)
        let barPath = UIBezierPath()
        barPath.move(to: CGPoint(x: 0, y: topY + archRadius))
        barPath.addLine(to: CGPoint(x: 0, y: h))
        barPath.addLine(to: CGPoint(x: w, y: h))
        barPath.addLine(to: CGPoint(x: w, y: topY + archRadius))
        barPath.addQuadCurve(to: CGPoint(x: w - barCorner, y: topY), controlPoint: CGPoint(x: w, y: topY))
        barPath.addLine(to: CGPoint(x: barCorner, y: topY))
        barPath.addQuadCurve(to: CGPoint(x: 0, y: topY + archRadius), controlPoint: CGPoint(x: 0, y: topY))
        barLayer.path = barPath.cgPath
        barLayer.fillColor = UIColor.systemBackground.cgColor
        barLayer.shadowColor = UIColor.black.cgColor
        barLayer.shadowOpacity = 0.08
        barLayer.shadowRadius = 8
        barLayer.shadowOffset = CGSize(width: 0, height: -2)
        barLayer.frame = bounds

        // Red arch behind the center button
        let cx = w / 2
        let half = archWidth / 2
        let archHeight: CGFloat = archRadius + 12
        let archPath = UIBezierPath()
        archPath.move(to: CGPoint(x: cx - half, y: topY))
        // upper semicircle
        archPath.addArc(withCenter: CGPoint(x: cx, y: topY), radius: archRadius, startAngle: .pi, endAngle: 0, clockwise: true)
        archPath.addLine(to: CGPoint(x: cx + half, y: archHeight))
        archPath.addLine(to: CGPoint(x: cx - half, y: archHeight))
        archPath.close()
        archLayer.path = archPath.cgPath
        archLayer.fillColor = UIColor.systemRed.cgColor
        archLayer.frame = bounds
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var s = super.sizeThatFits(size)
        s.height += barHeightExtra
        return s
    }
}

