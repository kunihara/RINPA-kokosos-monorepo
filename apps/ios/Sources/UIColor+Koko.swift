import UIKit

extension UIColor {
    // ブランド赤: #FF7170
    static let kokoRed: UIColor = UIColor(red: 1.0, green: 0.443, blue: 0.439, alpha: 1.0)

    // 帰るモードのボタン/ベタ用（Light/Dark最適化）
    // Light: より濃いグレー(systemGray)  / Dark: 中間グレー(systemGray4)
    static let homeButtonFill: UIColor = UIColor { tc in
        if tc.userInterfaceStyle == .dark { return .systemGray4 }
        return .systemGray
    }
}
