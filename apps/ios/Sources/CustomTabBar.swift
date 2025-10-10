import UIKit

final class CustomTabBar: UITabBar {
    private let barLayer = CAShapeLayer()
    private let archLayer = CAShapeLayer()
    // アーチをさらに広げる（セミサークル半径）
    var archRadius: CGFloat = 48
    // SOSの赤アーチのみを下方向にオフセット
    var archYOffset: CGFloat = 12

    // カスタムヒット優先（中央SOS/左右項目へタッチを振り分ける）
    weak var centerHitView: UIView?
    weak var leftHitView: UIView?
    weak var rightHitView: UIView?
    var barCorner: CGFloat = 16
    // 追加の高さは最小に（全体を薄く）
    var barHeightExtra: CGFloat = 0
    // 望ましいタブバー高さ（SafeArea下端を含めて計算）
    // 白背景をさらに広げる
    var desiredBarHeight: CGFloat = 80

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
        // 白背景を最大化（最上部から描画）
        let topY: CGFloat = 0

        // Bar background (rounded top corners)
        let barPath = UIBezierPath()
        // 白背景の角丸は archRadius ではなく barCorner を使用
        barPath.move(to: CGPoint(x: 0, y: topY + barCorner))
        barPath.addLine(to: CGPoint(x: 0, y: h))
        barPath.addLine(to: CGPoint(x: w, y: h))
        barPath.addLine(to: CGPoint(x: w, y: topY + barCorner))
        barPath.addQuadCurve(to: CGPoint(x: w - barCorner, y: topY), controlPoint: CGPoint(x: w, y: topY))
        barPath.addLine(to: CGPoint(x: barCorner, y: topY))
        barPath.addQuadCurve(to: CGPoint(x: 0, y: topY + barCorner), controlPoint: CGPoint(x: 0, y: topY))
        barLayer.path = barPath.cgPath
        barLayer.fillColor = UIColor.systemBackground.cgColor
        barLayer.shadowColor = UIColor.black.cgColor
        barLayer.shadowOpacity = 0.08
        barLayer.shadowRadius = 8
        barLayer.shadowOffset = CGSize(width: 0, height: -2)
        barLayer.frame = bounds

        // Red arch behind the center button（下方向へオフセット可能）
        // Ensure symmetry: the rectangular sides align exactly under the semicircle endpoints.
        let cx = w / 2
        let archTop = topY + archYOffset
        let leftX = cx - archRadius
        let rightX = cx + archRadius
        let archPath = UIBezierPath()
        // Start at left arc endpoint
        archPath.move(to: CGPoint(x: leftX, y: archTop))
        // Draw upper semicircle
        archPath.addArc(withCenter: CGPoint(x: cx, y: archTop), radius: archRadius, startAngle: .pi, endAngle: 0, clockwise: true)
        // Extend straight down to the bottom of the bar, then across, then back up
        archPath.addLine(to: CGPoint(x: rightX, y: h))
        archPath.addLine(to: CGPoint(x: leftX, y: h))
        archPath.close()
        archLayer.path = archPath.cgPath
        archLayer.fillColor = UIColor.systemRed.cgColor
        archLayer.frame = bounds
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var s = super.sizeThatFits(size)
        let bottom = safeAreaInsets.bottom
        s.height = desiredBarHeight + bottom
        return s
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 最優先: 中央SOSボタン
        if let v = centerHitView, v.isUserInteractionEnabled, !v.isHidden, v.alpha > 0.01 {
            let p = v.convert(point, from: self)
            if v.point(inside: p, with: event) { return v.hitTest(p, with: event) ?? v }
        }
        // 次に左右のカスタム項目
        if let v = leftHitView, v.isUserInteractionEnabled, !v.isHidden, v.alpha > 0.01 {
            let p = v.convert(point, from: self)
            if v.point(inside: p, with: event) { return v.hitTest(p, with: event) ?? v }
        }
        if let v = rightHitView, v.isUserInteractionEnabled, !v.isHidden, v.alpha > 0.01 {
            let p = v.convert(point, from: self)
            if v.point(inside: p, with: event) { return v.hitTest(p, with: event) ?? v }
        }
        return super.hitTest(point, with: event)
    }
}
