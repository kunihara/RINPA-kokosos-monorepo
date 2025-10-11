import UIKit

extension UIColor {
    // ブランド赤: #FF7170
    static let kokoRed: UIColor = UIColor(red: 1.0, green: 0.443, blue: 0.439, alpha: 1.0)

    // 帰るモードのボタン/ベタ用（Light/Dark最適化）
    // リクエストによりもう少し濃いトーンへ調整
    // Light: darkGray（視認性の高い濃いグレー） / Dark: systemGray3（やや明るめの中間グレー）
    static let homeButtonFill: UIColor = UIColor { tc in
        if tc.userInterfaceStyle == .dark { return .systemGray3 }
        return .darkGray
    }
}
